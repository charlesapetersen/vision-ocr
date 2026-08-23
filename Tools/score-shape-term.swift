// score-shape-term — is the ink outside the stencil *shaped* like the page's own type?
//
// `BUGS.md` C28 question 3, and this is its first measurement. The entry's four
// rendered sub-steps proved that no scalar orders the population: `inkOutsideText`
// interleaves losers and non-losers, `paleDrawing(…).extent` separates them
// perfectly *backwards*, the out-of-stencil pixel count discriminates nothing, and
// the source render's own width interleaves them too. Four scalars, four refusals.
// What is left is R56's lesson in a third place — the term that closed R56 was not
// "how pale is this mark" but "where is it" — so this tool asks about **shape**, and
// calibrates it against the page's own recognised text so that nothing here is a
// constant chosen in advance for a corpus.
//
// It drives the shipped code, like every other `score-*` tool: `Flattener.renderGrey`,
// `otsuThreshold`, `sauvolaMask`, `textRegionMask` and `inkOutsideText` are production's,
// not replicas. The only new arithmetic is the connected-component pass and the shape
// rule, and both live here rather than in `Sources/` because nothing ships them yet.
//
// ## The map is EXACT here, and that is the point
//
// `score-text-route.swift`'s header publishes a shell recipe for the same map —
// `ink AND NOT dilate(stencil)` off the dumped `-source.png` and `-stencil.png` — and
// records that it reads **0.56x to 16.0x** the guard's own `inkOutsideText` with the
// cause **not established**, naming three candidates: the erosion radius, ImageMagick's
// `-auto-threshold OTSU` against `Flattener.otsuThreshold`, and the dumped stencil being
// the Sauvola mask ∧ `region` while the guard tests `region` alone.
//
// This tool has `region` itself — it recognises the page, so it holds the boxes — so its
// map is `ink AND NOT region`, which is `inkOutsideText`'s own set by construction and
// **not a proxy for it**. The `mapFrac` column is that map's fraction and it must equal
// the `inkOut` column to every printed digit; when it does not, the row says so in
// `verdict` and the run exits 6. That identity is what makes every shape number below a
// statement about the pixels the guard reads rather than about a shell pipeline.
//
// The two candidate columns isolate the other two:
//
//   `stenFrac` — the same fraction with the *stencil* (Sauvola ∧ region) standing in for
//                `region`, no dilation. The gap to `mapFrac` is the Sauvola rim: ink the
//                page-wide Otsu calls ink inside a word box that the adaptive mask does
//                not. This is candidate 3, measured as a number per page.
//   `stenD3`   — the same with the stencil dilated by a 7x7 **square**, standing in for
//                the published recipe's `Disk:3`. The gap to `mapFrac` is what that radius
//                over- or under-eats. This is candidate 1.
//                ⛔ **It is a stand-in and not that kernel.** `-define
//                morphology:showKernel=1` prints `Disk:3` as `7x7+3+3 … Sum 29`; the square
//                is 49 cells, so they differ in **20 of 49** — 41%, not "only the corners",
//                which is what an earlier version of this comment claimed. The square is
//                strictly the more generous kernel, so a larger `keep` removes more map
//                pixels and this column is biased **low**: real `Disk:3` numbers sit closer
//                to 1.0 than these do. Read the band as a bound on the recipe's error, not
//                as the recipe. Found by the adversarial review of the commit that added
//                this file, which is also where `Disk:0` being radius 4 was already on
//                record.
//
// Candidate 2 (ImageMagick's OTSU) is not in the tool: the `otsu` column prints
// production's threshold, and `magick … -auto-threshold OTSU -verbose` prints
// ImageMagick's, so the comparison is one shell line and needs no Swift.
//
// ## One coordinate frame, deliberately
//
// Every rect this tool prints, and every pixel of every PNG it dumps, is in the frame of
// the page's own grey render — the same frame as `score-text-route`'s `-source.png`, so a
// `magick -crop WxH+X+Y` off one lands in the same place on the other. The interior
// window `inkOutsideText` walks is applied by *blanking* the border, never by cropping,
// because C28's sub-step 4 recorded a component rect read off an interior-cropped map,
// offset into page coordinates, landing 200 px from any flagged ink — a false negative
// that reads like a careful negative. There is nothing to offset here.
//
// ## What the shape rule is, and what it is not
//
// Per page: connected components (8-connected, run-based) of the exact map, and of the
// stencil. The stencil's components are the *recognised* glyphs, so their median height
// and median horizontal run length are the page's own type scale — the calibration. A map
// component is `textish` when its height is within [0.5, 3.0]x that median height, its
// median run is at most 2.0x that median run, and it has at least 4 px. `textish`
// components are then grouped into lines: same horizontal band, adjacent gaps at most 3
// glyph-heights, at least 4 members.
//
// ⚠️ **Where those five numbers come from, exactly, because it decides what the
// measurement is worth.** They were written down from the shape of type — a median glyph
// height sits between an `o` and an `H`, a stem is a few pixels wide, a line of prose is
// more than three marks — *before* any page was run, and **not one of them was adjusted
// afterwards**: the eight pages of C28 sub-step 1 were measured once, then the five
// held-out pages were measured with the same binary and the same constants. So this is
// not a fitted rule reporting its own training error. The first sample it was read over
// was 13 pages — **8 of the 73 and 5 of the 16 C26's bar move rescued**, not "13 of the
// 73" as this comment said for a day — chosen because earlier sub-steps had already
// published a verdict for them, which is a labelled convenience sample with four of its
// six non-losers on one scan. See `BUGS.md` C28 `#### A shape term, MEASURED`.
//
// ✅ **It has since been read over the WHOLE 73-page sub-bar population, 2026-08-21**, with
// the constants unchanged and every page's verdict already published: `lineN >= 1` on
// **12 of 12 pages that lose typeset content, 1 of 4 that lose only a hand-made mark, and
// 3 of 57 non-losers** (3 of the 51 that lose nothing; 0 of the 6 that only degrade). So
// the type half is 12/12 rather than 6/6, and the three firings on non-losing pages are,
// read at 1:1, the **rim of recognised type** — glyph tops outside Vision's word boxes on
// lines that are in the text layer. See `SHAPETERM-73-2026-08-21.tsv` and `BUGS.md` C28
// `#### The same shape term over ALL 73`.
//
// ⛔ **AND IT IS NOT SAFE ON PICTURES — read that before wiring it anywhere.** Over 10
// picture pages it fires on **6**, two of the three true halftone plates among them, and it
// reads **0** on two cartoons whose destruction C26 measured at 1:1. On hand-made marks it
// is a coin toss rather than blind: 3b measured it reading 0 on four such marks and firing on
// three, and the 73-page run below adds one more firing (a cursive signature) and three more
// zeroes. `BUGS.md` C28
// `#### The same shape term on PICTURES` and `SHAPETERM-PICTURES-2026-08-21.tsv`. The
// layering seam keeps those pages out because they are already routed as pictures;
// `textRegionMask`, which runs unconditionally on every layered page, does not.
//
// ## The rim sweep, added 2026-08-21 — ⛔ refused as a REPLACEMENT, ✅ open as a SECOND CONDITION
//
// The 73-page run's three firings on pages that lose nothing were all read at 1:1 and all
// three are the **rim of recognised type**. So the candidate fix that run named is in here
// as the `rim1N`/`rim2N`/`rim3N` columns: the shape rule re-run over the map with an
// `r`-pixel collar around every word box removed. It is a sweep in one pass because a
// radius is bounded from both sides — see `rimRadii` — and because the count is **not
// monotone** in `r`: cutting the collar can split a component, and a piece of a rejected
// component can pass a test its parent failed. Nothing here changes `mapFrac`, `outPx` or
// any share column; the identity stays the guard's own set.
//
// It was then run over all 73 (`SHAPETERM-RIM-2026-08-21.tsv`). Type-losers firing /
// non-losers firing, by radius: r=0 **12/12, 3/51**; r=1 **12/12, 2/51**;
// r=2 **11/12, 1/51**; r=3 **9/12, 1/51**. Four findings:
//
//  * **as a replacement, no radius separates them.** r=1 is the only one that keeps every
//    type-loser, and it does not clear the rim — it removes two false positives and adds
//    one of its own. On `Xin Qu et al_2018` p28 the rim of a recognised `469.` is **three**
//    accepted components at r=0, one short of `lineMinimumMembers`, and the 1-px collar
//    SPLITS the middle one (8x8 -> 4x6 + 3x6), taking the count to four and manufacturing
//    a line. So the collar can manufacture the artefact it was proposed to remove. (`rim1N`
//    is 2 on that page: two groups are manufactured and one of them was read.)
//  * ✅ **as a SECOND CONDITION it is the best rule measured on this population**:
//    `lineN >= 1 AND rim1N >= 1` reads **12/12 type-losers and 1 of 51 non-losers**, on 14
//    pages rather than 16, and p28 cannot enter it because `lineN` is 0 there. ⚠️ It is
//    post-hoc — a conjunction chosen after seeing these 73 pages — and the hand-made bucket
//    does not move (1 of 4 at every radius).
//  * ⛔ **and it buys NOTHING on a picture page, measured 2026-08-21 over the ten pages of
//    `SHAPETERM-PICTURES-2026-08-21.tsv`** — `SHAPETERM-PICTURES-RIM-2026-08-21.tsv`, same
//    constants and the same binary as the 73-page sweep, with all 23 shared columns plus
//    `verdict` byte-identical on 11 of 11 rows. ⚠️ The pictures file came from a binary with
//    **no** rim sweep in it, which is what makes that control span a real code change — so
//    it is not "the same binary", and saying so was this comment's first-draft error.
//    `rim1N == rim2N == rim3N == lineN` on **10 of 10**, the **largest** accepted-line rect
//    identical at every radius (one rect is printed per page, and on `Wilcox` p2 a
//    non-largest group did change), and a 3-px collar removes **4 accepted-line pixels of
//    16,294** page-wide, all four on `Wilcox` p2. So the conjunction fires on the same **6 of
//    10** the r=0 rule does and 3b's `textRegionMask` finding is untouched *as measured*.
//    ⚠️ Four of the ten read `lineN` 0, where a collar can only be tested for manufacture, so
//    the removal question is asked on the six that fire and one of those six moves.
//    The reason is in the collar's definition: `dilate(region, r) \ region` can only reach a
//    mark within `r` px of a word box's boundary, which is what a rim is and what a halftone
//    dot in the middle of a plate is not. Two controls in that run: the collar is live (on
//    `Wilcox` p2 it shaves a sliver at a `region` rectangle's own straight edge, read at 1:1)
//    and it is not idle for want of a `region` (on `1954 - Why` p4 recognised type covers 95%
//    of the interior ink and the group still does not move, because it is inside the drawing).
//    ⚠️ The tool does not print the collar's effect on the MAP, only on accepted lines, so
//    "0 accepted-line pixels removed" is not "0 map pixels removed".
//  * the false positive that survives every radius is `Herbert Marks papers` p12, and at
//    r=3 it is **still the rim** — 4-px flecks off the tops of `Corp.` on a recognised
//    ledger line, read at 1:1 (64 px, exactly `rim3Px`).
//  * ⛔ a **ratio**-scaled collar does not rescue the replacement reading: `Scott_TK` p3
//    loses its last group at 0.375x its own `glyphH` (8) while p12 still fires at 0.6x its
//    own (5), so a factor large enough to clear the rim has already destroyed a real loss
//    elsewhere — and note the direction: at a fixed ratio the larger `glyphH` buys the
//    larger absolute collar, so p3's 8 is eaten before p12's 5.
//    ⚠️ Derived from radii 1-3; radii above 3 were not run.
//    ⚠️ An earlier version of this comment said the collar "runs backwards" because the
//    surviving false positive has the smallest type and the destroyed losses the largest —
//    that is wrong on its own data (`Scott_TK` p3 is destroyed at `glyphH` 8, and
//    `Herbert Marks` p11 is a real loser at `glyphH` 5 that fires at every radius).
//
// Usage:
//
//   mkdir -p /tmp/h && cp Tools/score-shape-term.swift /tmp/h/main.swift
//   swiftc -O -o /tmp/score-shape-term -target "$(uname -m)-apple-macos13.0" \
//     $(ls Sources/*.swift | grep -v App.swift) /tmp/h/main.swift
//   /tmp/score-shape-term --self-test
//   /tmp/score-shape-term "<pdf>" [page…]              # 1-indexed; default: a spread
//   SHAPEDUMP=/tmp/look /tmp/score-shape-term "<pdf>" 3
//   WIDENBYTES=1 /tmp/score-shape-term "<pdf>" 3       # + the eleven byte columns
//
// ⚠️ The copied file must be named `main.swift` or swiftc rejects top-level code with a
// pile of misleading errors about the expressions themselves — recorded in C28's 2b
// section after it cost three builds.
//
// `SHAPEDUMP=<dir>` writes, per page, in the page's own frame:
//
//   <stem>-source.png   the grey render, so crops can be read at 1:1
//   <stem>-map.png      the exact map: ink outside `region`, black on white
//   <stem>-textish.png  only the components the shape rule accepts
//   <stem>-lines.png    only the components in an accepted line group
//   <stem>-rim<r>-lines.png   the same, per rim radius: one file for each of `rimRadii`
//   <stem>-stencil-ship.png   under `WIDENBYTES=1` only: the 1-bit stencil `mrcLayers`
//   <stem>-stencil-wide.png   built each way, copied rather than rebuilt, so the byte
//                             columns and the picture are the same two files
//
// Reading `-lines.png` beside `-source.png` at the same crop is the positive control the
// share columns cannot be: it says whether the term named the words the register says
// that page lost, or something else the same size. `-rim<r>-lines.png` is that same
// control at the radius under consideration, which is what says whether a surviving
// group still names the lost words or only a fragment of them.
//
// `WIDENBYTES=1` prices C28's question 4 at the `textRegionMask` seam: what it costs, in
// published bytes, to let the accepted line groups into the 1-bit stencil.
//
// The instrument is production's own `mrcLayers`, called twice on the same page with ONE
// property different — the box list. `mrcLayers` does exactly two things with `boxes`
// (refuses an empty list, `Flattener.swift:2664`, and builds `textRegionMask`, `:2696`),
// so a synthetic box over a line group's rect is exactly the word Vision would have
// returned had it recognised that line. **Nothing in `Sources/` moves for this**, which is
// what keeps it a measurement of production rather than of a second copy of it, and it is
// why there is no new override seam beside `textPageInkOutsideThresholdOverride`.
//
//   wideN       synthetic boxes added — 0 wherever `lineN` is 0, and those rows are the
//               negative control: the same call twice, so the two totals must agree
//   wideInkOut  `inkOutsideText` with the widened region, beside the shipped `inkOut`
//   stenPx / wideStenPx   Sauvola ink inside each region — whether the missed ink actually
//               ENTERED the stencil, which the map's Otsu components cannot say
//   shipSten / wideSten   the jbig2 stencil alone, each way
//   shipBytes / wideBytes / byteDelta   stencil + background + foreground, and the signed
//               difference: the number a widening is judged on
//   shipBg / wideBg   the background's stored dimensions each way
//
// ⚠️ **Read the two `Bg` columns before `byteDelta`.** The widening moves two things at
// once: the ink enters the stencil, AND `pageIsAllText` reads the widened region, so
// `inkOut` falls and a page that was refused the 8x shrink can be granted it. That is not
// a confound to remove — it is the candidate fix's own arithmetic, because the ink the
// shrink would have destroyed is in the 1-bit layer by then — but it means `byteDelta` can
// be NEGATIVE, and a negative delta is a page that got cheaper *and* kept its content.
//
// ⚠️ The synthetic box is the group's bounding RECT, so it admits whatever else shares
// that rect. A recognised word box already does that; it makes every byte figure an upper
// bound on the widening rather than an estimate of it.
//
// Exit codes: 1 unreadable PDF, 2 a refused `SHAPEDUMP` or `WIDENBYTES`, **3 `WIDENBYTES`
// was asked for and no jbig2 was found**, 5 a failed self-test,
// **6 the identity above failed on some page** — the rows are still printed, because a
// broken map is worth seeing, but no share column on that page means anything.
//
// Without `WIDENBYTES` it needs no jbig2 and never layers a page, which is what makes it
// cheaper than `score-text-route` on the same pages. With it, it costs two full layerings
// and two jbig2 encodes per page on top of everything above, so it is a knob and not the
// default.
import AppKit
import CoreGraphics
import Foundation
import PDFKit

