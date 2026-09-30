#!/bin/bash
# gemini-read.sh <prompt-file> <image>... — send one prompt and one or more images to Gemini and print the
# text it returns. For truth-second-reader (QUEUE.md). The API key is read here from the Keychain item
# ArchiveProcessor uses and goes to curl on stdin, so it never appears in argv, output, logs or a session.
#
# Every call is logged to $STATE/truth/gemini-usage.tsv with its token counts and cost, and a call is refused
# once the logged spend reaches GEMINI_CAP_USD (default 3, the owner's cap of 2026-09-30).
#   gemini-read.sh --spent        print the spend so far
# Exit: 0 text printed · 3 Gemini refused (RECITATION, SAFETY, blocked) · 4 cap reached · 2 any other error.
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
MODEL="${GEMINI_MODEL:-gemini-3.1-pro-preview}"
CAP="${GEMINI_CAP_USD:-3}"
# USD per million tokens, input and output (thinking tokens are billed as output). Gemini 3 Pro's published
# price for prompts under 200k tokens; check the current price before relying on the cap's accuracy.
PRICE_IN="${GEMINI_PRICE_IN:-2.00}"
PRICE_OUT="${GEMINI_PRICE_OUT:-12.00}"
USAGE="$HOME/.local/state/visionocr-autonomous/truth/gemini-usage.tsv"

spent() { awk -F'\t' 'NR>1{s+=$6} END{printf "%.4f\n", s+0}' "$USAGE" 2>/dev/null || echo 0; }
[ "${1:-}" = "--spent" ] && { spent; exit 0; }
[ $# -ge 2 ] || { echo "usage: gemini-read.sh <prompt-file> <image>..." >&2; exit 2; }
prompt="$1"; shift
[ -f "$prompt" ] || { echo "no prompt file: $prompt" >&2; exit 2; }
[ -f "$USAGE" ] || printf 'time\tmodel\tin\tout\tthoughts\tusd\tfinish\timages\n' > "$USAGE"
if awk -v s="$(spent)" -v c="$CAP" 'BEGIN{exit !(s >= c)}'; then
  echo "cap reached: \$$(spent) of \$$CAP spent" >&2; exit 4
fi

KEY=$(security find-generic-password -s com.archiveprocessor.app -a Gemini -w 2>/dev/null) || KEY=""
[ -n "$KEY" ] || { echo "no Gemini key in the Keychain" >&2; exit 2; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
parts="$tmp/parts.json"
jq -n --rawfile t "$prompt" '[{text: $t}]' > "$parts"
for img in "$@"; do
  [ -f "$img" ] || { echo "no image: $img" >&2; exit 2; }
  case "$img" in *.png) mt=image/png ;; *.jpg|*.jpeg) mt=image/jpeg ;; *) echo "not png/jpeg: $img" >&2; exit 2 ;; esac
  base64 -i "$img" | tr -d '\n' > "$tmp/b64"
  jq --arg mt "$mt" --rawfile d "$tmp/b64" '. + [{inline_data: {mime_type: $mt, data: $d}}]' "$parts" > "$tmp/p2" && mv "$tmp/p2" "$parts"
done
jq -n --slurpfile p "$parts" '{contents: [{parts: $p[0]}], generationConfig: {thinkingConfig: {thinkingLevel: "low"}}}' > "$tmp/body.json"

printf 'x-goog-api-key: %s\n' "$KEY" | curl -sS --max-time 180 -H @- -H 'Content-Type: application/json' \
  --data-binary @"$tmp/body.json" -o "$tmp/resp.json" -w '%{http_code}' \
  "https://generativelanguage.googleapis.com/v1beta/models/$MODEL:generateContent" > "$tmp/code" 2>"$tmp/err"
KEY=""
code=$(cat "$tmp/code")

in=$(jq -r '.usageMetadata.promptTokenCount // 0' "$tmp/resp.json" 2>/dev/null || echo 0)
out=$(jq -r '.usageMetadata.candidatesTokenCount // 0' "$tmp/resp.json" 2>/dev/null || echo 0)
th=$(jq -r '.usageMetadata.thoughtsTokenCount // 0' "$tmp/resp.json" 2>/dev/null || echo 0)
fin=$(jq -r '.candidates[0].finishReason // .promptFeedback.blockReason // "none"' "$tmp/resp.json" 2>/dev/null || echo none)
usd=$(awk -v i="$in" -v o="$out" -v t="$th" -v pi="$PRICE_IN" -v po="$PRICE_OUT" 'BEGIN{printf "%.6f", (i*pi + (o+t)*po)/1e6}')
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$MODEL" "$in" "$out" "$th" "$usd" "$fin" "$#" >> "$USAGE"

if [ "$code" != 200 ]; then
  echo "HTTP $code: $(jq -r '.error.message // empty' "$tmp/resp.json" 2>/dev/null | head -c 300)$(head -c 200 "$tmp/err")" >&2
  exit 2
fi
case "$fin" in
  STOP|MAX_TOKENS) jq -r '[.candidates[0].content.parts[]? | select(.thought != true) | .text // empty] | join("")' "$tmp/resp.json" ;;
  *) echo "refused: $fin" >&2; exit 3 ;;
esac
