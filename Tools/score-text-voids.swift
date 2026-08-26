// score-text-voids — how much of a page's ink has no word box over it.
//
// C30's instrument, and the first one in `Tools/`. The entry's own §"What a fix has to
// satisfy" asks for exactly this and says why nothing already here can do it:
//
//   **An instrument that starts from the PAGE, not from the observations.** Whatever it
//   is, it must be able to report a page as bad while `words=` reads 100%, or it has
//   inherited the blind spot.
//
// `score-corpus`'s `words=`, `start=`/`end=`, `probe-line-coverage` and `probe-line-edges`
// all count only the words Vision returned, so they read 100% on a page that lost a third
// of its text. This one divides *rows of ink* by *rows of ink no box covers*, so its
// numerator is unreachable from **the observation list** and a page can fail it while all
// four of those pass it. The `--self-test`'s group 5 is that property as a check: a
// fixture whose every box sits exactly on ink — perfect by any observation-based measure —
// reads 40 of 64 inked rows unboxed here.
//
// ⛔ **THE SIBLING, because "no existing instrument can see this" would be FALSE** — found
// by the adversarial review of this file's own first draft, which had claimed exactly that
// (CONTRIBUTING 4b). `Flattener.inkOutsideText` (`Sources/Flattener.swift:1707`) already
// answers a version of the one-line summary at the top, and two committed tools print it:
// `score-shape-term`'s `inkPx`/`outPx`/`inkOut`/`lineN` and `score-text-route`'s `inkOut`.
// It is **strictly stronger than this tool on the x axis** — a pixel measure, not a row
// measure, see the blind spot below — and **weaker on run structure**, returning one
// fraction and unable to say "171 contiguous rows"; it also walks
// `Flattener.interiorWindow`, ignoring the outer sixteenth on every side, where this walks
// the whole sheet. So the honest claim is the narrow one: this is the only instrument here
// that reports unboxed ink **as runs**, and the four named above — not "every existing
// instrument" — are the ones blind by construction.
//
// ⛔ **AND THE BLIND SPOT THAT CHANGES WHAT EVERY NUMBER HERE MEANS: coverage is
// ROW-WISE, so a box anywhere on a row covers the whole row.** `pixelBoxes` discards `x`
// and it never enters the measure. A page whose left column was recognised and whose right
// column was dropped reads `bareRows` 0, `voidInk` 0 and verdict `clean` — identical to a
// perfect page — and so do a lost marginal note beside recognised body text, a dropped
// table column, and the unrecognised half of a two-up scan. C30 is "whole blocks of clean
// body text get no text layer", and a side-by-side block is exactly the case this cannot
// see. **So `bareRows`, `voidInk` and both shares are LOWER BOUNDS on the loss and not
// measurements of it.** Faithful to the reference, which is row-wise too, so it is a limit
// of the measure rather than a defect in the port — and `inkOutsideText` is the thing to
// reach for when the question is two-dimensional.
//
// ⛔ **It recognises the REBUILT BITMAP, not a re-render**, which is the first bullet of
// that same section and the thing every earlier C30 instrument got wrong. Production
// recognises `Flattener.flatten`'s bitmaps (`Sources/Model.swift:1971`, `:2059`);
// `Recogniser.extract` — which `Tools/make-observations` calls, and therefore every
// artefact in `$STATE/c30-instrument/` — recognises `Recogniser.render`'s plain render of
// the source page. Same geometry, different pixels, measured on C30's page 5. So this tool
// takes its pixels AND its boxes from one `Recogniser.loadImage(page)` of what `flatten`
// wrote, and it has no render fallback: if that decode fails the row is a `SKIP` with a
// reason rather than a number measured on some other image. Both `RebuiltPage.Content`
// cases are covered — `score-shape-term` (`:1172`) and `score-text-route` (`:713`) both
// skip `.bilevel` with `verdict: "already 1-bit"`, and a 1-bit page is exactly where C30's
// document lives, so neither can be pointed at it. ⚠️ **They are not the only tools that
// flatten-then-recognise, which a first draft of this claimed**:
// `Tools/score-rebuild-dpi.swift` flattens at `:257` and then drives the whole production
// path at `:287` (`OCRModel.makeSearchablePDF(rebuild: true, …)`) on every route including
// `.bilevel`. It can be pointed at C30's document; it counts characters out of the
// published file rather than measuring ink coverage, which is a different question and not
// a blindness.
//
// ✅ **That it really is production's image is MEASURED, not architectural.** On C30's document this
// tool's `words` equals the published layer's box count exactly on 4 of 6 pages (296 / 445 / 279 /
// 421) and the `make-observations` plain render's on 0 of 6, off by 8 to 47 there — see `BUGS.md` C30
// `#### The instrument, in Tools/ as of 2026-08-25`. If you change how the bitmap is obtained, that
// control is the one to re-run.
//
// ## The two run definitions, and why both are printed
//
// A port of `$STATE/c30-instrument/artefact.py`, the throwaway pass that settled C30's
// fork. It carries TWO measures of the same thing and its own comment says they disagree
// by design — 171 rows against 412 over one block of page 1 — so this prints both rather
// than picking one and losing the comparison with the committed
// `C30-FORK-2026-08-22.tsv` / `C30-PAGE5-2026-08-23.tsv`:
//
//   bareRows / bareShare / longBare        `measure_inkruns`: runs of rows that are
//               INKED and uncovered. A blank line between paragraphs breaks such a run.
//               `longBare` is the entry's headline "171 rows", and `bareShare` is the
//               fork file's `bareShareInkRuns` column — **not** its `bareShare`.
//   voidInk / voidShare / longVoid / voidLongInk
//               `measure`: runs of UNCOVERED rows whatever their ink, then the inked rows
//               inside them. Reads through the interline gaps a dropped block leaves, so
//               it is the larger of the two on the same page. ⛔ **`voidShare` is the
//               column C30's sections quote (0.4446 / 0.2457 / …)**, because
//               `C30-FORK-2026-08-22.tsv` writes `measure`'s share to a column it calls
//               `bareShare` — so the two files' names cross over, and a first draft of
//               this header attributed those figures to the wrong one of these two
//               groups. Taken off that file's header, not inferred.
//   voidN       runs qualifying under `measure`. ⚠️ This one is NOT in the reference —
//               it returns no count — so do not read it as a ported figure. Groups 5-7
//               pin it (1, 1, 2) so that it is not a printed column nothing asserts.
//
// ⚠️ **`bareShare` credits a BOX, not a READING.** C30's page-5 section measured one
// 115-px observation whose entire text is the nonsense word `ASSAME` covering seven lines
// of type, and removing it moved the fresh share 0.2470 → 0.3866. A box over ink is all
// this tool can see; whether the string under it is the words on the page is a question it
// cannot ask, and neither can any of the four instruments it replaces.
//
// ⛔ **And it does not bound scattered single-line drops.** At the reference's
// `VOID_MIN_ROWS` against a ~13-row line pitch, ONE dropped line raises no band —
// asserted as group 4, on a fixture whose five unrecognised lines read `bareRows` 0. Use
// `VOIDMININCH` to vary it; the default is the reference's own value and nothing here
// establishes it as the right one.
//
// ⚠️ **`voidInk > 0` is a weak signal and `clean` may be close to unreachable on a real
// scan.** `voidMeasure` counts any run of ≥ `minRows` uncovered rows, so both margins of
// every page qualify as voids, and one inked speck in a margin — a platen edge, a gutter
// shadow — puts `voidInk` above zero. Blank margins contribute nothing (they are not inked
// rows), so the *shares* are not inflated by margins as such; what is weak is the boolean.
// `Flattener.inkOutsideText` walks `Flattener.interiorWindow` and ignores the outer
// sixteenth on every side for this reason. This tool deliberately does **not**: cropping
// would break the agreement with the reference that is its only external validation. Read
// `bareRows` and the shares; treat "voidInk > 0 on n" in the summary as a count of pages
// with any unboxed ink at all and not as a count of pages that lost something. ⚠️ That the
// boolean fires on most real pages is a prediction from the mechanism, not a measurement:
// it read `bare` on 6 of 6 of the one document run so far, which cannot distinguish the two.
//
// ## The constants, and why they are lengths rather than row counts
//
// The reference ran on `pdftoppm -r 100` PGMs, so its `VOID_MIN_ROWS = 20` and
// `BOX_PAD_PX = 2` are 100-dpi row counts. This tool measures the rebuilt bitmap, which on
// C30's document is 400 dpi, where 20 rows is a twentieth of an inch and every interline
// gap clears it. So both are held as physical lengths — 0.20 in and 0.02 in, which ARE 20
// and 2 rows at 100 dpi — and scaled by each page's own resolution. `minRows` and
// `padRows` are printed per row so the row states its own parameters.
// `INK_ROW_FRACTION` is a fraction of the row's width and needs no scaling.
//
// ⚠️ **So this tool's numbers are NOT expected to reproduce the committed TSVs**, and a
// reader who finds they differ has found nothing: those measure a 100-dpi render of the
// source page against boxes from a published layer or from `make-observations`, and this
// measures a 400-dpi rebuilt bitmap against a fresh recognition of that same bitmap.
// Different pixels, different boxes, different resolution. What IS pinned against the
// reference is the measure itself — groups 3-7 below carry values computed by running
// `artefact.py`'s own `measure`, `measure_inkruns` and `ink_rows` on the same three
// synthetic buffers, so a drift in the port reddens the self-test.
//
// ⛔ **One thing does NOT port, and it was measured rather than assumed:
// `Flattener.otsuThreshold` clamps its answer to `[90, 230]` (`Flattener.swift:1070`) and
// `artefact.py`'s `otsu` does not.** On the self-test's two-valued fixtures the shipped
// function reads **90** where the reference reads **0** — the argmax is identical, every
// t in [0, 254] ties on a bimodal histogram and both take the first maximum, so the clamp
// is the whole difference. Group 2 pins it and pins the consequence: on a bimodal buffer
// both thresholds select the same pixels, so the ink rows are unaffected.
//
// ⚠️ **That equivalence is a property of a two-valued image, so it covers a `.bilevel`
// page and NOT a `jpeg` one.** On a continuous-tone page the clamp can bind for real, and
// then this tool's `inkRows` is production's answer and not the reference's. That is the
// right way round for a tool measuring what production recognised — the shipped threshold
// is the one `flatten` itself thresholds with — but it means a `jpeg` row here is not
// comparable to a reference figure even after the resolution is accounted for. C30's
// document is 1-bit on all six pages, so this is not in C30's way; it is in the way of
// anyone pointing this tool at a tone page and expecting `artefact.py`'s number.
// ⚠️ Nothing here says the clamp is wrong. **`score-shape-term`'s run** measured
// ImageMagick's unclamped OTSU equal to the shipped one on 13 of 13 corpus pages over a
// 69-level range (that tool's header, `:54-56`, records the comparison as one shell line
// against its own `otsu` column), so on real scans the floor does not bind and two-valued
// synthetic buffers are where it does. ⚠️ A first draft of this header credited that
// measurement to `stratify-corpus.py`, which contains no Otsu and no ImageMagick at all —
// `grep -in 'otsu\|magick' Tools/stratify-corpus.py` returns nothing.
//
// ## Building and running
//
//   mkdir -p /tmp/h && cp Tools/score-text-voids.swift /tmp/h/main.swift
//   swiftc -O -o /tmp/score-text-voids -target "$(uname -m)-apple-macos13.0" \
//     $(ls Sources/*.swift | grep -v App.swift) /tmp/h/main.swift
//   /tmp/score-text-voids --self-test
//   /tmp/score-text-voids "<pdf>" [page…]        # 1-indexed; default: a spread of 12
//   VOIDMININCH=0.10 /tmp/score-text-voids "<pdf>" 1
//   TILES=4 /tmp/score-text-voids "<pdf>" 1      # the crop experiment, below
//   TILES=8 TILETEXT=/tmp/dump /tmp/score-text-voids "<pdf>" 5   # …and what it read
//
// ⚠️ The copied file must be named `main.swift` or swiftc rejects top-level code.
//
// ## `TILES=n` — the crop experiment
//
// C30's sharpest finding is that the loss is a property of the image handed to ONE request
// and not of the type: over the same pixels at the same 400 dpi, page 1's bottom half went
// from 84.81% bare to 8.61% purely by being its own request. That was a throwaway pass on
// **one half of one page of one document** and it is reproducible from nothing in this
// tree, which is why tiling — the only candidate fix the entry has — is unpriced.
//
// `TILES=n` runs the same page a second time as `n` equal horizontal bands, each its own
// `VNRecognizeTextRequest`, lifts every band's boxes back into the page's frame and scores
// the union against the SAME ink rows with the SAME constants. The whole-page columns and
// the `t…` columns in one row are therefore two recognitions of one image, differing only
// in how many requests it was cut into.
//
// ⛔ **What it does NOT settle, and the disclosures that go with any figure from it.**
//   * **A band boundary cuts lines.** Nothing overlaps the bands, so up to `n - 1` lines
//     straddle a seam and can come back halved, doubled or not at all. That is a real cost
//     of naive tiling and it is *in* these numbers — read them as a floor on tiling's
//     benefit, not as its ceiling.
//   * **A box is a box.** The measure sees a box's presence and never the string under it,
//     so a band that returns `ASSAME` over a real line counts as covered. C30's page-5
//     section is where that trap cost a headline.
//   * **Coverage is row-wise**, as everywhere else in this tool: a box anywhere on a row
//     covers the row, so a tiled arm that recovers one column of a two-column page reads
//     as well as one that recovers both.
//   * ⛔ **THE PADDING IS A CONFOUND AND IT IS NOT SMALL.** `coveredRows` pads every box
//     by `padRows` top and bottom — 8 rows at 400 dpi, so up to 16 free rows a box — and
//     the tiled arm has more boxes. On C30's document that is 175 extra boxes over six
//     pages, bounding the padding's contribution at 2,800 rows of an observed 5,157-row
//     improvement: **54.3%**, a loose upper bound because padded ranges overlap. So the
//     row counts alone cannot say the recovery is box *extent*; what says it is content is
//     `TILETEXT` and the flat words-per-observation. Found by the adversarial review of
//     the commit that added this mode, which is why it is here and not in a footnote.
//   * ⚠️ **"Differing only in how many requests" is not true at every SETTING.**
//     `makeRequest` sets `minimumTextHeight` as a fraction of the image
//     (`Sources/Recogniser.swift:423`), so with `minTextHeightOn` the two arms differ by an
//     n-fold effective glyph floor as well. It defaults off, so the committed artefact is
//     unaffected — but a run with it on is measuring two things.
//   * **It is not a fix and not a seam.** Nothing in `Sources/` tiles anything;
//     `Recogniser` has no tiling seam and this tool does not add one.
// ✅ **`TILES=1` is an identity control that runs on real pages**: one band is the whole
// sheet, cropped to itself and remapped by the identity map, so every `t…` column must
// equal its whole-page twin. A divergence exits **7** rather than being printed as a
// tiling benefit nobody can attribute.
// ✅ **`TILETEXT=<dir>` writes both arms' strings**, one observation a line, so a reader
// can name what came back instead of trusting `tWords`. Use it: the columns count boxes,
// and C30 has already been misled once by a box whose whole text was `ASSAME`.
//
// ⛔ **THE SELF-TEST RUNS ON EVERY INVOCATION**, not only under `--self-test`, and refuses
// to measure anything if it fails. That is `score-mrc`, `score-threshold-loss`,
// `score-text-route`, `score-line-separation`, `score-routing-census` and
// `score-run-width`'s pattern — seven of the EIGHT other Swift tools here that have one,
// `score-annot-marks` having joined them on 2026-08-26 —
// and `score-text-route:476-478` states the reason: "cheap enough to be unconditional".
// It is a few hundred microseconds on three 200x300 buffers.
// ⚠️ **The reason it is unconditional is a gate that does not exist**: the pre-commit hook
// runs `--self-test` for staged `Tools/*.py` only, so a flag-gated Swift self-test is
// type-checked by `check-tools-compile.sh` and never run. ⚠️ A first draft of this header
// said "all eight Swift tools carrying one … are never run", and the census is wrong three
// ways: seven others carried one on 2026-08-25 and **eight do since
// `score-annot-marks` landed**, **all but one run it unconditionally**, `score-shape-term` is the
// only flag-gated one, and `score-skew` has none at all (its `Deskew.selfTest` is a
// production per-page check, not a tool self-test). The minority pattern was being
// presented as the norm; this file now follows the majority instead of documenting a gap.
//
// Exit codes: 0 ok · 1 the PDF will not open · 2 usage, a page argument that is not a
// positive integer, a `VOIDMININCH` that is not a positive number, or a `TILES` that is
// not a whole number of bands in 1…64 · **3 it measured no pages** (the silent-success
// defect `score-corpus` and `score-threshold-loss` both had) · 5 a failed self-test ·
// **6 the geometry identity failed on some page** — the decoded bitmap's dimensions
// disagreed with the `RebuiltPage` that named it, so the rows are still printed but no
// share on that page means anything · **7 the tile arm cannot be trusted** — `TILES=1`
// diverged from the whole page, some band contributed no boxes, `TILES` produced no bands
// at all, or a `TILETEXT` dump failed to write. ⚠️ That last one says nothing about the
// arm being the same request; it is here because a run whose dump is missing must not be
// read as a run whose strings matched nothing.