// MARK: - The shape rule's five numbers, all ratios against the page's own type

/// A map component shorter than this many median glyph heights is not a glyph.
///
/// 0.5 rather than something tighter because a lower-case `o` and a cap `H` are already
/// 2x apart in one line of type, and the median lands between them.
let shapeHeightLow = 0.5
/// And taller than this many is not one either. 3.0 admits a display line and a
/// two-line-tall brace; it refuses the gutter shadow and the platen edge, which is what
/// the four non-losing pages of C28 sub-step 1 are made of.
let shapeHeightHigh = 3.0
/// A component whose median horizontal run is wider than this many median glyph runs is
/// a solid thing rather than a stroke. This is the term that refuses a scanner edge that
/// happens to be the right height.
let shapeRunHigh = 2.0
/// Fewer pixels than this is a speck. Dust and JPEG ringing both make them in quantity.
let shapeMinimumArea = 4
/// A line group needs this many accepted components. Four, so that two words of two
/// letters do not make a line out of noise.
let lineMinimumMembers = 4
/// …and no gap between adjacent members wider than this many glyph heights, which is
/// what stops a mark at each margin from being read as one line spanning the page.
let lineGapFactor = 3.0

/// The rim candidate's radii, in map pixels, swept in one pass so that one run over a
/// population answers the question at every radius rather than three runs at one each.
///
/// This is the fix the 73-page run named: all three of that run's firings on pages which
/// lose nothing are the **rim of recognised type** — glyph tops and descenders poking a
/// few pixels outside Vision's word box on a line that IS in the text layer, so the box's
/// own collar is where they live. `region` is a union of rectangles, so growing it by `r`
/// removes exactly that collar. A sweep and not a knob because the safe radius is bounded
/// from both sides and neither bound was known in advance: too small leaves the rim, and
/// too large eats an unrecognised line sitting beside a recognised one, which is what
/// C28 sub-step 1's four losers are made of.
///
/// ⚠️ These are absolute pixels, not a ratio against the page's own type like the five
/// numbers above — so unlike them this one does not travel across resolutions, and a page
/// whose `glyphH` is 5 px is a different question from one whose `glyphH` is 50. The
/// `rim*N` columns are read beside `glyphH` for that reason.
let rimRadii = [1, 2, 3]

// MARK: - Runs and components

/// A maximal horizontal run of set pixels. `x1` is exclusive.
struct Run { let y: Int, x0: Int, x1: Int }

