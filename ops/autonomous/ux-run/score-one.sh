#!/bin/bash
# score-one.sh <W> <label> <src> <out> : sample pages, run ux-harness, record exit
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
W="$1"; label="$2"; src="$3"; out="$4"
d="$W/scores/$label"; mkdir -p "$d"
if [ ! -f "$out" ]; then echo -e "$label\tNO-OUTPUT\t-\t-" > "$d/status"; exit 0; fi
n=$(qpdf --show-npages "$src" 2>/dev/null)
if [ -z "$n" ]; then echo -e "$label\tSRC-UNREADABLE\t-\t-" > "$d/status"; exit 0; fi
max="${SAMPLE_ALL_UPTO:-0}"
if [ "$n" -le "$max" ]; then pages=$(seq 1 "$n" | paste -sd, -)
else pages=$(for p in 1 $(( (n+3)/4 )) $(( (n+1)/2 )) $(( (3*n+3)/4 )); do [ "$p" -ge 1 ] && echo $p; done | sort -nu | paste -sd, -); fi
start=$(date +%s)
"$W/ux" "$src" "$out" "$d" "$pages" > "$d/stdout.tsv" 2> "$d/stderr.txt"
rc=$?
echo -e "$label\tEXIT-$rc\t$n\t$pages\t$(( $(date +%s) - start ))" > "$d/status"
# keep renders only for red pages
if [ -f "$d/pages.tsv" ]; then
  awk -F'\t' 'NR>1 && $NF=="-" {print $1}' "$d/pages.tsv" | while read -r p; do rm -f "$d/renders/p$p-"*; done
fi
