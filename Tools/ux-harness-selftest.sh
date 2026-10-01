#!/bin/bash
# Does Tools/ux-harness catch what the owner caught, and stay green on pages that look right in Preview?
#
#   Tools/ux-harness-selftest.sh [green-dir]
#
# RED: the owner's reports, on the owner's files in $STATE/owner-supplied/ (never committed: they are
# third-party copyrighted). Each named page must carry the named flag.
#   Why at 24a8f6a pp5-6      legibility   (BUGS.md C38: text illegible in PDFKit)
#   Why at 1.14.0 p5          colour       (C32: the red headings published black)
#   Raskin at 24a8f6a p1      selection and copy (C34/C39: drags cross columns, misread words)
#   Hughes (Desktop copy) at 24a8f6a p5   selection (a drag that leaves its column)
# GREEN: pages of the current pipeline's output that were looked at in PDFKit renders and read right:
#   Why pp3-8, Briefer pp1-6, Hughes (Desktop copy 2026-09-26) pp1-3, 5, 7-9. Every one must have no flag.
#   Left out, because the harness is right that they are wrong: Why p9 (a drag down the left column
#   takes 13 lines of the right one), Why p10 (the red logo is grey, C38), Hughes p6 (the text layer runs
#   across both columns row by row), Hughes p4 (the diagram's labels are not in the text layer).
# CONTESTED: a word the truth-harness re-read did not confirm (`contested-harness.tsv`) is not scored, and
#   a row of it naming another word than the transcript's stops the harness.
# ROTATED (invariant 5): `rotfix.pdf`, built here from Why pp5 and 9 as bitmaps, the second drawn sideways
#   under /Rotate 90 on a page of the other orientation. Page 1 must be green; page 2 must find its
#   columns (2 or more) and not be red for geometry, since the pipeline publishes it upright at /Rotate 0.
#   It is Why p9, so it is red for selection as Why p9 is.
#   `green-dir` holds `1954 - Why.ocr.pdf`, `1951 - Briefer Book Notes.ocr.pdf`,
#   `Hughes - ... (Desktop copy 2026-09-26).ocr.pdf` and `rotfix.ocr.pdf` from the pipeline under test.
#   Without it, this script builds `Tools/score-gate` and the helper from this checkout and publishes the
#   four itself, about four minutes. So a pipeline change that makes one of those pages worse turns this
#   red too. Document flags are printed and do not fail a case: on the current pipeline Briefer loses its
#   page labels and Hughes its title, which are real and belong to `ux-read`.
# The Hughes red case scores the 24a8f6a output of the Desktop copy against the 2026-09-26 file: that is
# the Desktop copy's source (490,599 B, BUGS.md C37).
#
# Exit: 0 every case as expected · 1 a case is not · 3 skipped (the owner's files are not here).
# Run it alone: publishing the green outputs runs the whole app pipeline. Scoring is about 8 s a page.
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE="${VISIONOCR_STATE:-$HOME/.local/state/visionocr-autonomous}"
O="$STATE/owner-supplied"
HUG="Hughes - The Knitting of Racial Groups in Industry (Desktop copy 2026-09-26)"
if [ ! -f "$O/1954 - Why.pdf" ] || [ ! -f "$O/$HUG.pdf" ]; then
    echo "ux-harness-selftest: SKIP, the owner's files are not in $O"; exit 3
fi
W="$(mktemp -d /tmp/ux-selftest.XXXXXX)"
mkdir -p "$W/h"
cp "$ROOT/Tools/ux-harness.swift" "$W/h/main.swift"
swiftc -O -o "$W/ux" "$W/h/main.swift" || { echo "ux-harness-selftest: ux-harness does not build"; exit 1; }
mkdir -p "$W/in" "$W/r"
cat > "$W/r/main.swift" <<'SWIFT'
import PDFKit
// two pages of a source as 2x bitmaps: the first upright, the second drawn sideways under /Rotate 90
let d = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let url = URL(fileURLWithPath: CommandLine.arguments[2])
func bitmap(_ p: PDFPage) -> (CGImage, CGSize) {
    let b = p.bounds(for: .cropBox), W = Int(b.width * 2), H = Int(b.height * 2)
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    ctx.scaleBy(x: 2, y: 2); p.draw(with: .cropBox, to: ctx)
    return (ctx.makeImage()!, b.size)
}
let c = CGContext(url as CFURL, mediaBox: nil, nil)!
let (i1, s1) = bitmap(d.page(at: 4)!)
var m1 = CGRect(origin: .zero, size: s1)
c.beginPage(mediaBox: &m1); c.draw(i1, in: m1); c.endPage()
let (i2, s2) = bitmap(d.page(at: 8)!)
var m2 = CGRect(x: 0, y: 0, width: s2.height, height: s2.width)
c.beginPage(mediaBox: &m2); c.translateBy(x: s2.height, y: 0); c.rotate(by: .pi / 2)
c.draw(i2, in: CGRect(origin: .zero, size: s2)); c.endPage()
c.closePDF()
let r = PDFDocument(url: url)!
r.page(at: 1)!.rotation = 90
r.write(to: url)
SWIFT
swiftc -O -o "$W/mkrot" "$W/r/main.swift" && "$W/mkrot" "$O/1954 - Why.pdf" "$W/in/rotfix.pdf" ||
    { echo "ux-harness-selftest: the rotated fixture was not made"; exit 1; }