/// One connected component, kept as statistics rather than as pixels: a page of
/// newsprint has hundreds of thousands of these and its pixel lists would not fit.
struct Comp {
    var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
    var area = 0
    var runLengths: [Int] = []
    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }
    /// The stroke-width proxy: the median of this component's own row runs. A stem of
    /// type is 2-6 px at these resolutions; a gutter shadow is hundreds.
    var medianRun: Int {
        guard !runLengths.isEmpty else { return 0 }
        let s = runLengths.sorted()
        return s[s.count / 2]
    }
    mutating func add(_ r: Run) {
        minX = min(minX, r.x0); maxX = max(maxX, r.x1 - 1)
        minY = min(minY, r.y);  maxY = max(maxY, r.y)
        area += r.x1 - r.x0
        runLengths.append(r.x1 - r.x0)
    }
}

/// 8-connected components of `mask`, over the half-open window only.
///
/// Run-based rather than pixel-based: the run lengths are the stroke-width proxy, so
/// finding them first and labelling *them* costs one pass instead of two.
func components(_ mask: [Bool], width w: Int, height h: Int,
                x0: Int, y0: Int, x1: Int, y1: Int) -> [Comp] {
    guard w > 0, h > 0, mask.count >= w * h, x0 < x1, y0 < y1 else { return [] }
    var runs: [Run] = []
    var rowStart: [Int] = []
    for y in y0..<y1 {
        rowStart.append(runs.count)
        var x = x0
        let row = y * w
        while x < x1 {
            if mask[row + x] {
                let s = x
                while x < x1, mask[row + x] { x += 1 }
                runs.append(Run(y: y, x0: s, x1: x))
            } else {
                x += 1
            }
        }
    }
    rowStart.append(runs.count)
    guard !runs.isEmpty else { return [] }

    var parent = Array(0..<runs.count)
    func find(_ a: Int) -> Int {
        var r = a
        while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }
        return r
    }
    func union(_ a: Int, _ b: Int) {
        let ra = find(a), rb = find(b)
        if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
    }
    // Two pointers down each pair of adjacent rows. 8-connectivity, so runs that only
    // touch at a corner are one component: `a.x0 <= b.x1 && b.x0 <= a.x1` with `x1`
    // exclusive is exactly that.
    if rowStart.count >= 3 {
        for band in 1..<(rowStart.count - 1) {
            var i = rowStart[band - 1], j = rowStart[band]
            let iEnd = rowStart[band], jEnd = rowStart[band + 1]
            while i < iEnd, j < jEnd {
                let a = runs[i], b = runs[j]
                if a.x0 <= b.x1, b.x0 <= a.x1 { union(i, j) }
                if a.x1 < b.x1 { i += 1 } else { j += 1 }
            }
        }
    }

    var slot = [Int: Int](minimumCapacity: runs.count / 4 + 1)
    var comps: [Comp] = []
    for (i, r) in runs.enumerated() {
        let root = find(i)
        if let k = slot[root] {
            comps[k].add(r)
        } else {
            slot[root] = comps.count
            var c = Comp()
            c.add(r)
            comps.append(c)
        }
    }
    return comps
}

/// The window `Flattener.inkOutsideText` walks, character for character from that
/// function rather than re-derived: the outer sixteenth on every side is ignored.
func interiorWindow(width w: Int, height h: Int) -> (x0: Int, y0: Int, x1: Int, y1: Int) {
    let mx = w / 16, my = h / 16
    let x1 = max(w - mx, mx + 1), y1 = max(h - my, my + 1)
    return (mx, my, min(x1, w), min(y1, h))
}

/// Grow the set by `radius` in a (2r+1)-square, separably.
///
/// A square and not a disk. `Disk:3` prints as a 7x7 kernel with `Sum 29`, so a 7x7 square
/// of 49 cells differs from it in **20 of 49** — 41%, not "only at the corners", which is
/// what this comment said until 2026-08-21 and what the header above already records as
/// refuted. The square is still the strictly more generous stand-in, which is the safe
/// direction for a column whose job is to show how much the published recipe over-eats.
func dilate(_ mask: [Bool], width w: Int, height h: Int, radius r: Int) -> [Bool] {
    guard r > 0, w > 0, h > 0, mask.count >= w * h else { return mask }
    var mid = [Bool](repeating: false, count: w * h)
    for y in 0..<h {
        let row = y * w
        for x in 0..<w where mask[row + x] {
            let lo = max(x - r, 0), hi = min(x + r, w - 1)
            for k in lo...hi { mid[row + k] = true }
        }
    }
    var out = [Bool](repeating: false, count: w * h)
    for y in 0..<h {
        let row = y * w
        for x in 0..<w where mid[row + x] {
            let lo = max(y - r, 0), hi = min(y + r, h - 1)
            for k in lo...hi { out[k * w + x] = true }
        }
    }
    return out
}

/// The rim candidate: the exact map with an `r`-pixel collar around every recognised word
/// box removed, so a glyph top that pokes out of its own box is no longer in the map.
///
/// Deliberately a *separate* mask rather than a change to `inkOutsideMap`: the identity
/// this tool rests on is that the map is `inkOutsideText`'s own set, and a map with a
/// collar cut out of it is not. So `mapFrac`, `outPx` and every share column stay the
/// guard's, and only the shape rule reads this.
func rimSubtract(_ map: [Bool], region: [Bool], width w: Int, height h: Int,
                 radius r: Int) -> [Bool] {
    guard r > 0, w > 0, h > 0, map.count >= w * h, region.count >= w * h else { return map }
    let grown = dilate(region, width: w, height: h, radius: r)
    var out = map
    for i in 0..<(w * h) where grown[i] { out[i] = false }
    return out
}

/// The exact map: interior ink that `region` does not cover, in the page's own frame.
///
/// ⛔ **One function, called by `main` and by the self-test.** The first version built this
/// inline in `main` and again inline in the check, so the check pinned two copies of the
/// arithmetic agreeing with `inkOutsideText` and could not have failed if `main`'s copy
/// drifted — a check that cannot fail, which is a shape this register has recorded ten
/// times. The runtime `identity` guard on every printed row is the other half.
func inkOutsideMap(_ grey: [UInt8], region: [Bool], width w: Int, height h: Int,
                   threshold: UInt8) -> (map: [Bool], ink: Int, outside: Int) {
    var map = [Bool](repeating: false, count: w * h)
    guard w > 0, h > 0, grey.count >= w * h, region.count >= w * h else { return (map, 0, 0) }
    let win = interiorWindow(width: w, height: h)
    var ink = 0, outside = 0
    for y in win.y0..<win.y1 {
        let base = y * w
        for x in win.x0..<win.x1 where grey[base + x] < threshold {
            ink += 1
            if !region[base + x] { map[base + x] = true; outside += 1 }
        }
    }
    return (map, ink, outside)
}

/// The fraction of the interior ink that `keep` does not cover — the same quantity
/// `Flattener.inkOutsideText` returns, with `keep` substituted for `region`. Used for
/// the two candidate columns; the exact map's own fraction comes from the map itself.
func outsideFraction(_ grey: [UInt8], keep: [Bool], width w: Int, height h: Int,
                     threshold: UInt8) -> Double {
    let win = interiorWindow(width: w, height: h)
    var outside = 0, total = 0
    for y in win.y0..<win.y1 {
        let row = y * w
        for x in win.x0..<win.x1 where grey[row + x] < threshold {
            total += 1
            if !keep[row + x] { outside += 1 }
        }
    }
    return total > 0 ? Double(outside) / Double(total) : 0
}

// MARK: - The shape rule

struct Line {
    var members: [Int] = []
    var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
    var area = 0
}

/// Which of `comps` are shaped like type at this page's own scale.
func textish(_ comps: [Comp], glyphHeight: Double, glyphRun: Double) -> [Int] {
    guard glyphHeight > 0, glyphRun > 0 else { return [] }
    return comps.indices.filter { i in
        let c = comps[i]
        guard c.area >= shapeMinimumArea else { return false }
        let hh = Double(c.height)
        guard hh >= shapeHeightLow * glyphHeight, hh <= shapeHeightHigh * glyphHeight
        else { return false }
        return Double(c.medianRun) <= shapeRunHigh * glyphRun
    }
}

/// Group accepted components into lines: same horizontal band, no adjacent gap wider
/// than `lineGapFactor` glyph heights, at least `lineMinimumMembers` members.
///
/// The band test is vertical *overlap* rather than a shared centre line, because a
/// descender and a cap on the same line of type do not share a centre.
func lines(_ comps: [Comp], accepted: [Int], glyphHeight: Double) -> [Line] {
    guard glyphHeight > 0 else { return [] }
    let sorted = accepted.sorted { comps[$0].minY < comps[$1].minY }
    var bands: [[Int]] = []
    for i in sorted {
        let c = comps[i]
        var placed = false
        for b in bands.indices {
            // The band's current extent, taken from its last member: bands are built in
            // increasing `minY`, so the newest member is the one a candidate can touch.
            let last = comps[bands[b].last!]
            let lo = max(c.minY, last.minY), hi = min(c.maxY, last.maxY)
            let overlap = hi - lo + 1
            if overlap > 0, Double(overlap) >= 0.5 * Double(min(c.height, last.height)) {
                bands[b].append(i)
                placed = true
                break
            }
        }
        if !placed { bands.append([i]) }
    }
    var out: [Line] = []
    for band in bands {
        let ordered = band.sorted { comps[$0].minX < comps[$1].minX }
        var run: [Int] = []
        func flush() {
            if run.count >= lineMinimumMembers {
                var l = Line()
                for i in run {
                    let c = comps[i]
                    l.members.append(i)
                    l.minX = min(l.minX, c.minX); l.maxX = max(l.maxX, c.maxX)
                    l.minY = min(l.minY, c.minY); l.maxY = max(l.maxY, c.maxY)
                    l.area += c.area
                }
                out.append(l)
            }
            run = []
        }
        for i in ordered {
            if let prev = run.last {
                let gap = comps[i].minX - comps[prev].maxX
                if Double(gap) > lineGapFactor * glyphHeight { flush() }
            }
            run.append(i)
        }
        flush()
    }
    return out
}

