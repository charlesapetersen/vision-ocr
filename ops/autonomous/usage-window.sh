#!/usr/bin/env bash
# ops/autonomous/usage-window.sh — how much of the five-hour usage window is spent, from the session's own log.
#
# `claude -p --output-format stream-json` writes a `rate_limit_event` into the session log as the session runs,
# with `utilization` (0-1) and `resetsAt` (epoch seconds) for the five-hour window. This prints the latest one.
# A session calls it to decide whether to hand out subagents or work alone (resume prompt, USAGE
# WINDOW); the daemon calls it with --raw after each session and before launching the next.
#
# USAGE:  usage-window.sh [--raw] [LOG]    LOG defaults to $STATE/last-session.log
# OUTPUT: "five-hour window 73% used, resets 18:10 (in 67 min)"; with --raw, "73 1790555400".
# EXIT:   0 known · 3 no rate_limit_event in the log yet
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

raw=0; [ "${1:-}" = "--raw" ] && { raw=1; shift; }
STATE="${VISIONOCR_STATE:-$HOME/.local/state/visionocr-autonomous}"
LOG="${1:-$STATE/last-session.log}"

ev="$(grep -o '"five_hour":{"utilization":[0-9.]*,"resetsAt":[0-9]*' "$LOG" 2>/dev/null | tail -1)"
[ -n "$ev" ] || { [ "$raw" = 1 ] || echo "five-hour window: unknown (no rate_limit_event in $LOG yet)"; exit 3; }
util="$(printf '%s' "$ev" | sed -E 's/.*"utilization":([0-9.]*).*/\1/')"
reset="$(printf '%s' "$ev" | sed -E 's/.*"resetsAt":([0-9]*).*/\1/')"
pct="$(awk -v u="$util" 'BEGIN{printf "%d", u*100 + 0.5}')"

if [ "$raw" = 1 ]; then
  echo "$pct $reset"
else
  mins=$(( (reset - $(date +%s)) / 60 ))
  if [ "$mins" -ge 0 ]; then
    echo "five-hour window ${pct}% used, resets $(date -r "$reset" '+%H:%M') (in ${mins} min)"
  else
    echo "five-hour window ${pct}% used as of the last event; that window reset at $(date -r "$reset" '+%H:%M')"
  fi
fi
