#!/bin/bash
# ops/ocrlab/layout-fused.sh — lc-fused: C41's fused rows in each layout-compare run of the five whole-page scans.
#
#   layout-fused.sh <H> <out.tsv> [combo...]      H is $STATE/ocrlab/layout; no combo means every one in H/combos.tsv
#
# For each combination and page among C41's five (s30 Helena 1941, c01 Billings 1926, c02 Kalispell 1939, c03 the
# comic, c04 October 1960) with a published PDF: Tools/count-fused-rows.swift over the source page and the published
# page (its rows kept in H/fused/<combo>-<id>.txt), then fused-regions.py places each ONE-RUN row in the regions the
# run's reader kept (keep/*.crops.tsv and the page image; its verdicts are in its docstring). One row a run:
#   combo id page layout lines joined oneRun twoRuns crossNotJoined spans straddles crossed oneSide none
# vision-off runs have no regions, so their placement columns are `-`. One PDFKit process at a time, seconds each.
set -u
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
OCRLAB="${OCRLAB:-$HOME/.local/share/visionocr-ocrlab}"
here="$(cd "$(dirname "$0")" && pwd)"
[ $# -ge 2 ] || { echo "usage: layout-fused.sh <H> <out.tsv> [combo...]" >&2; exit 2; }
H=$1 out=$2; shift 2
py="$OCRLAB/venv/bin/python"
b="$(mktemp -d -t vo-fused)" || exit 1
trap 'rm -rf "$b"' EXIT
swiftc -O -o "$b/cfr" "$here/../../Tools/count-fused-rows.swift" > "$b/build.log" 2>&1 || { echo "layout-fused: count-fused-rows does not build, see $b/build.log" >&2; exit 1; }
mkdir -p "$H/fused"
if [ $# -eq 0 ]; then set -- $(cut -f1 "$H/combos.tsv"); fi
none='-	-	-	-	-'
{ printf '# layout-compare lc-fused, %s: C41'"'"'s five whole-page scans, page 1, published by score-gate (tools from %s) in %s;\n' \
      "$(date '+%Y-%m-%d %H:%M')" "$(cat "$H/bin/commit" 2>/dev/null || echo '-')" "$H"
  printf '# Tools/count-fused-rows.swift counts (lines joined oneRun twoRuns crossNotJoined, its header says what they are), and\n'
  printf '# ops/ocrlab/fused-regions.py places each oneRun row in the regions the run'"'"'s reader was given (spans straddles crossed\n'
  printf '# oneSide none, its docstring says what they are). Counts are lower bounds, as C41-FUSED-ACCURATE-2026-10-14 says.\n'
  printf 'combo\tid\tpage\tlayout\tlines\tjoined\toneRun\ttwoRuns\tcrossNotJoined\tspans\tstraddles\tcrossed\toneSide\tnone\n'; } > "$out"
for combo in "$@"; do
    layout=$(/usr/bin/awk -F'\t' -v c="$combo" '$1 == c {print ($9 == "" ? "-" : $9)}' "$H/combos.tsv")
    for pair in "s30 helena" "c01 billings" "c02 kalispell" "c03 comic" "c04 oct1960"; do
        set -- $pair; id=$1 page=$2
        d="$H/runs/$combo/$id"
        pub=$(ls "$d"/pub/*.pdf 2>/dev/null | head -1)
        [ -n "$pub" ] || continue
        txt="$H/fused/$combo-$id.txt"
        "$b/cfr" "$H/pages/$id.pdf" "$pub" 1 500 > "$txt" 2> "$txt.err" || { echo "layout-fused: cfr failed on $combo $id" >&2; continue; }
        counts=$(tail -1 "$txt" | tr ' ' '\n' | /usr/bin/awk -F= '{print $2}' | paste -sd '	' -)
        crops=$(ls "$d"/keep/*.crops.tsv 2>/dev/null | tail -1)
        place=$none
        if [ -n "$crops" ]; then
            img="${crops%.crops.tsv}"; img=$(ls "$img".jpg "$img".png "$img".jpeg 2>/dev/null | head -1)
            if line=$("$py" -I "$here/fused-regions.py" "$txt" "$crops" "$img" --label "$combo" 2>> "$txt.err"); then
                place=$(printf '%s\n' "$line" | cut -f3-7)
                "$py" -I "$here/fused-regions.py" "$txt" "$crops" "$img" --label "$combo" --rows > "$H/fused/$combo-$id.rows.tsv" 2>> "$txt.err"
            else
                echo "layout-fused: fused-regions.py failed on $combo $id, see $txt.err" >&2
            fi
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$combo" "$id" "$page" "${layout:--}" "$counts" "$place" >> "$out"
    done
done
echo "layout-fused: $out"