/// The accepted line groups as word boxes, in `textRegionMask`'s own frame.
///
/// C28 question 4 at the `textRegionMask` seam. This is the whole of the widening: hand
/// `mrcLayers` more boxes and it builds a wider region, admits more of the page's ink to
/// the 1-bit stencil, and reads a smaller `inkOutsideText` — all through shipped code.
///
/// **The frame is the thing to get right.** `textRegionMask` reads `b.y` as a fraction of
/// the render's height counted from the TOP: `Recogniser.swift:465` flips Vision's
/// bottom-up origin (`y: 1 - origin.y - height`) before a box ever reaches it. A `Line`'s
/// `minY` is a row index in that same render, so the conversion is a plain divide — and a
/// flip here would price a rectangle on the *other half of the page* while every column
/// still printed a reasonable-looking number. The self-test pins both halves.
///
/// One function, called by `main` and by the check, for the reason `inkOutsideMap`'s
/// comment gives: two copies of this arithmetic is a check that cannot fail.
func lineBoxes(_ found: [Line], width w: Int, height h: Int) -> [SearchableWriter.BoundingBox] {
    guard w > 0, h > 0 else { return [] }
    return found.compactMap { l in
        guard l.minX <= l.maxX, l.minY <= l.maxY, l.minX >= 0, l.minY >= 0 else { return nil }
        return SearchableWriter.BoundingBox(x: Double(l.minX) / Double(w),
                                           y: Double(l.minY) / Double(h),
                                           width: Double(l.maxX - l.minX + 1) / Double(w),
                                           height: Double(l.maxY - l.minY + 1) / Double(h))
    }
}

func median(_ xs: [Int]) -> Double {
    guard !xs.isEmpty else { return 0 }
    let s = xs.sorted()
    return Double(s[s.count / 2])
}

// MARK: - Self-test