import AppKit
import CoreGraphics
import Foundation
import PDFKit

// MARK: - The three constants, as `artefact.py` holds them

/// A row is inked when this fraction of its pixels are at or below the page's own Otsu
/// threshold. `artefact.py:11`, and dimensionless, so it needs no resolution scaling.
let inkRowFraction = 0.005

/// The shortest run this reports as a void. `artefact.py:12` holds it as **20 rows at
/// 100 dpi**, which is this length; see the header for why it is a length here.
let voidMinimumInchesDefault = 0.20

/// Word boxes grow by this much, top and bottom, before covering rows. `artefact.py:13`
/// holds it as **2 rows at 100 dpi**.
let boxPadInches = 0.02

/// The two scaled row counts for a page at `dpi`.
func rowConstants(dpi: Double, minimumInches: Double)
    -> (minRows: Int, padRows: Int) {
    let minRows = max(1, Int((minimumInches * dpi).rounded()))
    let padRows = max(0, Int((boxPadInches * dpi).rounded()))
    return (minRows, padRows)
}

// MARK: - The measure

/// Which rows hold ink. `artefact.py`'s `ink_rows`, including its `int()` truncation of
/// the pixel count — `max(1, int(0.005 * w))`, not a rounding.
func inkedRows(_ grey: [UInt8], width w: Int, height h: Int,
               threshold: UInt8, lo: Int, hi: Int) -> [Bool] {
    var out = [Bool](repeating: false, count: max(h, 0))
    guard w > 0, h > 0, grey.count >= w * h, lo >= 0, hi <= h, lo < hi else { return out }
    let need = max(1, Int(inkRowFraction * Double(w)))
    for y in lo..<hi {
        var dark = 0
        let base = y * w
        for x in 0..<w where grey[base + x] <= threshold {
            dark += 1
            if dark >= need { break }
        }
        out[y] = dark >= need
    }
    return out
}

