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
// Usage:
//
//   mkdir -p /tmp/h && cp Tools/score-shape-term.swift /tmp/h/main.swift
//   swiftc -O -o /tmp/score-shape-term -target "$(uname -m)-apple-macos13.0" \
//     $(ls Sources/*.swift | grep -v App.swift) /tmp/h/main.swift
//   /tmp/score-shape-term --self-test
//   /tmp/score-shape-term "<pdf>" [page…]              # 1-indexed; default: a spread
//   SHAPEDUMP=/tmp/look /tmp/score-shape-term "<pdf>" 3
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
//
// Reading `-lines.png` beside `-source.png` at the same crop is the positive control the
// share columns cannot be: it says whether the term named the words the register says
// that page lost, or something else the same size.
//
// Exit codes: 1 unreadable PDF, 2 a refused `SHAPEDUMP`, 5 a failed self-test,
// **6 the identity above failed on some page** — the rows are still printed, because a
// broken map is worth seeing, but no share column on that page means anything.
//
// It needs no jbig2 and never layers a page: there are no byte columns here, which is
// what makes it cheaper than `score-text-route` on the same pages.
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
/// A square and not a disk. `Disk:3` prints as a 7x7 kernel and the two differ only at
/// the corners, so the square is the strictly more generous stand-in — which is the safe
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

    return bad
}

// MARK: - Main

let args = CommandLine.arguments
if args.contains("--self-test") {
    let bad = selfTest()
    if bad.isEmpty {
        print("score-shape-term: self-test ok (5 checks)")
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
let columns = ["page", "w", "h", "otsu", "inkPx", "outPx", "inkOut", "mapFrac",
               "stenFrac", "stenD3", "glyphN", "glyphH", "glyphRun",
               "ccN", "txtN", "txtPx", "txtShare",
               "lineN", "linePx", "lineShare", "topLine", "verdict"]
func row(_ page: Int, w: String = "-", h: String = "-", otsu: String = "-",
         inkPx: String = "-", outPx: String = "-", inkOut: String = "-",
         mapFrac: String = "-", stenFrac: String = "-", stenD3: String = "-",
         glyphN: String = "-", glyphH: String = "-", glyphRun: String = "-",
         ccN: String = "-", txtN: String = "-", txtPx: String = "-", txtShare: String = "-",
         lineN: String = "-", linePx: String = "-", lineShare: String = "-",
         topLine: String = "-", verdict: String) {
    let fields = ["p\(page)", w, h, otsu, inkPx, outPx, inkOut, mapFrac,
                  stenFrac, stenD3, glyphN, glyphH, glyphRun,
                  ccN, txtN, txtPx, txtShare, lineN, linePx, lineShare, topLine,
                  verdict.replacingOccurrences(of: "\t", with: " ")]
    precondition(fields.count == columns.count)
    print(fields.joined(separator: "\t"))
}

print(columns.joined(separator: "\t"))
var identityFailed = 0, measured = 0
var dumpMissing: [String] = []

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
    let topLine = biggest.map {
        "\($0.maxX - $0.minX + 1)x\($0.maxY - $0.minY + 1)+\($0.minX)+\($0.minY)"
    } ?? "-"

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
        topLine: topLine,
        verdict: identity ? "ok"
            : String(format: "⛔ mapFrac %.6f != inkOut %.6f", mapFrac, inkOut))

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
        func paint(_ into: inout [Bool], _ indices: [Int]) {
            for i in indices {
                let c = comps[i]
                for y in c.minY...c.maxY {
                    let base = y * w
                    for x in c.minX...c.maxX where map[base + x] { into[base + x] = true }
                }
            }
        }
        paint(&textishOnly, accepted)
        paint(&linesOnly, found.flatMap(\.members))
        let promised: [(String, () -> Data?)] = [
            ("\(stem)-source.png", { Flattener.greyPNG(grey, width: w, height: h) }),
            ("\(stem)-map.png", { maskPNG(map) }),
            ("\(stem)-textish.png", { maskPNG(textishOnly) }),
            ("\(stem)-lines.png", { maskPNG(linesOnly) }),
        ]
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
      + (identityFailed > 0 ? "; ⛔ IDENTITY FAILED on \(identityFailed)" : "")
      + (dumpMissing.isEmpty ? "" : "; ⚠️ dump missing \(dumpMissing.joined(separator: ", "))"))
if identityFailed > 0 { exit(6) }