func selfTest() -> [String] {
    var bad: [String] = []

    // 1. The component pass on a hand-built bitmap: two glyph-shaped marks two rows
    //    apart, one 1-px bridge away from being one component.
    let w = 20, h = 12
    var m = [Bool](repeating: false, count: w * h)
    for y in 2...5 { m[y * w + 3] = true }              // a 1x4 stem
    for y in 2...5 { for x in 10...12 { m[y * w + x] = true } }  // a 3x4 block
    let cs = components(m, width: w, height: h, x0: 0, y0: 0, x1: w, y1: h)
    if cs.count != 2 { bad.append("components: \(cs.count) not 2") }
    if let stem = cs.first(where: { $0.width == 1 }) {
        if stem.height != 4 { bad.append("stem height \(stem.height) not 4") }
        if stem.area != 4 { bad.append("stem area \(stem.area) not 4") }
        if stem.medianRun != 1 { bad.append("stem medianRun \(stem.medianRun) not 1") }
    } else {
        bad.append("components: no 1-px-wide component")
    }
    if let block = cs.first(where: { $0.width == 3 }) {
        if block.area != 12 { bad.append("block area \(block.area) not 12") }
        if block.medianRun != 3 { bad.append("block medianRun \(block.medianRun) not 3") }
    } else {
        bad.append("components: no 3-px-wide component")
    }

    // 2. Diagonal touching is one component, because the rule is 8-connectivity. A
    //    4-connected implementation reads two here and every stroke of type in the
    //    corpus would break into pieces at its own serifs.
    var d = [Bool](repeating: false, count: w * h)
    d[2 * w + 2] = true
    d[3 * w + 3] = true
    let dc = components(d, width: w, height: h, x0: 0, y0: 0, x1: w, y1: h)
    if dc.count != 1 { bad.append("diagonal: \(dc.count) components not 1") }

    // 3. The identity this tool rests on, against production's own function: the map's
    //    own fraction IS `inkOutsideText`. A synthetic page, ink both inside and outside
    //    a region, and the border deliberately full of ink so the interior window has
    //    to be doing its job for the two to agree.
    let gw = 64, gh = 64
    var grey = [UInt8](repeating: 255, count: gw * gh)
    var region = [Bool](repeating: false, count: gw * gh)
    for y in 20..<30 { for x in 20..<30 { region[y * gw + x] = true } }
    for y in 22..<26 { for x in 22..<26 { grey[y * gw + x] = 0 } }   // 16 px inside
    for y in 40..<44 { for x in 40..<42 { grey[y * gw + x] = 0 } }   // 8 px outside
    for x in 0..<gw { grey[x] = 0; grey[(gh - 1) * gw + x] = 0 }     // border ink
    let shipped = Flattener.inkOutsideText(grey, region: region, width: gw, height: gh,
                                           threshold: 128)
    let win = interiorWindow(width: gw, height: gh)
    let built = inkOutsideMap(grey, region: region, width: gw, height: gh, threshold: 128)
    let mapMask = built.map, ink = built.ink, out = built.outside
    let mine = ink > 0 ? Double(out) / Double(ink) : 0
    if abs(mine - shipped) > 1e-12 {
        bad.append("map identity: \(mine) against inkOutsideText \(shipped)")
    }
    if ink != 24 { bad.append("interior ink \(ink) not 24 — the border leaked in") }
    if out != 8 { bad.append("interior outside \(out) not 8") }
    let mc = components(mapMask, width: gw, height: gh,
                        x0: win.x0, y0: win.y0, x1: win.x1, y1: win.y1)
    if mc.count != 1 || mc.first?.area != 8 {
        bad.append("map components: \(mc.count) comps, area \(mc.first?.area ?? -1)")
    }

    // 4. Dilation grows by exactly the radius, and `radius: 0` is the identity — which
    //    ImageMagick's `Disk:0` is NOT (it is radius 4, measured; C28 records a sweep
    //    that read backwards because of it). A stand-in that inherited that behaviour
    //    would make `stenD3` a column about the wrong kernel.
    var one = [Bool](repeating: false, count: w * h)
    one[6 * w + 6] = true
    let grown = dilate(one, width: w, height: h, radius: 2)
    if grown.filter({ $0 }).count != 25 {
        bad.append("dilate r=2: \(grown.filter { $0 }.count) px not 25")
    }
    if dilate(one, width: w, height: h, radius: 0).filter({ $0 }).count != 1 {
        bad.append("dilate r=0 is not the identity")
    }

    // 5. The line grouper needs four members and refuses a gap wider than the factor.
    //    Three glyphs plus one far away is not a line; four adjacent ones are.
    var glyphs: [Comp] = []
    for k in 0..<4 {
        var c = Comp()
        for y in 10...19 { c.add(Run(y: y, x0: 10 + k * 12, x1: 12 + k * 12)) }
        glyphs.append(c)
    }
    let all = Array(glyphs.indices)
    if lines(glyphs, accepted: all, glyphHeight: 10).count != 1 {
        bad.append("lines: four adjacent glyphs did not make one line")
    }
    if lines(glyphs, accepted: Array(all.prefix(3)), glyphHeight: 10).count != 0 {
        bad.append("lines: three glyphs made a line")
    }
    var far = glyphs
    var c = Comp()
    for y in 10...19 { c.add(Run(y: y, x0: 400, x1: 402)) }
    far[3] = c
    if lines(far, accepted: all, glyphHeight: 10).count != 0 {
        // 365 px: the third glyph ends at x=35 and the moved one starts at x=400. Counted
        // rather than eyeballed — the first version of this comment said 388.
        bad.append("lines: a 365-px gap did not split the line")
    }

    // 6. The rim candidate, both directions on one scene. A recognised word box with five
    //    glyph-top stubs sitting immediately above it — the shape the 73-page run's three
    //    false positives are actually made of — and, twenty pixels below it, four full
    //    stems standing for an unrecognised line of prose. Untrimmed the rule reads BOTH
    //    as lines; trimmed by 3 px the rim stubs fall under the height floor and the
    //    unrecognised line survives untouched.
    //
    //    The second half is the half that matters: a collar wide enough to remove the rim
    //    must not remove a line of type that merely sits next to a recognised one, which
    //    is what C28 sub-step 1's losers are. A one-sided check would pass on
    //    `rimSubtract` returning an empty mask.
    let rw = 128, rh = 128
    var rimRegion = [Bool](repeating: false, count: rw * rh)
    for y in 40..<60 { for x in 20..<100 { rimRegion[y * rw + x] = true } }
    var rimMap = [Bool](repeating: false, count: rw * rh)
    for k in 0..<5 {                                   // the rim: 2x6 stubs above the box
        for y in 34..<40 { for x in (22 + k * 10)..<(24 + k * 10) { rimMap[y * rw + x] = true } }
    }
    for k in 0..<4 {                                   // an unrecognised line, 20 px clear
        for y in 80..<90 { for x in (22 + k * 10)..<(24 + k * 10) { rimMap[y * rw + x] = true } }
    }
    func rimLines(_ radius: Int) -> [Line] {
        let trimmed = rimSubtract(rimMap, region: rimRegion, width: rw, height: rh,
                                  radius: radius)
        let cs = components(trimmed, width: rw, height: rh, x0: 0, y0: 0, x1: rw, y1: rh)
        return lines(cs, accepted: textish(cs, glyphHeight: 10, glyphRun: 2),
                     glyphHeight: 10)
    }
    let untrimmed = rimLines(0)
    if untrimmed.count != 2 {
        bad.append("rim: untrimmed read \(untrimmed.count) lines not 2 (rim + real)")
    }
    let trimmed3 = rimLines(3)
    if trimmed3.count != 1 {
        bad.append("rim: r=3 read \(trimmed3.count) lines not 1 — the rim survived"
                   + " or the real line went with it")
    } else if trimmed3[0].minY < 80 {
        bad.append("rim: r=3 kept the rim line at y=\(trimmed3[0].minY), not the real one")
    }
    // …and the collar is the whole mechanism, so radius 0 must leave the map alone.
    if rimSubtract(rimMap, region: rimRegion, width: rw, height: rh, radius: 0)
        != rimMap {
        bad.append("rim: radius 0 changed the map")
    }
    // …and it must be exactly `r` wide, which is the one thing the assertions above
    // cannot see. The stubs stop one row short of the box and are 2 px wide, five of
    // them, so radius `r` eats exactly `r` rows of each: 10, 20, 30 px. Without this a
    // collar built at `radius: r - 1` passes every other check — measured, and it would
    // relabel a whole published sweep by one column while `rim1` did nothing at all.
    func rimRemoved(_ radius: Int) -> Int {
        let t = rimSubtract(rimMap, region: rimRegion, width: rw, height: rh,
                            radius: radius)
        return rimMap.filter { $0 }.count - t.filter { $0 }.count
    }
    for (radius, expected) in [(1, 10), (2, 20), (3, 30)] {
        let got = rimRemoved(radius)
        if got != expected {
            bad.append("rim: r=\(radius) removed \(got) px not \(expected)")
        }
    }

    // 7. `lineBoxes` puts the group where the group is — the frame, both halves.
    //
    //    Deliberately on a NON-square page and off-centre vertically, because those are
    //    the two ways a wrong frame hides: on a square page a transposed box lands
    //    plausibly, and a group straddling the middle survives a y-flip. Rows 10-19 of a
    //    200-row page mirror to rows 180-189, so the negative half is the flip's own
    //    answer and not merely "somewhere else".
    let bw = 100, bh = 200
    var probe = Line()
    probe.minX = 30; probe.maxX = 49; probe.minY = 10; probe.maxY = 19
    let boxed = lineBoxes([probe], width: bw, height: bh)
    if boxed.count != 1 {
        bad.append("lineBoxes: made \(boxed.count) boxes from one group, not 1")
    } else {
        let r = Flattener.textRegionMask(boxed, width: bw, height: bh)
        func covered(_ x: Int, _ y: Int) -> Bool { r.count == bw * bh && r[y * bw + x] }
        if !covered(35, 15) { bad.append("lineBoxes: the group's own middle is not covered") }
        if !covered(30, 10) || !covered(49, 19) {
            bad.append("lineBoxes: a corner of the group is not covered")
        }
        if covered(35, 185) {
            bad.append("lineBoxes: the vertically MIRRORED rows are covered — y is flipped")
        }
        if covered(15, 15) {
            bad.append("lineBoxes: a column well left of the group is covered — x is wrong")
        }
        // `mrcBoxPadding` is a quarter of the box's height and is production's, so the
        // pad is real and must not be mistaken for the box: 10 rows tall pads 2.5 rows,
        // so row 5 is outside it and row 185 is nowhere near.
        if covered(35, 5) {
            bad.append("lineBoxes: row 5 is covered — the box is taller than its own group")
        }
    }
    // …and an empty group list widens nothing, which is what makes a `lineN == 0` row a
    // negative control rather than an untested path.
    if !lineBoxes([], width: bw, height: bh).isEmpty {
        bad.append("lineBoxes: an empty group list produced boxes")
    }

    // 8. The widening is a superset, strictly, and it lowers `inkOutsideText`.
    //
    //    One recognised word box on the left, one unrecognised line of the same shape on
    //    the right, ink under both. Without this, `lineBoxes` returning boxes that land
    //    entirely inside `region` would satisfy check 7 and price nothing at all — the
    //    widening would read "free" on every page, which is the failure this whole column
    //    set exists to avoid.
    let ww = 200, wh = 100
    var wGrey = [UInt8](repeating: 255, count: ww * wh)
    for y in 40..<50 { for x in 10..<40 { wGrey[y * ww + x] = 0 } }   // recognised
    for y in 40..<50 { for x in 120..<150 { wGrey[y * ww + x] = 0 } } // missed
    let wordBox = SearchableWriter.BoundingBox(x: 10.0 / 200, y: 40.0 / 100,
                                               width: 30.0 / 200, height: 10.0 / 100)
    let narrow = Flattener.textRegionMask([wordBox], width: ww, height: wh)
    var missed = Line()
    missed.minX = 120; missed.maxX = 149; missed.minY = 40; missed.maxY = 49
    let widened = Flattener.textRegionMask([wordBox] + lineBoxes([missed], width: ww, height: wh),
                                           width: ww, height: wh)
    let grew = zip(narrow, widened).contains { !$0 && $1 }
    let shrank = zip(narrow, widened).contains { $0 && !$1 }
    if !grew { bad.append("widening: the widened region is no larger than the shipped one") }
    if shrank { bad.append("widening: the widened region LOST pixels the shipped one had") }
    let before = outsideFraction(wGrey, keep: narrow, width: ww, height: wh, threshold: 128)
    let after = outsideFraction(wGrey, keep: widened, width: ww, height: wh, threshold: 128)
    if !(after < before) {
        bad.append(String(format: "widening: inkOutsideText did not fall, %.4f -> %.4f",
                          before, after))
    }

    // 9. The byte columns are a Balanced measurement, and nothing in this file says so
    //    with a literal. `mrcLayers` is called on its default `backgroundDownsample`;
    //    if either constant moves, every historical row stops being comparable silently.
    //    `score-text-route` pins the same claim for the same reason — a sibling, not a
    //    duplicate: two tools, two call sites, one fact.
    if Flattener.mrcBackgroundDownsample != Prefs.PhotoDetail.balanced.downsample {
        bad.append("bytes: mrcLayers' default background factor"
                   + " \(Flattener.mrcBackgroundDownsample) is not Balanced's"
                   + " \(Prefs.PhotoDetail.balanced.downsample)")
    }

    // 10. ⛔ THE PORT CHECK, without a corpus. C28's wiring put a copy of this file's
    //     five functions into `Flattener`, and `pageIsAllText()` consults that copy —
    //     so every figure this tool has published is a claim about the shipped rule
    //     only for as long as the two agree. `main` compares them on every measured
    //     page; this compares them on a bitmap, so a machine with no `testdocs/` still
    //     catches a divergence.
    //
    //     ⛔ **ITS OWN BITMAP, and the first version reused check 8's and COULD NOT
    //     FAIL.** Check 8's missed mark is a single solid block, and one component can
    //     never reach `lineMinimumMembers` — so both copies read 0 and agreed trivially.
    //     Measured, not reasoned: a sabotaged port hard-wired to `return 0` passed the
    //     whole self-test. That is the tenth check in this project's history that could
    //     not fail, and the only thing that found it was building the sabotage and
    //     running it (CONTRIBUTING 4a). So this fixture has FIVE glyph-shaped marks on a
    //     baseline outside the boxes, which is a real group of five members, and the
    //     sabotage now goes red on it.
    let pw = 200, ph = 100
    var pGrey = [UInt8](repeating: 255, count: pw * ph)
    var pStencil = [Bool](repeating: false, count: pw * ph)
    // Five recognised glyph-shaped marks — the calibration: height 10, run 3.
    for k in 0..<5 {
        let x0 = 20 + k * 6
        for y in 40..<50 { for x in x0..<(x0 + 3) {
            pGrey[y * pw + x] = 0
            pStencil[y * pw + x] = true
        } }
    }
    // …and five of the same shape on their own baseline, with no box over them.
    for k in 0..<5 {
        let x0 = 120 + k * 6
        for y in 70..<80 { for x in x0..<(x0 + 3) { pGrey[y * pw + x] = 0 } }
    }
    // ⛔ …and THREE MORE baselines the rule must REFUSE — added 2026-08-22, because check
    // 10 as it stood was blind to three of the six constants it compares. A 3x10 mark
    // against a 3x10 calibration sits in the MIDDLE of every band: height 10 in [5, 30],
    // `medianRun` 3 under 6. So loosening this file's own `shapeRunHigh`,
    // `shapeHeightHigh` or `shapeHeightLow` left both copies at one group and the port
    // check agreed while the copy had drifted — over the file every published C28 figure
    // came from. Each of these puts a group just past a different bar: four 8x10 marks
    // are refused on `medianRun` (8 > 2.0 x 3), four 3x36 on the height ceiling
    // (36 > 3.0 x 10) and four 3x3 on the height floor (3 < 0.5 x 10, and area 9 clears
    // `shapeMinimumArea` so it is the floor that refuses them and not the speck test). A
    // copy that loosens any one of the three finds a group `Flattener` does not. The
    // suite's own fixture for the first two is `Tests/main.swift`'s four-dash trio;
    // `BUGS.md` C28 `#### The owed fixture` is why both exist.
    // ⚠️ Measured: the 3x3 baseline is in the rim check's scene as well, so a
    // `shapeHeightLow` loosening trips *two* checks rather than one (`rim: r=3 read 2
    // lines not 1` comes along with the port divergence). Over-detection, not a false
    // positive — the shipped build reads `ok (10 checks)` with all three baselines in.
    for k in 0..<4 {
        let x0 = 20 + k * 14
        for y in 15..<25 { for x in x0..<(x0 + 8) { pGrey[y * pw + x] = 0 } }
    }
    for k in 0..<4 {
        let x0 = 20 + k * 6
        for y in 30..<33 { for x in x0..<(x0 + 3) { pGrey[y * pw + x] = 0 } }
    }
    for k in 0..<4 {
        let x0 = 20 + k * 6
        for y in 58..<94 { for x in x0..<(x0 + 3) { pGrey[y * pw + x] = 0 } }
    }
    let pRecognised = SearchableWriter.BoundingBox(x: 18.0 / 200, y: 39.0 / 100,
                                                  width: 30.0 / 200, height: 12.0 / 100)
    let pNarrow = Flattener.textRegionMask([pRecognised], width: pw, height: ph)
    /// The out-of-region components this file finds. **One copy**, called by both the
    /// group count and the fixture guard: the first version of the guard built this array
    /// a second time inline, which is a third copy of three lines nothing ties together —
    /// the mistake the rim check's own map builder was written to avoid.
    func pComps(_ keep: [Bool]) -> [Comp] {
        let win = interiorWindow(width: pw, height: ph)
        let m = inkOutsideMap(pGrey, region: keep, width: pw, height: ph,
                              threshold: 128).map
        return components(m, width: pw, height: ph, x0: win.x0, y0: win.y0,
                          x1: win.x1, y1: win.y1)
    }
    /// This file's own answer, through this file's own five functions.
    func pMine(_ keep: [Bool]) -> Int {
        let win = interiorWindow(width: pw, height: ph)
        let gc = components(pStencil, width: pw, height: ph, x0: win.x0, y0: win.y0,
                            x1: win.x1, y1: win.y1).filter { $0.area >= shapeMinimumArea }
        let cs = pComps(keep)
        let gh = median(gc.map(\.height))
        return lines(cs, accepted: textish(cs, glyphHeight: gh,
                                           glyphRun: median(gc.map(\.medianRun))),
                     glyphHeight: gh).count
    }
    //     The fixture must produce EXACTLY the one group it was built to produce, or this
    //     is check 8 again. Asserted before the two copies are compared, so a fixture that
    //     drifted reports itself rather than making the comparison vacuous.
    //     ⛔ `!= 1` and not `< 1`, and the review of this diff is why: with `< 1` the four
    //     refused baselines could start being ACCEPTED — the exact drift they were added to
    //     detect — and this guard would wave a count of 2 through while both copies agreed.
    let pMineNarrow = pMine(pNarrow)
    if pMineNarrow != 1 {
        bad.append("port: the fixture makes \(pMineNarrow) line groups rather than 1, so"
                   + " the comparison below cannot fail — check 8's own mistake")
    }
    //     …and all FOUR baselines must be there and whole: 5 missed + 4 too-wide + 4
    //     too-tall + 4 too-short = 17 out-of-region components. This catches a baseline
    //     the padded box swallowed or a neighbour it merged with; it does NOT catch one
    //     clipped from an end, which stays four components — that is what pinning the
    //     group count at exactly 1 above is for, and the two guards are complementary
    //     rather than belt-and-braces.
    let pCompN = pComps(pNarrow).count
    if pCompN != 17 {
        bad.append("port: the fixture has \(pCompN) out-of-region components, not 17, so"
                   + " a baseline is missing or merged and the refusals prove nothing")
    }
    let pPortNarrow = Flattener.textLineGroupsOutsideText(pGrey, stencil: pStencil,
                                                          region: pNarrow, width: pw,
                                                          height: ph, threshold: 128)
    if pPortNarrow != pMineNarrow {
        bad.append("port: Flattener says \(pPortNarrow.map { "\($0)" } ?? "nil")"
                   + " and this file says \(pMineNarrow) over the missed baseline")
    }
    //     …and the other direction on the same pixels: box the missed baseline too and
    //     both must read 0. Without this a port that returned the RIGHT non-zero count
    //     for the wrong reason would still pass above.
    let pMissed = SearchableWriter.BoundingBox(x: 118.0 / 200, y: 69.0 / 100,
                                               width: 30.0 / 200, height: 12.0 / 100)
    let pWide = Flattener.textRegionMask([pRecognised, pMissed], width: pw, height: ph)
    let pPortWide = Flattener.textLineGroupsOutsideText(pGrey, stencil: pStencil,
                                                        region: pWide, width: pw,
                                                        height: ph, threshold: 128)
    if pPortWide != 0 || pMine(pWide) != 0 {
        bad.append("port: with the baseline recognised the counts are"
                   + " \(pPortWide.map { "\($0)" } ?? "nil") and \(pMine(pWide)), not 0 and 0")
    }
    //     …and the run bound, which nothing else in this file and no corpus page can
    //     reach at the shipped 8,000,000. CONTRIBUTING 4c: an error branch that has
    //     never executed is R31, R32 and H2.
    if Flattener.textLineGroupsOutsideText(pGrey, stencil: pStencil, region: pNarrow,
                                           width: pw, height: ph, threshold: 128,
                                           runLimit: 1) != nil {
        bad.append("port: a run limit of 1 did not truncate")
    }

    return bad
}