/// A box list in the reference's frame: first and last inked pixel row, unrounded.
func pixelBoxes(_ boxes: [SearchableWriter.BoundingBox], height h: Int)
    -> [(top: Double, bottom: Double)] {
    // `SearchableWriter.BoundingBox` is normalised to the page with a TOP-LEFT origin
    // (`Sources/SearchableWriter.swift:157`, flipped out of Vision's frame at
    // `Sources/Recogniser.swift:471-479`), so no second flip belongs here.
    boxes.map { (top: $0.y * Double(h), bottom: ($0.y + $0.height) * Double(h)) }
}

/// Which rows at least one box covers, padded. `artefact.py`'s coverage loop, which
/// `measure` and `measure_inkruns` share verbatim: rows `round(top) - pad` through
/// `round(bottom) + pad` INCLUSIVE, clamped to `[lo, hi - 1]`.
///
/// The rounding is `.toNearestOrEven` because Python's `round()` is, and a box landing on
/// an exact half row is the one input where the two disagree.
func coveredRows(pixelBoxes boxes: [(top: Double, bottom: Double)],
                 height h: Int, lo: Int, hi: Int, pad: Int) -> [Bool] {
    var out = [Bool](repeating: false, count: max(h, 0))
    guard h > 0, lo >= 0, hi <= h, lo < hi else { return out }
    for box in boxes {
        // ⚠️ A DIVERGENCE FROM THE REFERENCE, declared: `int(round(nan))` raises in
        // Python and this skips the box instead. Skipping *increases* the reported void,
        // so it errs toward alarm rather than toward silence — but it is still an input
        // dropped without a word, and a real page has never produced one.
        guard box.top.isFinite, box.bottom.isFinite else { continue }
        // Clamped before the `Int` conversion because that conversion TRAPS on a finite
        // Double outside `Int64`, which `isFinite` does not exclude.
        let top = min(max(box.top.rounded(.toNearestOrEven), -1e9), 1e9)
        let bottom = min(max(box.bottom.rounded(.toNearestOrEven), -1e9), 1e9)
        let first = max(lo, Int(top) - pad)
        let last = min(hi - 1, Int(bottom) + pad)
        guard first <= last else { continue }
        for y in first...last { out[y] = true }
    }
    return out
}

/// `artefact.py`'s `measure_inkruns`: runs of rows that are inked AND uncovered.
///
/// ⚠️ `longest` is over ALL such runs, including those under `minRows`, while `bare`
/// counts only the qualifying ones — the reference's own asymmetry, and the reason a page
/// can read `bareRows` 0 beside a `longBare` of 8.
func inkRunMeasure(inked: [Bool], covered: [Bool], lo: Int, hi: Int, minRows: Int)
    -> (bare: Int, share: Double, longest: Int) {
    precondition(lo >= 0 && hi >= lo && inked.count >= hi && covered.count >= hi,
                 "inkRunMeasure: rows [\(lo), \(hi)) against inked \(inked.count) "
                 + "and covered \(covered.count)")
    var bare = 0, longest = 0, run = 0, total = 0
    for y in lo..<hi {
        if inked[y] { total += 1 }
        if inked[y] && !covered[y] {
            run += 1
            longest = max(longest, run)
        } else {
            if run >= minRows { bare += run }
            run = 0
        }
    }
    if run >= minRows { bare += run }
    return (bare, total == 0 ? 0 : Double(bare) / Double(total), longest)
}

/// `artefact.py`'s `measure`: runs of UNCOVERED rows whatever their ink, then the inked
/// rows inside the qualifying ones. `runs` is this tool's addition and not the
/// reference's.
func voidMeasure(inked: [Bool], covered: [Bool], lo: Int, hi: Int, minRows: Int)
    -> (inkRows: Int, voidInk: Int, share: Double,
        longest: Int, longestInk: Int, runs: Int) {
    precondition(lo >= 0 && hi >= lo && inked.count >= hi && covered.count >= hi,
                 "voidMeasure: rows [\(lo), \(hi)) against inked \(inked.count) "
                 + "and covered \(covered.count)")
    var isVoid = [Bool](repeating: false, count: hi)
    var longest = 0, longestInk = 0, runs = 0
    var y = lo
    while y < hi {
        if covered[y] { y += 1; continue }
        var j = y
        while j < hi, !covered[j] { j += 1 }
        if j - y >= minRows {
            var ink = 0
            for k in y..<j {
                isVoid[k] = true
                if inked[k] { ink += 1 }
            }
            longest = max(longest, j - y)
            longestInk = max(longestInk, ink)
            runs += 1
        }
        y = j
    }
    var total = 0, voidInk = 0
    for y in lo..<hi where inked[y] {
        total += 1
        if isVoid[y] { voidInk += 1 }
    }
    return (total, voidInk, total == 0 ? 0 : Double(voidInk) / Double(total),
            longest, longestInk, runs)
}

// MARK: - Pixels

