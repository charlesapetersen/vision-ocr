#!/bin/bash
# ops/ocrlab/test-free-mb.sh — free-mb.sh counts purgeable space, never reports less than df, and fails closed.
here="$(cd "$(dirname "$0")" && pwd)"; fail=0
f=$("$here/free-mb.sh" /); d=$(df -m / | awk 'NR==2 {print $4}')
case "$f" in ''|*[!0-9]*) echo "FAIL: not a number: '$f'"; fail=1 ;; esac
# Purgeable space shows as available > df. It is not always present (no local snapshots), so equal is only a
# warning; but on 2026-10-05 there was 56 GB of it, and a free-mb.sh that fell back to df read equal.
if [ "${f:-0}" -gt "$d" ] 2>/dev/null; then echo "ok: / available ${f} MB > df ${d} MB (purgeable counted)"
elif [ "${f:-0}" -eq "$d" ] 2>/dev/null; then echo "WARN: available = df (${f} MB): no purgeable space now, or the Swift probe fell back"
else echo "FAIL: ${f} < df ${d}"; fail=1; fi
z=$("$here/free-mb.sh" /no/such/volume 2>/dev/null)
[ "$z" = 0 ] && echo "ok: no answer reads as 0 MB" || { echo "FAIL: bad path gave '$z'"; fail=1; }
grep -q '"\$here/free-mb.sh"' "$here/try-mlx.sh" && echo "ok: try-mlx uses free-mb.sh" || { echo "FAIL: try-mlx does not use free-mb.sh"; fail=1; }
exit $fail