// MARK: - Main

let args = CommandLine.arguments
if args.contains("--self-test") {
    let bad = selfTest()
    if bad.isEmpty {
        // ⚠️ A LITERAL, so it goes stale silently — it read 9 with ten groups in the
        // function until 2026-08-22, and a count that does not move when a check is
        // added is worth less than no count, because it reads as corroboration. If you
        // add a group, change this number in the same edit.
        // ⚠️ Still TEN, and deliberately: 2026-08-22 added two fixture guards *inside*
        // group 10 rather than an eleventh group, and this literal counts groups. A draft
        // read 11 and made the number uncountable — the exact failure the comment above
        // describes, committed in the same hour as the comment.
        print("score-shape-term: self-test ok (10 checks)")
        exit(0)
    }
    FileHandle.standardError.write(Data(
        ("score-shape-term: self-test FAILED\n  " + bad.joined(separator: "\n  ") + "\n").utf8))
    exit(5)
}
guard args.count > 1 else {
    FileHandle.standardError.write(Data(
        "usage: score-shape-term <pdf> [page…]   (or --self-test)\n".utf8))
    exit(2)
}
let src = URL(fileURLWithPath: args[1])
Prefs.register(migrate: false)
let settings = Prefs.Snapshot.current()

let work = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("shapeterm-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }

guard let doc = PDFDocument(url: src), doc.pageCount > 0 else {
    FileHandle.standardError.write(Data("cannot open \(src.path)\n".utf8))
    exit(1)
}
let requested = args.dropFirst(2).compactMap { Int($0) }
let pages: [Int] = requested.isEmpty
    ? Flattener.sampleIndices(count: doc.pageCount, wanted: 12).map { $0 + 1 }
    : requested

/// Where to write the four PNGs, or `nil`. Refused loudly rather than created quietly
/// on a bad path, for the reason `score-text-route`'s `INKDUMP` gives: an empty dump
/// directory reads as "there was nothing on those pages".
let dumpDirectory: URL? = {
    guard let raw = ProcessInfo.processInfo.environment["SHAPEDUMP"], !raw.isEmpty
    else { return nil }
    let url = URL(fileURLWithPath: raw, isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    } catch {
        FileHandle.standardError.write(Data(
            "SHAPEDUMP=\(raw) cannot be created: \(error.localizedDescription)\n".utf8))
        exit(2)
    }
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
          isDir.boolValue else {
        FileHandle.standardError.write(Data("SHAPEDUMP=\(raw) is not a directory\n".utf8))
        exit(2)
    }
    return url
}()

/// C28 question 4. Whether to price the widening in bytes.
///
/// A knob rather than always-on because it changes what this tool costs by an order of
/// magnitude: two `mrcLayers` calls and two `jbig2` encodes a page, against the single
/// grey render every other column shares. A sweep that wants only the shape columns —
/// which is every sweep this tool has run so far — should not start paying for an encoder.
///
/// Refused loudly on any other value, for `INKBAR`'s reason: `WIDENBYTES=0` or
/// `WIDENBYTES=yes` silently printing eleven dashes reads as "measured, and it costs
/// nothing", which is the worst answer this tool could give.
let widenBytes: Bool = {
    guard let raw = ProcessInfo.processInfo.environment["WIDENBYTES"], !raw.isEmpty
    else { return false }
    guard raw == "1" else {
        FileHandle.standardError.write(Data(
            "WIDENBYTES=\(raw) is not understood; the only accepted value is 1\n".utf8))
        exit(2)
    }
    return true
}()

/// The encoder, located only when the byte columns were asked for — this tool is useful
/// on a machine with no jbig2 and must stay so.
let jbig2Tool: String? = {
    guard widenBytes else { return nil }
    guard let found = JBIG2.encoder else {
        FileHandle.standardError.write(Data(
            "WIDENBYTES=1 but jbig2 was not found; there are no bytes to measure\n".utf8))
        exit(3)
    }
    return found
}()

func bytes(_ url: URL) -> Int { (try? Data(contentsOf: url).count) ?? 0 }

/// One page, alone in its own PDF: `Flattener.flatten` takes a document, and the
/// recognition below must run on the bitmap the app publishes (R40).
func isolate(_ index: Int) -> URL? {
    guard let page = doc.page(at: index - 1) else { return nil }
    let one = PDFDocument()
    one.insert(page, at: 0)
    let url = work.appendingPathComponent("p\(index).pdf")
    return one.write(to: url) ? url : nil
}

/// The one printer, and the columns in one place — T14, A12.3 and T18 are three
/// separate defects from counting tab escapes by eye.
/// The rim sweep's columns are generated from `rimRadii` rather than typed out, so the
/// header and the row cannot disagree about how many there are — which is the defect T14,
/// A12.3 and T18 each are, in a header written by hand beside a row written by hand.
/// The byte columns, in one list for the same reason: the header and the row read it, and
/// the `-` filler on a row that did not measure them is `count` dashes rather than eleven
/// typed by hand. Appended AFTER `verdict` so the 31 columns every committed
/// `SHAPETERM-*.tsv` was written against stay a byte-identical prefix.
let wideColumns = ["wideN", "wideInkOut", "stenPx", "wideStenPx",
                   "shipSten", "wideSten", "shipBytes", "wideBytes", "byteDelta",
                   "shipBg", "wideBg"]
let columns = ["page", "w", "h", "otsu", "inkPx", "outPx", "inkOut", "mapFrac",
               "stenFrac", "stenD3", "glyphN", "glyphH", "glyphRun",
               "ccN", "txtN", "txtPx", "txtShare",
               "lineN", "linePx", "lineShare", "topLine"]
    + rimRadii.flatMap { ["rim\($0)N", "rim\($0)Px", "rim\($0)Top"] }
    + ["verdict"] + wideColumns
func row(_ page: Int, w: String = "-", h: String = "-", otsu: String = "-",
         inkPx: String = "-", outPx: String = "-", inkOut: String = "-",
         mapFrac: String = "-", stenFrac: String = "-", stenD3: String = "-",
         glyphN: String = "-", glyphH: String = "-", glyphRun: String = "-",
         ccN: String = "-", txtN: String = "-", txtPx: String = "-", txtShare: String = "-",
         lineN: String = "-", linePx: String = "-", lineShare: String = "-",
         topLine: String = "-", rim: [String]? = nil, verdict: String,
         wide: [String]? = nil) {
    let fields = ["p\(page)", w, h, otsu, inkPx, outPx, inkOut, mapFrac,
                  stenFrac, stenD3, glyphN, glyphH, glyphRun,
                  ccN, txtN, txtPx, txtShare, lineN, linePx, lineShare, topLine]
        + (rim ?? [String](repeating: "-", count: rimRadii.count * 3))
        + [verdict.replacingOccurrences(of: "\t", with: " ")]
        + (wide ?? [String](repeating: "-", count: wideColumns.count))
    precondition(fields.count == columns.count)
    print(fields.joined(separator: "\t"))
}

print(columns.joined(separator: "\t"))
var identityFailed = 0, measured = 0
/// C28's port check: the shipped `Flattener` rule against this file's own copy.
var portAgreed = 0, portDisagreed = 0
var dumpMissing: [String] = []
/// Pages where `WIDENBYTES` was asked for and one of the two layerings declined — an
/// `mrcLayers` that returned nil or a jbig2 that failed. Counted and reported rather than
/// left as a dash, because "the widening costs nothing" and "nothing was measured" print
/// the same way otherwise.
var wideRefused = 0

for index in pages {
    guard let single = isolate(index), let page = doc.page(at: index - 1) else { continue }

    // A12.2, exactly as `score-text-route` guards it: isolating a page can move the
    // rebuild resolution, and a row measured at the wrong resolution is not that page's.
    if let isolated = PDFDocument(url: single)?.page(at: 0) {
        let before = Flattener.rebuildDPI(of: page)
        let after = Flattener.rebuildDPI(of: isolated)
        if abs(before - after) > 0.5 {
            row(index, verdict: String(format:
                "SKIP isolation moved the rebuild DPI %.0f->%.0f (A12.2)", before, after))
            continue
        }
    }

    let autoDir = work.appendingPathComponent("auto\(index)")
    try? FileManager.default.createDirectory(at: autoDir, withIntermediateDirectories: true)
    guard let auto = try? Flattener.flatten(single, to: work.appendingPathComponent("a\(index).pdf"),
                                            mode: .auto, pngDirectory: autoDir),
          let first = auto.first else {
        row(index, verdict: "SKIP flatten produced nothing")
        continue
    }
    guard case .jpeg(let jpegURL) = first.content else {
        row(index, verdict: "already 1-bit")
        continue
    }

    let box = Flattener.fullBox(of: page)
    let dpi = Flattener.rebuildDPI(of: page)
    let scale = dpi / 72.0
    let w = max(Int((box.width * scale).rounded()), 1)
    let h = max(Int((box.height * scale).rounded()), 1)
    guard let grey = Flattener.renderGrey(page, box: box, scale: scale,
                                          width: w, height: h, from: .mediaBox) else {
        row(index, verdict: "SKIP no grey render")
        continue
    }
    let otsu = Flattener.otsuThreshold(of: grey)

    // The boxes come from the bitmap the app publishes, not from a re-render: R40.
    var boxes: [SearchableWriter.BoundingBox] = []
    if let source = CGImageSourceCreateWithURL(jpegURL as CFURL, nil),
       let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
       let observations = try? Recogniser.recognise(image, settings: settings) {
        boxes = observations.map { $0.boundingBox }
    }
    guard !boxes.isEmpty else {
        row(index, w: "\(w)", h: "\(h)", otsu: "\(otsu)",
            verdict: "SKIP no words — mrcLayers refuses this page too")
        continue
    }
    let region = Flattener.textRegionMask(boxes, width: w, height: h)
    let inkOut = Flattener.inkOutsideText(grey, region: region, width: w, height: h,
                                          threshold: otsu)

    // The exact map, blanked outside the interior window rather than cropped to it, so
    // every rect below is already in the page's own frame.
    let win = interiorWindow(width: w, height: h)
    let built = inkOutsideMap(grey, region: region, width: w, height: h, threshold: otsu)
    let map = built.map, inkPx = built.ink, outPx = built.outside
    let mapFrac = inkPx > 0 ? Double(outPx) / Double(inkPx) : 0
    // The identity. Printed to four places like the sweep's own column, and compared at
    // full precision: this is the whole claim that the map is the guard's own set.
    let identity = abs(mapFrac - inkOut) <= 1e-12
    if !identity { identityFailed += 1 }

    // The two candidates from `score-text-route`'s header, each as a fraction directly
    // comparable to `inkOut`.
    let sauvola = Flattener.sauvolaMask(grey, width: w, height: h,
                                        window: Flattener.sauvolaWindow(dpi: dpi,
                                                                        width: w, height: h))
    var stencil = sauvola
    if stencil.count == w * h {
        for i in 0..<(w * h) where !region[i] { stencil[i] = false }
    } else {
        stencil = region
    }
    let stenFrac = outsideFraction(grey, keep: stencil, width: w, height: h, threshold: otsu)
    let stenD3 = outsideFraction(grey, keep: dilate(stencil, width: w, height: h, radius: 3),
                                 width: w, height: h, threshold: otsu)

    // The calibration: the recognised glyphs are the stencil's own components.
    let glyphComps = components(stencil, width: w, height: h,
                                x0: win.x0, y0: win.y0, x1: win.x1, y1: win.y1)
        .filter { $0.area >= shapeMinimumArea }
    let glyphH = median(glyphComps.map(\.height))
    let glyphRun = median(glyphComps.map(\.medianRun))

    let comps = components(map, width: w, height: h,
                           x0: win.x0, y0: win.y0, x1: win.x1, y1: win.y1)
    let accepted = textish(comps, glyphHeight: glyphH, glyphRun: glyphRun)
    let txtPx = accepted.reduce(0) { $0 + comps[$1].area }
    let found = lines(comps, accepted: accepted, glyphHeight: glyphH)
    let linePx = found.reduce(0) { $0 + $1.area }
    let biggest = found.max { $0.area < $1.area }
    func rect(_ l: Line) -> String {
        "\(l.maxX - l.minX + 1)x\(l.maxY - l.minY + 1)+\(l.minX)+\(l.minY)"
    }
    let topLine = biggest.map(rect) ?? "-"

    // ⛔ THE PORT CHECK, added 2026-08-22 with C28's wiring, and it is the only thing
    // that says the shipped rule is the rule this tool measured. Every figure in C28's
    // decision — 12 of 12 type-losers, 3 of 51 non-losers, +2,362,625 B — was produced
    // by the five functions ABOVE in this file, and `pageIsAllText()` now consults a
    // port of them in `Flattener`. Two copies of an arithmetic, one of which supplies
    // the evidence for the other, is this register's most repeated instrument defect;
    // and unlike the identity guard on `mapFrac` a divergence here would be **silent**,
    // because nothing else in this tool reads the shipped function.
    //
    // So: same `grey`, same `stencil`, same `region`, same Otsu, and the two counts must
    // agree on every page. Counted rather than only warned about, because "the check is
    // there" and "the check ran" are different claims and the summary line below is what
    // tells them apart.
    let portN = Flattener.textLineGroupsOutsideText(grey, stencil: stencil, region: region,
                                                    width: w, height: h, threshold: otsu)
    if portN == found.count {
        portAgreed += 1
    } else {
        portDisagreed += 1
        FileHandle.standardError.write(Data(
            ("port-check p\(index + 1): Flattener says \(portN.map { "\($0)" } ?? "nil") "
             + "and this tool says \(found.count)\n").utf8))
    }

    // The rim sweep. Each radius gets its own components pass over its own trimmed map,
    // not a filter over `comps`: cutting a collar out of the map can SPLIT a component as
    // well as shrink it, and a piece of a rejected component can be accepted where its
    // parent was not — so the count is not monotone in the radius and it has to be
    // re-derived rather than subtracted. The calibration stays the undilated stencil's:
    // the page's type scale is not a function of the collar.
    var rimFields: [String] = []
    var rimResult: [(radius: Int, comps: [Comp], lines: [Line])] = []
    for r in rimRadii {
        let trimmed = rimSubtract(map, region: region, width: w, height: h, radius: r)
        let rc = components(trimmed, width: w, height: h,
                            x0: win.x0, y0: win.y0, x1: win.x1, y1: win.y1)
        let racc = textish(rc, glyphHeight: glyphH, glyphRun: glyphRun)
        let rlines = lines(rc, accepted: racc, glyphHeight: glyphH)
        let top = rlines.max { $0.area < $1.area }.map(rect) ?? "-"
        rimFields += ["\(rlines.count)", "\(rlines.reduce(0) { $0 + $1.area })", top]
        rimResult.append((r, rc, rlines))
    }

    // C28 question 4 at the `textRegionMask` seam: what the widening costs in bytes.
    //
    // Two `mrcLayers` calls on the same page differing in ONE property — the box list —
    // so the two totals cannot come from two pieces of code that drifted. It is
    // `score-text-route`'s `layered` / `layeredAtBar` pattern with the boxes substituted
    // instead of the bar, and on a page whose `lineN` is 0 it is the same call twice,
    // which is a determinism control every such row carries for free.
    //
    // `backgroundDownsample` is left at the default argument deliberately: passing a
    // literal here would be a second copy of shipped arithmetic (T15's shape), and the
    // self-test pins that the default *is* `PhotoDetail.balanced.downsample`, so every
    // byte figure below is a Balanced measurement and stays comparable to the rest of
    // this campaign's.
    var wideFields: [String]? = nil
    var shipMask: URL? = nil, wideMask: URL? = nil
    if widenBytes, let jbig2 = jbig2Tool {
        let extra = lineBoxes(found, width: w, height: h)
        let wideBoxes = boxes + extra
        let wideRegion = Flattener.textRegionMask(wideBoxes, width: w, height: h)
        let wideInkOut = Flattener.inkOutsideText(grey, region: wideRegion,
                                                 width: w, height: h, threshold: otsu)
        // The stencil's own ink, from the same `sauvola` the columns above use. This is
        // the column that says whether the missed ink actually ENTERED the stencil rather
        // than the region merely growing around it: the map's components come from Otsu
        // and the stencil from Sauvola, and nothing guarantees the two agree on a pale
        // line. Counted over the whole page, not the interior window — the stencil is not
        // interior-cropped, and mixing the two frames is the trap sub-step 4 recorded.
        func stencilPixels(_ keep: [Bool]) -> Int {
            guard sauvola.count == w * h, keep.count == w * h else { return 0 }
            var n = 0
            for i in 0..<(w * h) where sauvola[i] && keep[i] { n += 1 }
            return n
        }
        func price(_ list: [SearchableWriter.BoundingBox], _ stem: String)
            -> (sten: Int, total: Int, bg: String, mask: URL)? {
            guard let layers = Flattener.mrcLayers(for: page, boxes: list, into: work,
                                                   stem: stem, inColour: first.isColour)
            else { return nil }
            let out = work.appendingPathComponent("\(stem).jbig2")
            guard (try? JBIG2.encode(png: layers.mask, to: out, using: jbig2)) != nil
            else { return nil }
            let sten = bytes(out)
            // A zero-byte stream is a jbig2 that ran and produced nothing, which would
            // otherwise be summed into a total that looks like a cheap page.
            guard sten > 0 else { return nil }
            return (sten, sten + bytes(layers.background) + bytes(layers.foreground),
                    "\(layers.backgroundWidth)x\(layers.backgroundHeight)", layers.mask)
        }
        let ship = price(boxes, "ms\(index)")
        let wide = price(wideBoxes, "mw\(index)")
        if ship == nil || wide == nil { wideRefused += 1 }
        // Held for `SHAPEDUMP` below: the two stencils are the only positive control a
        // byte column can have. `wideStenPx > stenPx` says ink entered the 1-bit layer;
        // only reading the two PNGs at 1:1 over the same rect says the WORDS did.
        shipMask = ship?.mask
        wideMask = wide?.mask
        wideFields = ["\(extra.count)",
                      String(format: "%.4f", wideInkOut),
                      "\(stencilPixels(region))", "\(stencilPixels(wideRegion))",
                      ship.map { "\($0.sten)" } ?? "-",
                      wide.map { "\($0.sten)" } ?? "-",
                      ship.map { "\($0.total)" } ?? "-",
                      wide.map { "\($0.total)" } ?? "-",
                      ship.flatMap { s in
                          wide.map { String(format: "%+d", $0.total - s.total) } } ?? "-",
                      ship?.bg ?? "-", wide?.bg ?? "-"]
    }

    measured += 1
    row(index, w: "\(w)", h: "\(h)", otsu: "\(otsu)",
        inkPx: "\(inkPx)", outPx: "\(outPx)",
        inkOut: String(format: "%.4f", inkOut),
        mapFrac: String(format: "%.4f", mapFrac),
        stenFrac: String(format: "%.4f", stenFrac),
        stenD3: String(format: "%.4f", stenD3),
        glyphN: "\(glyphComps.count)",
        glyphH: String(format: "%.0f", glyphH),
        glyphRun: String(format: "%.0f", glyphRun),
        ccN: "\(comps.count)", txtN: "\(accepted.count)", txtPx: "\(txtPx)",
        txtShare: outPx > 0 ? String(format: "%.4f", Double(txtPx) / Double(outPx)) : "-",
        lineN: "\(found.count)", linePx: "\(linePx)",
        lineShare: outPx > 0 ? String(format: "%.4f", Double(linePx) / Double(outPx)) : "-",
        topLine: topLine, rim: rimFields,
        verdict: identity ? "ok"
            : String(format: "⛔ mapFrac %.6f != inkOut %.6f", mapFrac, inkOut),
        wide: wideFields)

    if let dump = dumpDirectory {
        let stem = "\(src.deletingPathExtension().lastPathComponent.prefix(40))-p\(index)"
        func maskPNG(_ set: [Bool]) -> Data? {
            var px = [UInt8](repeating: 255, count: w * h)
            for i in 0..<(w * h) where set[i] { px[i] = 0 }
            return Flattener.greyPNG(px, width: w, height: h)
        }
        var textishOnly = [Bool](repeating: false, count: w * h)
        var linesOnly = [Bool](repeating: false, count: w * h)
        // Components hold statistics rather than pixels, so the two derived masks are
        // painted from their bounding boxes intersected with the map — which is the map's
        // own ink inside those boxes and never a filled rectangle.
        //
        // ⚠️ `through` is the mask the components were found in, and it is a parameter
        // rather than `map` because the rim files below are components of a *trimmed*
        // map: painting them through the untrimmed one would put collar pixels the radius
        // removed back inside a surviving component's bounding box, so the picture would
        // show more ink than the rule accepted. Found by the adversarial review of the
        // commit that added the rim sweep, after a crop had already been read off the
        // leaky version.
        func paint(_ into: inout [Bool], _ from: [Comp], _ indices: [Int],
                   through mask: [Bool]) {
            for i in indices {
                let c = from[i]
                for y in c.minY...c.maxY {
                    let base = y * w
                    for x in c.minX...c.maxX where mask[base + x] { into[base + x] = true }
                }
            }
        }
        paint(&textishOnly, comps, accepted, through: map)
        paint(&linesOnly, comps, found.flatMap(\.members), through: map)
        var promised: [(String, () -> Data?)] = [
            ("\(stem)-source.png", { Flattener.greyPNG(grey, width: w, height: h) }),
            ("\(stem)-map.png", { maskPNG(map) }),
            ("\(stem)-textish.png", { maskPNG(textishOnly) }),
            ("\(stem)-lines.png", { maskPNG(linesOnly) }),
        ]
        // One `-lines` per rim radius, so the positive control can be read at the radius
        // being considered rather than only at zero. Painted through that radius's OWN
        // trimmed mask — never through `map`, which is the defect `paint`'s comment above
        // records — so the pixels are the page's own ink, are only the ink the rule at this
        // radius accepted, and are never a filled rectangle.
        for entry in rimResult {
            // Recomputed rather than carried on the common path: three full-page masks is
            // several megabytes a page and only a dumping run ever needs them.
            let trimmed = rimSubtract(map, region: region, width: w, height: h,
                                      radius: entry.radius)
            var rimOnly = [Bool](repeating: false, count: w * h)
            paint(&rimOnly, entry.comps, entry.lines.flatMap(\.members), through: trimmed)
            promised.append(("\(stem)-rim\(entry.radius)-lines.png", { maskPNG(rimOnly) }))
        }
        // C28 question 4's positive control: production's own two stencils, copied rather
        // than rebuilt here, so what a reader looks at is the PNG `mrcLayers` handed to
        // jbig2 and the byte columns counted. Only present under `WIDENBYTES=1`, and the
        // per-page accounting line below counts them like every other promised file.
        if let ship = shipMask {
            promised.append(("\(stem)-stencil-ship.png", { try? Data(contentsOf: ship) }))
        }
        if let wide = wideMask {
            promised.append(("\(stem)-stencil-wide.png", { try? Data(contentsOf: wide) }))
        }
        var wrote = 0
        for (name, make) in promised {
            guard let data = make(),
                  (try? data.write(to: dump.appendingPathComponent(name))) != nil else {
                dumpMissing.append(name)
                continue
            }
            wrote += 1
        }
        // Per page, counted from what this page wrote. A first version printed
        // `promised.count - dumpMissing.count` — a page count against a run-long list, so
        // page 2 would report 3 files after page 1 lost one, on a run where page 2 wrote
        // all four. `score-text-route`'s own accounting is per page for the same reason.
        print("SHAPEDUMP p\(index): \(wrote) of \(promised.count) file(s) written")
    }
}

print("")
print("pages measured \(measured)"
      + "; port agreed on \(portAgreed)"
      + (identityFailed > 0 ? "; ⛔ IDENTITY FAILED on \(identityFailed)" : "")
      + (portDisagreed > 0 ? "; ⛔ PORT DISAGREED on \(portDisagreed)" : "")
      + (wideRefused > 0 ? "; ⚠️ widening not priced on \(wideRefused)" : "")
      + (dumpMissing.isEmpty ? "" : "; ⚠️ dump missing \(dumpMissing.joined(separator: ", "))"))
if identityFailed > 0 { exit(6) }
// C28. A silent divergence between the shipped rule and this tool's copy would
// make every figure this file has ever published a claim about code that is not
// running, so it is an exit and not a warning. 7 rather than 6 so a caller can
// tell the two instrument failures apart.
if portDisagreed > 0 { exit(7) }