/// One decode of the bitmap `flatten` wrote, as a grey buffer whose row 0 is the top.
///
/// There is no shipped CGImage-to-grey helper — `Flattener.renderGrey` starts from a
/// `PDFPage`, which is the re-render this tool exists to avoid — so this is the only
/// pixel code here that is not production's. Group 1 of the self-test pins its row order
/// and its dimensions rather than reasoning about Core Graphics' two y conventions.
func greyBytes(of image: CGImage) -> (grey: [UInt8], width: Int, height: Int)? {
    let w = image.width, h = image.height
    // The app's own ceiling by name rather than a literal — 4b's drift shape. Note
    // `Flattener.swift:190-205`: 400 MP of grey peaks near 2.20 GB RSS, so this is the
    // limit and not a comfortable working size.
    guard w > 0, h > 0,
          Double(w) * Double(h) <= Double(Flattener.maximumPageMegapixels) * 1_000_000
    else { return nil }
    var buffer = [UInt8](repeating: 255, count: w * h)
    let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
        guard let base = raw.baseAddress, let ctx = CGContext(
            data: base, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    return ok ? (buffer, w, h) : nil
}

/// An 8-bit grey `CGImage` over a buffer, for the self-test only.
func greyImage(_ grey: [UInt8], width w: Int, height h: Int) -> CGImage? {
    guard let provider = CGDataProvider(data: Data(grey) as CFData) else { return nil }
    return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8,
                   bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                   bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                   decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}

// MARK: - The crop experiment (TILES)

/// The `tiles` horizontal bands of a page `h` rows tall, top-first, as half-open row
/// ranges in the grey buffer's frame (row 0 = the top of the sheet).
///
/// Integer division on purpose: band `i` runs `i * h / tiles` up to `(i + 1) * h / tiles`,
/// so the ranges PARTITION `[0, h)` exactly — no gap, no overlap, and the last band
/// absorbs the remainder because `tiles * h / tiles == h`. Group 12 pins that on a height
/// the tile count does not divide.
func bandRanges(height h: Int, tiles: Int) -> [(top: Int, bottom: Int)] {
    guard h > 0, tiles > 0 else { return [] }
    var out: [(top: Int, bottom: Int)] = []
    for i in 0..<tiles {
        let top = i * h / tiles
        let bottom = (i + 1) * h / tiles
        if top < bottom { out.append((top, bottom)) }
    }
    return out
}

/// The rect to hand `CGImage.cropping(to:)` for a band whose TOP row is `top` in the grey
/// buffer's frame.
///
/// ⛔ **Which y this is, is MEASURED and not reasoned.** Core Graphics has two y
/// conventions and this tool already carries one check (group 1) written because reasoning
/// about them is how a whole measure ends up upside down. Group 11 crops a buffer whose
/// top five rows are the only dark ones and asserts the band comes back dark, so a flipped
/// convention here is a red check rather than a silent 180-degree error in every tile row.
func bandRect(top: Int, height: Int, width: Int) -> CGRect {
    CGRect(x: 0, y: top, width: width, height: height)
}

/// A band's box lifted back into the whole page's normalised frame.
///
/// The box arrives normalised to the BAND — Vision normalises to whatever image it was
/// handed — with a top-left origin, because `Recogniser.recognise` has already flipped it
/// (`Sources/Recogniser.swift:471-479`). So only y and height move, and both scale by the
/// band's share of the sheet. Group 13 pins it through `pixelBoxes`.
func remapped(_ box: SearchableWriter.BoundingBox,
              bandTop: Int, bandHeight: Int,
              pageHeight: Int) -> SearchableWriter.BoundingBox {
    guard pageHeight > 0, bandHeight > 0 else { return box }
    let scale = Double(bandHeight) / Double(pageHeight)
    return SearchableWriter.BoundingBox(
        x: box.x,
        y: Double(bandTop) / Double(pageHeight) + box.y * scale,
        width: box.width,
        height: box.height * scale)
}

// MARK: - Self-test

/// The three synthetic buffers groups 2-7 are pinned on, in the reference's own 100-dpi
/// frame. 200 x 300, paper 255, ink 0, forty dark pixels in an inked row.
func fixture(_ ranges: [(Int, Int)]) -> [UInt8] {
    let w = 200, h = 300
    var px = [UInt8](repeating: 255, count: w * h)
    for (a, b) in ranges {
        for y in a...b { for x in 10..<50 { px[y * w + x] = 0 } }
    }
    return px
}

/// Three recognised lines, at the pixel rows the boxes below cover.
let selfTestRecognised: [(Int, Int)] = [(20, 27), (33, 40), (46, 53)]
/// Five unrecognised lines with blank gaps between them — five dropped lines that raise
/// no band, which is the blindness the header names.
let selfTestScattered: [(Int, Int)] = [(100, 107), (113, 120), (126, 133),
                                       (139, 146), (152, 159)]

func selfTest() -> [String] {
    var bad: [String] = []
    let w = 200, h = 300
    let (minRows, padRows) = rowConstants(dpi: 100, minimumInches: voidMinimumInchesDefault)

    // 1. `greyBytes`: dimensions, and which end of the buffer is the top of the image.
    //    Core Graphics has two y conventions and reasoning about which one a bitmap
    //    context uses is how a whole measure ends up upside down.
    var half = [UInt8](repeating: 255, count: 20 * 10)
    for y in 0..<5 { for x in 0..<20 { half[y * 20 + x] = 0 } }
    if let image = greyImage(half, width: 20, height: 10),
       let read = greyBytes(of: image) {
        if read.width != 20 || read.height != 10 {
            bad.append("greyBytes: \(read.width)x\(read.height) not 20x10")
        }
        let darkRows = (0..<10).filter { y in (0..<20).allSatisfy { read.grey[y * 20 + $0] == 0 } }
        if darkRows != Array(0..<5) {
            bad.append("greyBytes: dark rows \(darkRows) not the top five — the buffer is flipped")
        }
    } else {
        bad.append("greyBytes: no image")
    }

    // 2. The shipped Otsu does NOT agree with `artefact.py`'s copy, and this pins the
    //    reason and the consequence rather than the equality.
    //
    //    ⛔ Measured, not reasoned: `Flattener.otsuThreshold` reads **90** on fixture 1
    //    where the reference reads **0**. The argmax is the same — both take the first
    //    maximum, and on a two-valued buffer every t in [0, 254] ties — but the shipped
    //    one ends `UInt8(min(max(chosen, 90), 230))` (`Flattener.swift:1070`) and the
    //    reference has no clamp. So the divergence is the clamp's floor alone.
    //
    //    What matters is whether it moves the ink, and on a bimodal buffer it cannot:
    //    both thresholds select exactly the pixels at 0. That is the second assertion,
    //    and it is what lets groups 3-7 pin the port at `threshold: 0` while the run path
    //    uses the shipped value. ⚠️ It holds BECAUSE the buffer is two-valued — which a
    //    `.bilevel` rebuilt bitmap is and a `jpeg` one is not; see the header.
    let f1 = fixture(selfTestRecognised + selfTestScattered)
    let otsu1 = Flattener.otsuThreshold(of: f1)
    if otsu1 != 90 {
        bad.append("otsu on fixture 1: \(otsu1) not the shipped clamp's floor of 90")
    }
    let atShipped = inkedRows(f1, width: w, height: h, threshold: otsu1, lo: 0, hi: h)
    let atReference = inkedRows(f1, width: w, height: h, threshold: 0, lo: 0, hi: h)
    if atShipped != atReference {
        bad.append("otsu: the shipped threshold \(otsu1) and the reference's 0 select "
                   + "different rows on a bimodal buffer")
    }

    // 3. `inkedRows`, against `sum(ink_rows(...).values())` = 64.
    let inked1 = inkedRows(f1, width: w, height: h, threshold: 0, lo: 0, hi: h)
    let inkTotal1 = inked1.filter { $0 }.count
    if inkTotal1 != 64 { bad.append("inkedRows fixture 1: \(inkTotal1) not 64") }

    //    And the reference's `int()` TRUNCATION of the pixel count, exercised through
    //    `inkedRows` at a width where it is visible. ⛔ The check that used to sit here
    //    re-computed `max(1, Int(inkRowFraction * Double(w)))` — the expression under
    //    test, character for character — which is the mirror shape this register has
    //    recorded, and it was unpinnable anyway: `0.005 * 200` is exactly 1.0, so
    //    truncation, rounding and ceiling all agree at w=200, and every inked row in
    //    fixture 1 has 40 dark pixels, so `need` 1 and `need` 2 both total 64.
    //    At w=300 the product is 1.5: the reference needs ONE dark pixel and a rounding
    //    implementation would need two, so a single dark pixel separates them.
    var thin = [UInt8](repeating: 255, count: 300 * 3)
    thin[1 * 300 + 7] = 0
    let thinRows = inkedRows(thin, width: 300, height: 3, threshold: 0, lo: 0, hi: 3)
    if thinRows != [false, true, false] {
        bad.append("inkedRows at w=300: \(thinRows) — one dark pixel of 300 must be inked, "
                   + "which is the reference's int(1.5) = 1 and not a rounding's 2")
    }

    // The three boxes, in the reference's pixel frame, exactly on the recognised lines.
    let boxes1 = selfTestRecognised.map { (top: Double($0.0), bottom: Double($0.1)) }
    let cov1 = coveredRows(pixelBoxes: boxes1, height: h, lo: 0, hi: h, pad: padRows)

    // 4. Fixture 1 through `measure_inkruns`: `(0, 0.0, 8)`.
    //    ⛔ THE DOCUMENTED BLINDNESS AS A CHECK. Five whole lines of type have no box and
    //    this measure reports NOTHING, because the blank rows between them break every
    //    run at 8 against a minimum of 20. Anyone tempted to read `bareShare` 0 as
    //    "nothing was lost" is reading this fixture.
    let ir1 = inkRunMeasure(inked: inked1, covered: cov1, lo: 0, hi: h, minRows: minRows)
    if ir1.bare != 0 || ir1.share != 0.0 || ir1.longest != 8 {
        bad.append("inkRunMeasure fixture 1: \(ir1) not (0, 0.0, 8)")
    }

    // 5. Fixture 1 through `measure`: `(64, 40, 0.625, 244, 40)`.
    //    ⛔ THE WHOLE POINT OF THE TOOL. Every one of the three boxes sits exactly on ink,
    //    so `words=`, `start=`/`end=`, `probe-line-coverage` and `probe-line-edges` — all
    //    of which divide something by the words Vision returned — read this page as
    //    perfect. This measure reads 40 of its 64 inked rows with no box over them. A
    //    change that makes this check pass by starting from the observations is the defect
    //    the tool was written against.
    let vm1 = voidMeasure(inked: inked1, covered: cov1, lo: 0, hi: h, minRows: minRows)
    if vm1.inkRows != 64 || vm1.voidInk != 40 || vm1.share != 0.625
        || vm1.longest != 244 || vm1.longestInk != 40 || vm1.runs != 1 {
        bad.append("voidMeasure fixture 1: \(vm1) not (64, 40, 0.625, 244, 40, runs 1)")
    }

    // 6. Fixture 2 — the same page with the unrecognised block as one solid 60-row band —
    //    through both: `(60, 0.714…, 60)` and `(84, 60, 0.714…, 244, 60)`. This is the
    //    band `measure_inkruns` CAN see, and the pair with group 4 is what says the two
    //    definitions differ on the ink and agree on the share only by coincidence here.
    let f2 = fixture(selfTestRecognised + [(100, 159)])
    let inked2 = inkedRows(f2, width: w, height: h, threshold: 0, lo: 0, hi: h)
    let ir2 = inkRunMeasure(inked: inked2, covered: cov1, lo: 0, hi: h, minRows: minRows)
    let expected2 = 60.0 / 84.0
    if ir2.bare != 60 || ir2.share != expected2 || ir2.longest != 60 {
        bad.append("inkRunMeasure fixture 2: \(ir2) not (60, 60/84, 60)")
    }
    let vm2 = voidMeasure(inked: inked2, covered: cov1, lo: 0, hi: h, minRows: minRows)
    if vm2.inkRows != 84 || vm2.voidInk != 60 || vm2.share != expected2
        || vm2.longest != 244 || vm2.longestInk != 60 || vm2.runs != 1 {
        bad.append("voidMeasure fixture 2: \(vm2) not (84, 60, 60/84, 244, 60, runs 1)")
    }

    // 7. Fixture 3, THE INVERSE. Fixture 2 with a fourth box over the solid band:
    //    `(0, 0.0, 0)` and `(84, 0, 0.0, 138, 0)`. Without this row a measure that
    //    shouts on every page passes groups 4-6, and CONTRIBUTING 4d's rule is that the
    //    table needs the row where the property does not apply. Note `longest` stays
    //    138 — the margins are still uncovered — while `longestInk` goes to 0, which is
    //    why the ink column and not the run length is what a verdict reads.
    let boxes3 = boxes1 + [(top: 100.0, bottom: 159.0)]
    let cov3 = coveredRows(pixelBoxes: boxes3, height: h, lo: 0, hi: h, pad: padRows)
    let ir3 = inkRunMeasure(inked: inked2, covered: cov3, lo: 0, hi: h, minRows: minRows)
    if ir3.bare != 0 || ir3.share != 0.0 || ir3.longest != 0 {
        bad.append("inkRunMeasure fixture 3: \(ir3) not (0, 0.0, 0)")
    }
    let vm3 = voidMeasure(inked: inked2, covered: cov3, lo: 0, hi: h, minRows: minRows)
    //     `runs` is 2 here and 1 in groups 5-6, which is the only place the run COUNT
    //     is informative: boxing the band splits one void into the two margins. Without
    //     it `voidN` would be a printed column that nothing asserts.
    if vm3.inkRows != 84 || vm3.voidInk != 0 || vm3.share != 0.0
        || vm3.longest != 138 || vm3.longestInk != 0 || vm3.runs != 2 {
        bad.append("voidMeasure fixture 3: \(vm3) not (84, 0, 0.0, 138, 0, runs 2)")
    }

    // 8. The constants are LENGTHS. At 100 dpi they are the reference's own 20 and 2; at
    //    400 dpi, which is what C30's document rebuilds at, they are 80 and 8. A tool
    //    that kept them as row counts would read every interline gap on that page as a
    //    void.
    let at100 = rowConstants(dpi: 100, minimumInches: voidMinimumInchesDefault)
    let at400 = rowConstants(dpi: 400, minimumInches: voidMinimumInchesDefault)
    if at100.minRows != 20 || at100.padRows != 2 {
        bad.append("rowConstants at 100 dpi: \(at100) not (20, 2)")
    }
    if at400.minRows != 80 || at400.padRows != 8 {
        bad.append("rowConstants at 400 dpi: \(at400) not (80, 8)")
    }

    // 9. The normalised-to-pixel conversion, kept apart from the port above so the port
    //    is pinned on exact doubles: a box at y 0.1 of height 0.1 on h=300 is pixel rows
    //    30…60, covering 28…62 inclusive once padded — 35 rows.
    let one = [SearchableWriter.BoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.1)]
    let px = pixelBoxes(one, height: h)
    if px.count != 1 || abs(px[0].top - 30) > 1e-9 || abs(px[0].bottom - 60) > 1e-9 {
        bad.append("pixelBoxes: \(px) not [(30, 60)]")
    }
    let covOne = coveredRows(pixelBoxes: px, height: h, lo: 0, hi: h, pad: padRows)
    let rows = (0..<h).filter { covOne[$0] }
    if rows != Array(28...62) {
        bad.append("coveredRows: \(rows.count) rows \(rows.first ?? -1)…\(rows.last ?? -1), "
                   + "not 35 rows 28…62 — a count alone cannot say WHICH rows moved")
    }

    //     And the rounding MODE, which nothing above can see: no other fixture box lands
    //     on an exact half row, so `.rounded()` and `.toNearestOrEven` agree everywhere
    //     else and a check that cannot tell them apart is not pinning the port. Python's
    //     `round()` is half-to-even, so 30.5 goes DOWN to 30 and 33.5 up to 34 — the pair
    //     is deliberate, because half-to-even is not "always down".
    let halves = coveredRows(pixelBoxes: [(top: 30.5, bottom: 33.5)],
                             height: h, lo: 0, hi: h, pad: 0)
    let halfRows = (0..<h).filter { halves[$0] }
    if halfRows != Array(30...34) {
        bad.append("coveredRows half rows: \(halfRows) not 30…34 — the rounding is not "
                   + "Python's half-to-even")
    }

    // 10. Clamping, both ends: the reference's `max(lo, …)` and `min(hi - 1, …)`. A box
    //     running off the sheet covers to the last row and no further, and one starting
    //     above it covers from row 0 — not a crash and not a silently dropped box.
    let over = coveredRows(pixelBoxes: [(top: -40, bottom: Double(h) + 40)],
                           height: h, lo: 0, hi: h, pad: padRows)
    if over.filter({ $0 }).count != h {
        bad.append("coveredRows clamp: \(over.filter { $0 }.count) rows, not \(h)")
    }
    let empty = coveredRows(pixelBoxes: [(top: Double(h) + 10, bottom: Double(h) + 20)],
                            height: h, lo: 0, hi: h, pad: padRows)
    if empty.contains(true) { bad.append("coveredRows: a box off the sheet covered rows") }

    // 11. ⛔ WHICH END OF THE IMAGE `cropping(to:)` COUNTS FROM, MEASURED. `bandRect` puts
    //     the band's top row straight into the rect's `y`, which is only right if
    //     `CGImage.cropping(to:)` uses a TOP-LEFT origin. Group 1 exists because reasoning
    //     about Core Graphics' two y conventions once turned a whole measure upside down;
    //     this is the same hazard one function further on, and a flipped convention here
    //     would put every tile's boxes on the wrong half of the sheet while the counts
    //     stayed plausible.
    //     ⚠️ THREE bands of five rows and not two, and the reason is a sabotage: on a
    //     two-band fixture the flipped convention lands OUT OF BOUNDS, `cropping` returns
    //     nil, and the failure that fires is the "could not crop" guard — so the
    //     assertion about *which pixels came back* would never have been watched failing.
    //     Measured by building that sabotage (`y: top + height` on a 10-row fixture) and
    //     reading which line went red. With three distinct greys every wrong band is a
    //     valid band and the content assertions are what bite.
    //     ⛔ **WHAT THIS ESTABLISHES, exactly, after the review of this diff cut it down**:
    //     that `cropping(to:)`'s y AGREES with `greyImage`'s and `greyBytes`' — not that
    //     any of the three is top-down. Each band here is a single uniform grey, so
    //     `greyBytes`' row order cannot enter, and flipping all three would leave this
    //     group and group 1 green. The run path composes `cropping` with
    //     `Recogniser.loadImage`, which no check in this file touches. What the group does
    //     buy is that a flip in `bandRect` ALONE — the change a maintainer would make —
    //     is a red check and not a silent 180-degree error in every tile row.
    let bandRows = [UInt8(0), UInt8(128), UInt8(255)]
    var band = [UInt8](repeating: 0, count: 20 * 15)
    for y in 0..<15 { for x in 0..<20 { band[y * 20 + x] = bandRows[y / 5] } }
    if let image = greyImage(band, width: 20, height: 15) {
        for (i, want) in bandRows.enumerated() {
            guard let crop = image.cropping(to: bandRect(top: i * 5, height: 5, width: 20)),
                  let read = greyBytes(of: crop) else {
                bad.append("bandRect(top: \(i * 5)): could not crop the fixture")
                continue
            }
            if read.width != 20 || read.height != 5 {
                bad.append("bandRect(top: \(i * 5)): crop is \(read.width)x\(read.height), "
                           + "not 20x5")
            }
            if read.grey.contains(where: { $0 != want }) {
                let saw = Set(read.grey).sorted()
                bad.append("bandRect(top: \(i * 5)): band \(i) came back \(saw), not all "
                           + "\(want) — cropping does not count y from the top")
            }
        }
    } else {
        bad.append("bandRect: could not build the fixture")
    }

    // 12. `bandRanges` PARTITIONS the sheet. The divisible case is arithmetic; the case
    //     that matters is a height the tile count does not divide, where dropping the
    //     remainder would leave the bottom rows in no band at all — rows this tool would
    //     then report as void because nothing could ever cover them.
    func flat(_ ranges: [(top: Int, bottom: Int)]) -> [[Int]] {
        ranges.map { [$0.top, $0.bottom] }
    }
    let even = bandRanges(height: 300, tiles: 4)
    if flat(even) != [[0, 75], [75, 150], [150, 225], [225, 300]] {
        bad.append("bandRanges(300, 4): \(even) not four 75-row bands")
    }
    let odd = bandRanges(height: 10, tiles: 3)
    if flat(odd) != [[0, 3], [3, 6], [6, 10]] {
        bad.append("bandRanges(10, 3): \(odd) — the last band must absorb the remainder")
    }
    //     ⚠️ The partition properties below are REDUNDANT GIVEN THOSE TWO LITERALS and are
    //     labelled so rather than left reading as independent coverage — the adversarial
    //     review of this diff called them dead, and it is right: no change to `bandRanges`
    //     can red them while the literals hold. They are kept as the *statement* of what
    //     the literals are for, and they would bite if either literal were ever relaxed to
    //     a shape assertion. The load-bearing case is the `(10, 3)` one above.
    for ranges in [even, odd] {
        let covered = ranges.reduce(0) { $0 + ($1.bottom - $1.top) }
        let contiguous = zip(ranges, ranges.dropFirst()).allSatisfy { $0.bottom == $1.top }
        if !contiguous || ranges.first?.top != 0 {
            bad.append("bandRanges: \(ranges) is not a contiguous partition from row 0")
        }
        if covered != (ranges.last?.bottom ?? 0) {
            bad.append("bandRanges: \(ranges) covers \(covered) rows, not the sheet")
        }
    }
    //     And the identity arm the run path leans on: one tile is the whole sheet.
    if flat(bandRanges(height: 4400, tiles: 1)) != [[0, 4400]] {
        bad.append("bandRanges(4400, 1) is not the whole sheet, so TILES=1 is not an "
                   + "identity control")
    }

    // 13. `remapped`, through `pixelBoxes` — a band-normalised box back in the page's
    //     frame. Band 2 of 3 on h=300 is rows 100…200, and a box at band-y 0.25 of band
    //     height 0.5 is page rows **125…175**.
    //     ⛔ ALL THREE TERMS ARE PINNED, and the fixture's `y` is 0.25 rather than 0
    //     BECAUSE OF THAT: the adversarial review of this diff found that at `y: 0` the
    //     `box.y * scale` term — the one that decides where a box lands *inside* its band,
    //     and the only new arithmetic that can silently misplace every tiled box — is
    //     multiplied by nothing, so deleting the scale, inverting it or dropping the whole
    //     term left both assertions green. At 0.25 an unscaled y reads (175, 225) and an
    //     inverted scale (325, 375). An implementation that offsets and forgets to scale
    //     the HEIGHT reads (125, 275), and one that scales and forgets to offset (25, 75).
    let inBand = SearchableWriter.BoundingBox(x: 0.2, y: 0.25, width: 0.3, height: 0.5)
    let lifted = remapped(inBand, bandTop: 100, bandHeight: 100, pageHeight: 300)
    let liftedPx = pixelBoxes([lifted], height: 300)
    if liftedPx.count != 1 || abs(liftedPx[0].top - 125) > 1e-9
        || abs(liftedPx[0].bottom - 175) > 1e-9 {
        bad.append("remapped: \(liftedPx) not [(125, 175)]")
    }
    if abs(lifted.x - 0.2) > 1e-12 || abs(lifted.width - 0.3) > 1e-12 {
        bad.append("remapped: x/width moved (\(lifted.x), \(lifted.width)) — a horizontal "
                   + "band split must not touch either")
    }
    //     And the one-tile identity at the box level. ⚠️ Declared as REDUNDANT rather than
    //     left looking load-bearing: every mutation of `remapped` that reds this also reds
    //     the band-2 assertion above, so it can never be the sole red — the shape this
    //     register has recorded eleven times. It is kept because it is the *run* path's
    //     `TILES=1` control written down as arithmetic, and ⛔ because that control is
    //     weaker than three documents used to say: at one band `scale` is exactly 1.0 and
    //     `bandTop` is 0, so a `TILES=1` divergence can come from the crop or the union
    //     and NEVER from this function.
    let whole = remapped(inBand, bandTop: 0, bandHeight: 300, pageHeight: 300)
    if whole.x != inBand.x || whole.y != inBand.y
        || whole.width != inBand.width || whole.height != inBand.height {
        bad.append("remapped over one whole-sheet band is not the identity")
    }

    return bad
}

