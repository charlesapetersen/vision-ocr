#!/bin/bash
# finish-page.sh <page-dir> <checks-dir> <reader-tokens>
# Closes a truth-set page once its checks are read: contested.tsv (contest.py), objects.txt (the OBJECTS
# section of the transcript, which procedure.md lists as its own output), the reader's usage in meta.txt,
# then deletes the page image and its crops (QUEUE.md: they are large, and the daemon parks below 8 GB).
# The word crops in check/ are kept; they are small. Prints `words spots contested unchecked`.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
set -euo pipefail
d=$1 c=$2 tok=$3
here=$(cd "$(dirname "$0")" && pwd)
[ -s "$d/transcript.txt" ] || { echo "no transcript in $d" >&2; exit 1; }
r=$(python3 "$here/contest.py" "$d" "$c")   # refuses a missing or stale spots.tsv, and 0 words
awk '/^OBJECTS:/{f=1; next} f' "$d/transcript.txt" > "$d/objects.txt"
grep -v '^reader_tokens=\|^words=' "$d/meta.txt" > "$d/meta.tmp" || true
printf 'reader_tokens=%s\nwords=%s spots=%s contested=%s unchecked=%s\n' "$tok" $r >> "$d/meta.tmp"
mv "$d/meta.tmp" "$d/meta.txt"
find "$d" -maxdepth 1 \( -name page.png -o -name 'zoom-*.png' \) -delete
[ -d "$d/crops" ] && find "$d/crops" -maxdepth 1 -name 'c*.png' -delete
echo "$r"