GREEN="${1:-}"
if [ -z "$GREEN" ]; then
    GREEN="$W/green"; mkdir -p "$W/g"
    cp "$O/1954 - Why.pdf" "$O/1951 - Briefer Book Notes.pdf" "$O/$HUG.pdf" "$W/in/"
    cp "$ROOT/Tools/score-gate.swift" "$W/g/main.swift"
    ( cd "$ROOT" && swiftc -O -o "$W/gate" -target "$(uname -m)-apple-macos13.0" \
        $(ls Sources/*.swift | grep -v App.swift) "$W/g/main.swift" &&
      swiftc -O -o "$W/visionocr-recognise" -target "$(uname -m)-apple-macos13.0" \
        Sources/{Prefs,Runner,Recogniser,SearchableWriter,Flattener,JBIG2}.swift Helper/main.swift ) \
        > "$W/build.log" 2>&1 || { echo "ux-harness-selftest: the gate does not build, see $W/build.log"; exit 1; }
    VISIONOCR_HELPER="$W/visionocr-recognise" "$W/gate" "$W/in" "$GREEN" > "$W/gate.log" 2>&1
fi

bad=0
# case <label> <source> <output> <pages, space-separated> <expect: flags, `-` for green, or `rotated`>
# Every page asked for must have a row: a crash after page 1, or a page the output lacks, is a FAIL.
case_() {
    local label="$1" src="$2" out="$3" pages="$4" want="$5"
    if [ ! -f "$out" ]; then echo "FAIL  $label: no output $out"; bad=1; return; fi
    "$W/ux" "$src" "$out" "$W/$label" "$(echo $pages | tr ' ' ',')" > "$W/$label.tsv" 2> /dev/null
    echo "      $label document flags: $(awk -F'\t' '$1 == "DOC" {print $NF}' "$W/$label.tsv")"
    local p
    for p in $pages; do
        local flags
        flags="$(awk -F'\t' -v p="$p" '$1 == p {print $NF}' "$W/$label.tsv")"
        if [ -z "$flags" ]; then echo "FAIL  $label p$p: no row"; bad=1; continue; fi
        if [ "$want" = "rotated" ]; then
            local cols
            cols="$(awk -F'\t' -v p="$p" '$1 == p {print $10}' "$W/$label.tsv")"
            case ",$flags," in
                *",geometry,"*|*",unmeasured,"*) echo "FAIL  $label p$p: $flags"; bad=1;;
                *) if [ "$cols" -ge 2 ] 2>/dev/null; then echo "ok    $label p$p: $cols columns, $flags"
                   else echo "FAIL  $label p$p: $cols columns"; bad=1; fi;;
            esac
        elif [ "$want" = "-" ]; then
            if [ "$flags" = "-" ]; then echo "ok    $label p$p green"
            else echo "FAIL  $label p$p should be green, is $flags"; bad=1; fi
        else
            local f miss=""
            for f in $(echo "$want" | tr ',' ' '); do
                case ",$flags," in *",$f,"*) ;; *) miss="$miss $f";; esac
            done
            if [ -z "$miss" ]; then echo "ok    $label p$p red: $flags"
            else echo "FAIL  $label p$p should be red for$miss, is $flags"; bad=1; fi
        fi
    done
}

RASKIN="Raskin - 1956 - New Jobs Opening to Negro in North"
case_ why-24a8f6a    "$O/1954 - Why.pdf" "$O/1954 - Why.ocr-24a8f6a.pdf" "5 6" legibility
case_ why-1.14.0     "$O/1954 - Why.pdf" "$O/1954 - Why.ocr-1.14.0.pdf"  "5"   colour
case_ raskin-24a8f6a "$O/$RASKIN.pdf" "$O/$RASKIN.ocr-24a8f6a.pdf"       "1"   selection,copy
case_ hughes-24a8f6a "$O/$HUG.pdf" "$O/Hughes - The Knitting of Racial Groups in Industry (Desktop copy).ocr-24a8f6a.pdf" "5" selection
case_ green-why      "$O/1954 - Why.pdf" "$GREEN/1954 - Why.ocr.pdf" "3 4 5 6 7 8" -
case_ green-briefer  "$O/1951 - Briefer Book Notes.pdf" "$GREEN/1951 - Briefer Book Notes.ocr.pdf" "1 2 3 4 5 6" -
case_ green-hughes   "$O/$HUG.pdf" "$GREEN/$HUG.ocr.pdf" "1 2 3 5 7 8 9" -
case_ rotated-green  "$W/in/rotfix.pdf" "$GREEN/rotfix.ocr.pdf" "1" -
case_ rotated-cols   "$W/in/rotfix.pdf" "$GREEN/rotfix.ocr.pdf" "2" rotated

# TRUTH (`--truth`): the same pages scored against the truth set's transcripts ($STATE/truth/owner/),
# on the TRUTH rows' own flags. Red where the owner's report is about the text: Raskin p1 and Hughes p5
# at 24a8f6a, and Why p5 at 1.14.0, whose drags leave their columns (copy error 0.69-4.2). Why pp5-6 at
# 24a8f6a are illegible, not wrong: their text scores clean, and their headings' boxes keep none (p5) and
# 38% (p6) of the source's dark ink (`tink`); Why p5 at 1.14.0 keeps none of their colour (`tcolour`).
# Green: Why pp3-8, Hughes pp1-3, 5, 7-9, Briefer pp5-6 (copy error at most 0.048). Briefer pp1-4 are
# RED on the truth although every measure above passes them: the output's text layer lacks 3-10% of the
# page's words, whole lines of clean type (p1: "are even less different from those of the", in the
# source's own layer too), which Vision's reading of the source, the old reference, lacks as well.
TR="$STATE/truth/owner"
case_truth() {
    local label="$1" truth="$2" src="$3" out="$4" pages="$5" want="$6"
    if [ ! -d "$TR/$truth" ]; then echo "skip  $label: no truth set at $TR/$truth"; return; fi
    if [ ! -f "$out" ]; then echo "FAIL  $label: no output $out"; bad=1; return; fi
    "$W/ux" --truth "$TR/$truth" "$src" "$out" "$W/$label" "$(echo $pages | tr ' ' ',')" > "$W/$label.tsv" 2> /dev/null
    local p
    for p in $pages; do
        local flags
        flags="$(awk -F'\t' -v p="$p" '$1 == "TRUTH" && $2 == p {print $NF}' "$W/$label.tsv")"
        if [ -z "$flags" ]; then echo "FAIL  $label p$p: no truth row"; bad=1; continue; fi
        if [ "$want" = "-" ]; then
            if [ "$flags" = "-" ]; then echo "ok    $label p$p green on the truth"
            else echo "FAIL  $label p$p should be green on the truth, is $flags"; bad=1; fi
        else
            case ",$flags," in *",$want,"*) echo "ok    $label p$p red on the truth: $flags";;
                *) echo "FAIL  $label p$p should be red for $want on the truth, is $flags"; bad=1;; esac
        fi
    done
}
case_truth truth-raskin     "$RASKIN" "$O/$RASKIN.pdf" "$O/$RASKIN.ocr-24a8f6a.pdf" "1" tcopy
case_truth truth-hughes     "$HUG" "$O/$HUG.pdf" "$O/Hughes - The Knitting of Racial Groups in Industry (Desktop copy).ocr-24a8f6a.pdf" "5" tcopy
case_truth truth-why-1.14.0 "1954 - Why" "$O/1954 - Why.pdf" "$O/1954 - Why.ocr-1.14.0.pdf" "5" tcopy
case_truth truth-why-colour "1954 - Why" "$O/1954 - Why.pdf" "$O/1954 - Why.ocr-1.14.0.pdf" "5" tcolour
case_truth truth-why-legib  "1954 - Why" "$O/1954 - Why.pdf" "$O/1954 - Why.ocr-24a8f6a.pdf" "5 6" tink
case_truth truth-green-why  "1954 - Why" "$O/1954 - Why.pdf" "$GREEN/1954 - Why.ocr.pdf" "3 4 5 6 7 8" -
case_truth truth-green-hug  "$HUG" "$O/$HUG.pdf" "$GREEN/$HUG.ocr.pdf" "1 2 3 5 7 8 9" -
case_truth truth-green-bri  "1951 - Briefer Book Notes" "$O/1951 - Briefer Book Notes.pdf" "$GREEN/1951 - Briefer Book Notes.ocr.pdf" "5 6" -
case_truth truth-lost-lines "1951 - Briefer Book Notes" "$O/1951 - Briefer Book Notes.pdf" "$GREEN/1951 - Briefer Book Notes.ocr.pdf" "1 2 3 4" tcopy

# CONTESTED BY THE RE-READ: a word in a page's `contested-harness.tsv` (`ops/truth/reread.py`, the words the
# blind re-read did not confirm) is not scored. A copy of Raskin p1's truth page contests every word the
# truth-raskin case scored wrong, beside whatever the page already contests: none may be left wrong, and
# `scored` must fall by exactly that many.
case_contest() {
    local r="$W/truth-raskin" t="$W/contest-truth/p1" f n
    if [ ! -f "$r/truth-words.tsv" ]; then echo "skip  truth-contest: truth-raskin did not run"; return; fi
    mkdir -p "$t"
    for f in "$TR/$RASKIN/p1/"*; do [ "$(basename "$f")" = contested-harness.tsv ] || ln -s "$f" "$t/"; done
    awk -F'\t' 'NR > 1 && $1 == 1 && $3 == "wrong" {print $2}' "$r/truth-words.tsv" | sort -un > "$W/contest-wrong.txt"
    n=$(wc -l < "$W/contest-wrong.txt" | tr -d ' ')
    { cut -f1 "$TR/$RASKIN/p1/contested-harness.tsv" 2> /dev/null; cat "$W/contest-wrong.txt"; } | sort -un > "$t/contested-harness.tsv"
    "$W/ux" --truth "$W/contest-truth" "$O/$RASKIN.pdf" "$O/$RASKIN.ocr-24a8f6a.pdf" "$W/truth-contest" 1 > "$W/truth-contest.tsv" 2> /dev/null
    local b a
    b="$(awk -F'\t' '$1 == "TRUTH" && $2 == 1 {print $5, $7}' "$W/truth-raskin.tsv")"
    a="$(awk -F'\t' '$1 == "TRUTH" && $2 == 1 {print $5, $7}' "$W/truth-contest.tsv")"
    if [ "$n" -gt 0 ] && [ "${a#* }" = 0 ] && [ "${a% *}" = "$(( ${b% *} - n ))" ]; then
        echo "ok    truth-contest: $n contested words left out (scored, wrong: $b -> $a)"
    else echo "FAIL  truth-contest: contesting $n words took scored, wrong from $b to ${a:-no row}"; bad=1; fi
}
case_contest

# A STALE RE-READ: a `contested-harness.tsv` row naming another word than the transcript has at its index
# (a transcript corrected after the re-read moves every later index) must stop the harness, exit 2, rather
# than leave some other word out in silence.
case_stale() {
    local t="$W/stale-truth/p1" f rc=0
    mkdir -p "$t"
    for f in "$TR/$RASKIN/p1/"*; do [ "$(basename "$f")" = contested-harness.tsv ] || ln -s "$f" "$t/"; done
    printf '0\tnot-the-first-word\t?\n' > "$t/contested-harness.tsv"
    "$W/ux" --truth "$W/stale-truth" "$O/$RASKIN.pdf" "$O/$RASKIN.ocr-24a8f6a.pdf" "$W/truth-stale" 1 > "$W/truth-stale.tsv" 2> "$W/truth-stale.err" || rc=$?
    if [ "$rc" = 2 ] && grep -q 'run the re-read again' "$W/truth-stale.err" && ! grep -q '^TRUTH' "$W/truth-stale.tsv"; then
        echo "ok    truth-stale: a re-read row naming another word stops the harness (exit 2)"
    else echo "FAIL  truth-stale: exit $rc and $(grep -c '^TRUTH' "$W/truth-stale.tsv") TRUTH rows, not exit 2 and none"; bad=1; fi
}
case_stale

echo "renders and TSVs: $W"
[ "$bad" = 0 ] && { echo "ux-harness-selftest: PASS"; exit 0; }
echo "ux-harness-selftest: FAIL"; exit 1