// MARK: - Main

let args = CommandLine.arguments

// UNCONDITIONAL, before anything is measured: `score-mrc`, `score-threshold-loss`,
// `score-text-route`, `score-line-separation`, `score-routing-census` and
// `score-run-width`'s pattern, seven of the eight other Swift tools here that have a
// self-test. `score-text-route:476-478` gives the reason — "cheap enough to be
// unconditional" — and the gate that would otherwise run it does not exist: the
// pre-commit hook runs `--self-test` for staged `Tools/*.py` only.
let selfTestFailures = selfTest()
if !selfTestFailures.isEmpty {
    FileHandle.standardError.write(Data(
        ("score-text-voids: self-test FAILED\n  "
         + selfTestFailures.joined(separator: "\n  ") + "\n").utf8))
    exit(5)
}
if args.contains("--self-test") {
    // ⚠️ A LITERAL, and `score-shape-term:996-999` records it going stale silently while
    // `:1000-1003` records the next hazard: guards added *inside* a group must not move
    // this number, because it counts GROUPS. 2026-08-25's review added assertions to
    // groups 3, 5, 6 and 7 and it stayed 10, which is correct. The crop experiment added
    // three whole groups the same day, so it moved to 13.
    print("score-text-voids: self-test ok (13 checks)")
    exit(0)
}
guard args.count > 1 else {
    FileHandle.standardError.write(Data(
        "usage: score-text-voids <pdf> [page…]   (or --self-test)\n".utf8))
    exit(2)
}

let minimumInches: Double = {
    guard let raw = ProcessInfo.processInfo.environment["VOIDMININCH"], !raw.isEmpty
    else { return voidMinimumInchesDefault }
    guard let value = Double(raw), value.isFinite, value > 0 else {
        FileHandle.standardError.write(Data(
            "VOIDMININCH=\(raw) is not a positive number of inches\n".utf8))
        exit(2)
    }
    return value
}()

/// `TILES=n` runs the SAME page a second time as `n` horizontal bands, each its own
/// `VNRecognizeTextRequest`, and prints the `t…` columns beside the whole-page ones. Unset
/// means no second arm and every `t…` column reads `-`.
///
/// The ceiling is arbitrary and is there so a typo cannot start ten thousand requests.
let tiles: Int? = {
    guard let raw = ProcessInfo.processInfo.environment["TILES"], !raw.isEmpty
    else { return nil }
    guard let value = Int(raw), value >= 1, value <= 64 else {
        FileHandle.standardError.write(Data(
            "TILES=\(raw) is not a whole number of bands in 1…64\n".utf8))
        exit(2)
    }
    return value
}()

/// `TILETEXT=<dir>` writes each measured page's two recognitions as text, one observation
/// a line: `p<N>-whole.txt` and `p<N>-tiled-<bands>.txt`.
///
/// ⛔ It exists because the `t…` columns count BOXES. C30's page-5 section is where a
/// 115-px observation reading the single nonsense word `ASSAME` moved a headline by 98
/// rows, so "the tiled arm returns 1.72x the words" is worth nothing until someone can
/// read what the words are. `Tools/make-observations` dumps strings too, but of
/// `Recogniser.render`'s plain render — a different image — so for production's own bitmap
/// this is the only dump there is.
///
/// ⛔ **The band count is IN the tiled filename** and `TILETEXT` without `TILES` is refused
/// at exit 2, both because of the review of this diff: without the first, one directory
/// reused across `TILES=2` and `TILES=8` silently overwrites and a stale file reads as this
/// run's; without the second, `TILETEXT` alone created the directory, wrote nothing and
/// exited 0 — which is exactly the "a missing dump must not read as *the strings matched
/// nothing*" failure this knob was added to prevent.
let textDirectory: URL? = {
    guard let raw = ProcessInfo.processInfo.environment["TILETEXT"], !raw.isEmpty
    else { return nil }
    guard tiles != nil else {
        FileHandle.standardError.write(Data(
            "TILETEXT=\(raw) needs TILES=n: there is no tiled arm to dump\n".utf8))
        exit(2)
    }
    let url = URL(fileURLWithPath: raw)
    do {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    } catch {
        // ⛔ Not swallowed. Two of the five image writers in `Tools/` drop a failed write
        // silently and that is an open queue item; a dump directory that does not exist
        // must not read as "the strings matched nothing".
        FileHandle.standardError.write(Data(
            "TILETEXT=\(raw) is not a writable directory: \(error.localizedDescription)\n"
                .utf8))
        exit(2)
    }
    return url
}()

/// One recognition's strings, in the order Vision returned them.
func dumpText(_ observations: [SearchableWriter.Observation],
              page: Int, arm: String, to directory: URL) -> String? {
    let url = directory.appendingPathComponent("p\(page)-\(arm).txt")
    let body = observations.map { $0.text }.joined(separator: "\n") + "\n"
    do {
        try Data(body.utf8).write(to: url, options: .atomic)
        return nil
    } catch {
        return "could not write \(url.lastPathComponent): \(error.localizedDescription)"
    }
}

let src = URL(fileURLWithPath: args[1])
Prefs.register(migrate: false)
let settings = Prefs.Snapshot.current()

let work = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("textvoids-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
/// Top-level `defer` does not run through `exit()`, and the scratch tree holds a rebuilt
/// PDF plus a full-page bitmap per page — so every `exit` below calls this. The exit-6
/// case is the one that matters: an operator re-runs it, and the leak would compound.
func cleanup() { try? FileManager.default.removeItem(at: work) }
defer { cleanup() }

guard let doc = PDFDocument(url: src), doc.pageCount > 0 else {
    FileHandle.standardError.write(Data("cannot open \(src.path)\n".utf8))
    cleanup()
    exit(1)
}
// ⛔ Every page argument is checked. `compactMap { Int($0) }` silently DROPPED `abc`,
// `3.5` and a mistyped flag, and if every argument was unparseable it fell back to the
// 12-page spread — so a typo measured a different set of pages than the one asked for and
// said nothing. Invariant 1 in an instrument.
let pageArguments = args.dropFirst(2)
var requested: [Int] = []
for argument in pageArguments {
    guard let number = Int(argument), number > 0, number <= doc.pageCount else {
        FileHandle.standardError.write(Data(
            "\(argument) is not a page number in a \(doc.pageCount)-page document\n".utf8))
        cleanup()
        exit(2)
    }
    requested.append(number)
}
let pages: [Int] = requested.isEmpty
    ? Flattener.sampleIndices(count: doc.pageCount, wanted: 12).map { $0 + 1 }
    : requested

/// One page, alone in its own PDF: `Flattener.flatten` takes a document, and the
/// recognition below has to run on the bitmap it writes (R40).
func isolate(_ index: Int) -> URL? {
    guard let page = doc.page(at: index - 1) else { return nil }
    let one = PDFDocument()
    one.insert(page, at: 0)
    let url = work.appendingPathComponent("p\(index).pdf")
    return one.write(to: url) ? url : nil
}

/// The one printer, and the columns in one place — T14, A12.3 and T18 are three separate
/// defects from counting tab escapes by eye.
let columns = ["page", "kind", "w", "h", "dpi", "otsu", "minRows", "padRows",
               "obsN", "words", "inkRows",
               "bareRows", "bareShare", "longBare",
               "voidInk", "voidShare", "voidN", "longVoid", "voidLongInk",
               "tiles", "tObsN", "tWords", "tBareRows", "tBareShare", "tLongBare",
               "tVoidInk", "tVoidShare", "verdict"]
func row(_ page: Int, kind: String = "-", w: String = "-", h: String = "-",
         dpi: String = "-", otsu: String = "-", minRows: String = "-",
         padRows: String = "-", obsN: String = "-", words: String = "-",
         inkRows: String = "-", bareRows: String = "-", bareShare: String = "-",
         longBare: String = "-", voidInk: String = "-", voidShare: String = "-",
         voidN: String = "-", longVoid: String = "-", voidLongInk: String = "-",
         tiles: String = "-", tObsN: String = "-", tWords: String = "-",
         tBareRows: String = "-", tBareShare: String = "-", tLongBare: String = "-",
         tVoidInk: String = "-", tVoidShare: String = "-",
         verdict: String) {
    let fields = ["p\(page)", kind, w, h, dpi, otsu, minRows, padRows,
                  obsN, words, inkRows, bareRows, bareShare, longBare,
                  voidInk, voidShare, voidN, longVoid, voidLongInk,
                  tiles, tObsN, tWords, tBareRows, tBareShare, tLongBare,
                  tVoidInk, tVoidShare,
                  verdict.replacingOccurrences(of: "\t", with: " ")]
    precondition(fields.count == columns.count)
    print(fields.joined(separator: "\t"))
}

print(columns.joined(separator: "\t"))

var measured = 0, barePages = 0, voidPages = 0, worstBare = 0, identityFailed = 0
var tileIdentityFailed = 0, tileBandFailures = 0, textWriteFailures = 0

for index in pages {
    // ⛔ A ROW FOR EVERY PAGE ASKED FOR, whatever happens to it. This was a bare
    // `continue` — inherited verbatim from `score-shape-term:1149` — so a page that would
    // not isolate produced no row, no message and exit 0, while every other failure in
    // this loop prints a `SKIP` with a reason. That is invariant 1, and it is fixed here
    // rather than argued about; the same `continue` is still in the two tools it came from.
    guard let page = doc.page(at: index - 1) else {
        row(index, verdict: "SKIP no such page")
        continue
    }
    guard let single = isolate(index) else {
        row(index, verdict: "SKIP could not write the isolated page")
        continue
    }

    // A12.2, exactly as `score-shape-term` and `score-text-route` guard it: isolating a
    // page can move the rebuild resolution, and a row measured at the wrong resolution is
    // not that page's.
    guard let isolated = PDFDocument(url: single)?.page(at: 0) else {
        // ⚠️ The two tools this is copied from let a nil here fall through and measure the
        // page with the guard silently skipped. A guard that quietly does not run is worse
        // than no guard, because the row looks checked.
        row(index, verdict: "SKIP could not reopen the isolated page, so A12.2 is unchecked")
        continue
    }
    do {
        let before = Flattener.rebuildDPI(of: page)
        let after = Flattener.rebuildDPI(of: isolated)
        if abs(before - after) > 0.5 {
            row(index, verdict: String(format:
                "SKIP isolation moved the rebuild DPI %.0f->%.0f (A12.2)", before, after))
            continue
        }
    }

    let pngDir = work.appendingPathComponent("png\(index)")
    try? FileManager.default.createDirectory(at: pngDir, withIntermediateDirectories: true)
    // `pngDirectory` is load-bearing: `Flattener.swift:645-649` records that the returned
    // array is appended to only inside `if let pngDirectory`, so a call without one
    // rebuilds every page and hands back `[]`.
    guard let rebuilt = try? Flattener.flatten(single,
                                               to: work.appendingPathComponent("r\(index).pdf"),
                                               mode: .auto, pngDirectory: pngDir),
          let first = rebuilt.first else {
        row(index, verdict: "SKIP flatten produced nothing")
        continue
    }
    let kind: String
    switch first.content {
    case .bilevel: kind = "bilevel"
    case .jpeg: kind = first.isColour ? "jpeg-colour" : "jpeg"
    // C29. Unreachable from here — this tool passes no `passThrough` set, so
    // `flatten` rasterises every page exactly as it did before that parameter
    // existed, which is what keeps `C30-VOIDS-2026-08-25.tsv` and
    // `C30-TILES-2026-08-25.tsv` reproducible from this tool. Handled rather than
    // defaulted so that a run which DOES ask for production's routing gets a SKIP
    // with a reason instead of a void measured on a page that has no bitmap.
    case .passthrough:
        row(index, verdict: "SKIP page was passed through, so there is no bitmap")
        continue
    }

    // ⛔ No render fallback. The whole point of this tool is that the pixels and the boxes
    // are one decode of what `flatten` wrote; a page whose bitmap will not decode is a
    // SKIP with a reason, not a number measured on some other image.
    guard let image = Recogniser.loadImage(first) else {
        row(index, kind: kind, verdict: "SKIP the rebuilt bitmap did not decode")
        continue
    }
    guard let read = greyBytes(of: image) else {
        row(index, kind: kind, verdict: "SKIP no grey buffer")
        continue
    }
    let w = read.width, h = read.height
    let dpi = first.boxSize.height > 0
        ? Double(first.pixelHeight) / Double(first.boxSize.height) * 72.0
        : Flattener.rebuildDPI(of: page)
    let (minRows, padRows) = rowConstants(dpi: dpi, minimumInches: minimumInches)

    // The identity: the decoded bitmap has to be the page `RebuiltPage` described. These
    // disagreeing means the file on disk is not the one whose dimensions the struct
    // carries, and every share below would be divided by the wrong height.
    if w != first.pixelWidth || h != first.pixelHeight {
        identityFailed += 1
        row(index, kind: kind, w: "\(w)", h: "\(h)", dpi: String(format: "%.1f", dpi),
            minRows: "\(minRows)", padRows: "\(padRows)",
            verdict: "⛔ IDENTITY the bitmap is \(w)x\(h), RebuiltPage says "
                   + "\(first.pixelWidth)x\(first.pixelHeight)")
        continue
    }

    guard let observations = try? Recogniser.recognise(image, settings: settings) else {
        row(index, kind: kind, w: "\(w)", h: "\(h)", dpi: String(format: "%.1f", dpi),
            minRows: "\(minRows)", padRows: "\(padRows)",
            verdict: "SKIP recognition threw")
        continue
    }
    let words = observations.reduce(0) {
        $0 + $1.text.split(whereSeparator: { $0.isWhitespace }).count
    }

    let otsu = Flattener.otsuThreshold(of: read.grey)
    let inked = inkedRows(read.grey, width: w, height: h, threshold: otsu, lo: 0, hi: h)
    let covered = coveredRows(pixelBoxes: pixelBoxes(observations.map { $0.boundingBox },
                                                     height: h),
                              height: h, lo: 0, hi: h, pad: padRows)
    let ir = inkRunMeasure(inked: inked, covered: covered, lo: 0, hi: h, minRows: minRows)
    let vm = voidMeasure(inked: inked, covered: covered, lo: 0, hi: h, minRows: minRows)

    measured += 1
    if ir.bare > 0 { barePages += 1 }
    if vm.voidInk > 0 { voidPages += 1 }
    worstBare = max(worstBare, ir.longest)
    // ⛔ `no-words` rather than `bare`, and the numbers are still printed. With no boxes at
    // all nothing is covered, so the whole sheet is one void and the shares read near 1.0 —
    // the worst page in any sweep — when what happened is that recognition returned
    // nothing. That is a total recall failure and worth seeing, but it must not be quoted
    // beside a page that lost a block. `obsN` discloses it too; this makes it unmissable.
    var verdict = observations.isEmpty
        ? "no-words — recognition returned nothing, so every share below is trivially high"
        : (ir.bare > 0 ? "bare" : (vm.voidInk > 0 ? "void" : "clean"))

    // The crop experiment. Same pixels, same measure, the only difference being how many
    // requests they were handed to — which is what C30's fork measured on one half of one
    // page and could not reproduce from the tree.
    var tileFields: (tiles: String, obsN: String, words: String, bareRows: String,
                     bareShare: String, longBare: String, voidInk: String,
                     voidShare: String) = ("-", "-", "-", "-", "-", "-", "-", "-")
    if let tiles {
        let bands = bandRanges(height: h, tiles: tiles)
        var union: [SearchableWriter.Observation] = []
        var bandFailed = 0
        var bandNotes: [String] = []
        for band in bands {
            let bandHeight = band.bottom - band.top
            // ⛔ Counted and reported with its ROWS and its REASON, never swallowed. A band
            // that will not crop or whose request throws removes every box it would have
            // contributed, which INFLATES the tile arm's void — the direction that would
            // make tiling look useless — so a silent skip here is a wrong answer, not a
            // missing one. ⚠️ The two failures are reported apart because the review of
            // this diff found one `guard` conflating them, and the thrown error is printed
            // rather than dropped by a `try?`. ⚠️ A band that succeeds with ZERO
            // observations is *not* a failure and is not counted here — it is the finding,
            // not the fault.
            guard let crop = image.cropping(
                    to: bandRect(top: band.top, height: bandHeight, width: w)) else {
                bandFailed += 1
                bandNotes.append("rows \(band.top)…\(band.bottom) would not crop")
                continue
            }
            let got: [SearchableWriter.Observation]
            do {
                got = try Recogniser.recognise(crop, settings: settings)
            } catch {
                bandFailed += 1
                bandNotes.append("rows \(band.top)…\(band.bottom) threw "
                                 + "\(error.localizedDescription)")
                continue
            }
            for o in got {
                union.append(SearchableWriter.Observation(
                    boundingBox: remapped(o.boundingBox, bandTop: band.top,
                                          bandHeight: bandHeight, pageHeight: h),
                    text: o.text, confidence: o.confidence))
            }
        }
        let tWords = union.reduce(0) {
            $0 + $1.text.split(whereSeparator: { $0.isWhitespace }).count
        }
        let tCovered = coveredRows(pixelBoxes: pixelBoxes(union.map { $0.boundingBox },
                                                          height: h),
                                   height: h, lo: 0, hi: h, pad: padRows)
        let tir = inkRunMeasure(inked: inked, covered: tCovered, lo: 0, hi: h,
                                minRows: minRows)
        let tvm = voidMeasure(inked: inked, covered: tCovered, lo: 0, hi: h,
                              minRows: minRows)
        tileFields = ("\(bands.count)", "\(union.count)", "\(tWords)", "\(tir.bare)",
                      String(format: "%.4f", tir.share), "\(tir.longest)",
                      "\(tvm.voidInk)", String(format: "%.4f", tvm.share))
        if let textDirectory {
            for note in [dumpText(observations, page: index, arm: "whole", to: textDirectory),
                         dumpText(union, page: index, arm: "tiled-\(bands.count)",
                                  to: textDirectory)] {
                if let note { textWriteFailures += 1; verdict += " ⛔ \(note)" }
            }
        }
        // ⛔ A sheet too short to band at all. `bandRanges`' guard returns `[]`, which would
        // otherwise compute every `t…` column from an empty union — i.e. print the whole
        // page's ink as the tiled arm's void — with no reason and exit 0. Named here rather
        // than left to the guard, and it is why the `tiles` column prints `bands.count`
        // (what was measured) while the summary prints the requested `tiles`.
        if bands.isEmpty {
            tileBandFailures += 1
            verdict += " ⛔ TILES=\(tiles) produced no bands on a \(h)-row page"
        }
        if bandFailed > 0 {
            tileBandFailures += bandFailed
            verdict += " ⛔ \(bandFailed) of \(bands.count) bands contributed no boxes: "
                + bandNotes.joined(separator: "; ")
        }
        // ⛔ THE IDENTITY ARM, and read what it does NOT cover. One band IS the whole
        // sheet, cropped to itself and remapped by the identity map (group 13's last
        // assertion), so every `t…` column must equal its whole-page twin. A divergence
        // means the CROP or the UNION is wrong — ⚠️ **not the remap**: at one band `scale`
        // is exactly 1.0 and `bandTop` is 0, so an inverted scale, an unscaled height, an
        // unscaled y and a mis-scaled offset are all the identity here, and this arm is
        // blind to every one of them. That is group 13's job, and the review of this diff
        // is why both say so. What it buys is a run-path check that a tiling "benefit" is
        // not the crop or the union manufacturing boxes.
        if bands.count == 1, bandFailed == 0,
           union.count != observations.count || tWords != words
            || tir.bare != ir.bare || tir.longest != ir.longest
            || tvm.voidInk != vm.voidInk {
            tileIdentityFailed += 1
            verdict += " ⛔ TILE-IDENTITY one band diverged from the whole page: "
                + "obsN \(observations.count)->\(union.count), words \(words)->\(tWords), "
                + "bareRows \(ir.bare)->\(tir.bare), longBare \(ir.longest)->\(tir.longest), "
                + "voidInk \(vm.voidInk)->\(tvm.voidInk)"
        }
    }

    row(index, kind: kind, w: "\(w)", h: "\(h)", dpi: String(format: "%.1f", dpi),
        otsu: "\(otsu)", minRows: "\(minRows)", padRows: "\(padRows)",
        obsN: "\(observations.count)", words: "\(words)", inkRows: "\(vm.inkRows)",
        bareRows: "\(ir.bare)", bareShare: String(format: "%.4f", ir.share),
        longBare: "\(ir.longest)", voidInk: "\(vm.voidInk)",
        voidShare: String(format: "%.4f", vm.share), voidN: "\(vm.runs)",
        longVoid: "\(vm.longest)", voidLongInk: "\(vm.longestInk)",
        tiles: tileFields.tiles, tObsN: tileFields.obsN, tWords: tileFields.words,
        tBareRows: tileFields.bareRows, tBareShare: tileFields.bareShare,
        tLongBare: tileFields.longBare, tVoidInk: tileFields.voidInk,
        tVoidShare: tileFields.voidShare, verdict: verdict)
}

print("")
print("pages measured \(measured)"
      + "; bareRows > 0 on \(barePages)"
      + "; voidInk > 0 on \(voidPages)"
      + "; longest inked-and-unboxed run \(worstBare)"
      + (tiles != nil ? "; tiles \(tiles!)" : "")
      + (tileBandFailures > 0 ? "; ⛔ \(tileBandFailures) BANDS PRODUCED NOTHING" : "")
      + (textWriteFailures > 0
         ? "; ⛔ \(textWriteFailures) TEXT DUMPS FAILED TO WRITE" : "")
      + (tileIdentityFailed > 0
         ? "; ⛔ TILE-IDENTITY FAILED on \(tileIdentityFailed)" : "")
      + (identityFailed > 0 ? "; ⛔ IDENTITY FAILED on \(identityFailed)" : "")
      + (measured == 0 ? "; ⛔ MEASURED NOTHING" : ""))
if identityFailed > 0 { cleanup(); exit(6) }
// ⛔ Before the exit-3 check on purpose: a run whose TILES=1 arm disagreed with the whole
// page measured something, so exit 3 would never fire, and a tile column nobody can trust
// is worse than no tile column. Exit 7 rather than folding it into 6, because 6 says the
// PIXELS are not the page's and 7 says the second ARM is not the same request.
if tileIdentityFailed > 0 || tileBandFailures > 0 || textWriteFailures > 0 {
    cleanup(); exit(7)
}
// The silent-success defect `score-corpus` and `score-threshold-loss` both had: a run that
// measured no page printed a header, a cheerful summary and exit 0, which reads exactly
// like "there is nothing wrong with those pages".
if measured == 0 { cleanup(); exit(3) }
