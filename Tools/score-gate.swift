// The release gate: every document in a corpus through the whole app, end to end.
//
// This is the check the unit suite cannot do. `run_tests.sh` exercises the parts;
// this exercises `OCRModel.start()` over hundreds of real documents at the app's
// own concurrency and reports what came out the other side. Worth running before
// any release that touches `Flattener`, `SearchableWriter` or `JBIG2` — 1.8.0 and
// 1.9.0 both shipped without it, and the run that finally happened found R38.
//
//   mkdir -p /tmp/h && cp Tools/score-gate.swift /tmp/h/main.swift
//   swiftc -O -o /tmp/gate -target "$(uname -m)-apple-macos13.0" \
//     $(ls Sources/*.swift | grep -v App.swift) /tmp/h/main.swift
//   swiftc -O -o /tmp/visionocr-recognise -target "$(uname -m)-apple-macos13.0" \
//     Sources/{Prefs,Runner,Recogniser,SearchableWriter,Flattener,JBIG2}.swift \
//     Helper/main.swift
//   VISIONOCR_HELPER=/tmp/visionocr-recognise /tmp/gate testdocs /tmp/gateout
//
// The pixel verification below can also be pointed at a corpus and an output
// directory that already exist, without a run:
//
//   /tmp/gate --verify testdocs /tmp/gateout
//
// That mode exists so the check itself can be tested — the whole reason A12.1
// stood is that nothing had ever made this tool's verification fail. Corrupting
// a real output's image streams and running `--verify` over the pair takes
// seconds; reproducing it through a 78-minute run does not.
//
// **The output directory must be empty of PDFs.** It refuses otherwise, because
// `uniqueOutputs` seeds its claimed set with the batch's *inputs* and not with
// whatever is already at the destination, so a second run into a used directory
// republishes over the first run's outputs — and the old version of this tool
// then enumerated the directory and reported the leftovers as this run's
// products: `documents 1 … outputs 2 characters 15187` (A12.6).
//
// **Build the helper and point at it, or the timing means nothing** (R40).
// Recognition runs in helper processes because Vision does not parallelise
// across concurrent requests inside one process; without one this harness
// silently falls back to in-process recognition and measures the 187-minute
// configuration while looking exactly like a 75-minute one. It says which it is
// doing in its opening line — read that line before believing the minutes.
//
// **Run it through `start()`, never in a serial loop over `makeSearchablePDF`.**
// A serial version was tried and projected **9.1 hours** for work this does in
// **78 minutes**: `start()` runs files in parallel at `defaultConcurrency`, the
// serial harness ran one at a time. Its timing measured a configuration the app
// never runs, which is worse than no number at all.
//
// Three things it must keep doing, all learned the hard way:
//
//  1. `warnDigitalText` **off**. The digital-text confirmation is a modal, and in
//     a headless run it sits there indefinitely — indistinguishable from a hang.
//  2. Read the **output PDFs** at the end, not just the outcome enum. Page count
//     is not sufficient verification (invariant 1) and neither is a success
//     value; a stream a reader cannot decode still opens as a page.
//  3. Read the **pixels**, not the text layer. This is A12.1, and requirement 2
//     did not achieve it: the whole verification was
//     `PDFDocument(url:)?.string?.count`, which reads the text layer
//     `SearchableWriter` draws itself and which is independent of the image
//     underneath it. 400 bytes of `0x41` into the middle of each of a five-page
//     output's image streams changed **48.3% / 48.8% / 52.7% / 50.8% / 84.3%**
//     of each page's rendered pixels and moved *none* of `characters`, `outputs`
//     or `colour`, with `qpdf --check` calling the file clean. So every page of
//     every output is now rendered and reduced to a darkness figure, each
//     output is paired with the input it came from, and a page that renders
//     blank over an input page that has ink is a release-blocking failure.
//
// What the pixel check does and does not catch, stated so the next person does
// not over-trust it:
//
//  * **Catches wholesale destruction, by the resemblance correlation and only by
//    it.** Not by anything going blank: A12.1's own corruption left no page blank
//    at all — see the `Ink` doc comment, which records mean ink going 0.05973 to
//    0.37470 with exit 0. A decoder fed rubbish emits rubbish.
//  * **Catches** a page-count or output-path divergence from the run's own
//    resolved outputs, a success with nothing at the destination, and a document
//    that did not convert.
//  * **Does not catch a fade** — R56's shape, a pale drawing erased. A ratio was
//    tried and measured useless: R56's fixture and an undamaged control land 0.9%
//    apart, because the number is paper tone rather than ink. `fadeCount` has the
//    figures.
//  * **Does not catch a partial blob** — R57's shape. The tonal-plate fixture
//    scores 0.924 and 0.92x the ink, which is also what a correct rebuild of that
//    page looks like. What catches both of those is the per-page ink, resemblance
//    and darkness columns written to `per-document.tsv`, diffed against the
//    previous run's file — the same mechanism, and the same reason, as the
//    per-document character column below.
//
// The baseline it establishes is recorded in HANDOFF.md.

import AppKit
import PDFKit

// The full-corpus gate, driven through OCRModel.start() at the app's own
// concurrency — which is what the 1.7.0 baseline measured.
//
// A serial loop over makeSearchablePDF was tried first and projected 9 hours
// against the baseline's 23 minutes. That is not a regression, it is a
// different instrument: start() runs files in parallel at defaultConcurrency
// and the serial harness ran one at a time. Measuring throughput with the
// concurrency removed would have produced a number worth nothing.
final class Harness: NSObject, NSApplicationDelegate {
    var model: OCRModel!
    var started = Date()
    var total = 0
    var outDir = URL(fileURLWithPath: NSTemporaryDirectory())
    /// Consecutive 20-second ticks on which the batch was neither running nor
    /// pre-flighting and had produced no outcome. `!isRunning && done > 0` was
    /// the only way this harness could ever finish, so a run that never started
    /// — a mistyped corpus path, a refusal — sat here for ever, which is the
    /// hang requirement 1 exists to prevent arriving through another door
    /// (A12.6).
    var idleTicks = 0

    // MARK: - Pixels

    /// A page's pixels, reduced to a scalar and a coarse map.
    ///
    /// `darkness` is `(255 − mean luminance) / 255`: 0 for a blank white sheet,
    /// higher the more ink. Threshold-free on purpose — an ink-coverage fraction
    /// needs a cutoff, and a cutoff calibrated on text pages is the wrong cutoff
    /// for a tone plate. `grid` is the same figure per cell of a `cells`×`cells`
    /// lattice laid over the page.
    ///
    /// **`darkness` alone is not enough, established by trying it.** The first
    /// version of this check tested each output page for renders-as-paper, on the
    /// assumption that a stream a decoder chokes on draws nothing. Measured
    /// against A12.1's own corruption — 400 bytes of `0x41` into five image
    /// streams — the pages did not go blank: mean ink went **0.05973 → 0.37470**,
    /// because a JBIG2 arithmetic decoder fed rubbish emits rubbish rather than
    /// failing. Nothing was blank, nothing was reported, exit 0. A decode-error
    /// check fails for the same reason: no error is raised.
    ///
    /// So the only honest test is against the input, and the comparison has to
    /// survive the rebuild legitimately changing every pixel's value (1-bit
    /// binarisation, MRC layering, a different resolution). `grid` correlation
    /// does: it asks whether the ink is still *in the same places*, which
    /// binarising preserves and destruction does not, and being scale- and
    /// offset-invariant it does not care that a 1-bit page is uniformly darker
    /// than its greyscale original.
    struct Ink {
        static let cells = 28
        var darkness: Double
        var spread: Int
        var grid: [Double]      // cells * cells, row-major from the top
        /// Which cells actually had pixels behind them. See `ink`.
        var covered: [Bool]

        /// **Uniform, which is not the same as white.** The blank test used to be
        /// `spread == 0 || darkness < 0.004`, and the darkness half was wrong in
        /// both directions: a sparse title page of real text can sit under 0.004,
        /// and calling it blank meant its pixels were **never compared at all** —
        /// a page could be destroyed to near-white over a near-white source and
        /// the comparison would be skipped rather than made. A page is blank when
        /// it has no variation, full stop; whether that flat page is paper or a
        /// solid black sheet is what `darkness` then says.
        var isFlat: Bool { spread <= 2 }
    }

    /// Pearson correlation of two ink maps, or nil when either page is too flat
    /// for a correlation to mean anything (a blank sheet has no structure to
    /// match, and dividing by its zero variance would invent one).
    static func correlation(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        let n = Double(a.count)
        let ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
        var sa = 0.0, sb = 0.0, sab = 0.0
        for i in 0..<a.count {
            let da = a[i] - ma, db = b[i] - mb
            sa += da * da; sb += db * db; sab += da * db
        }
        // 1e-6 on the *variance* of a 0…1 quantity: a page whose cells all sit
        // within a thousandth of each other carries no structure.
        guard sa / n > 1e-6, sb / n > 1e-6 else { return nil }
        return sab / (sa * sb).squareRoot()
    }

    /// Subtracts each cell's local mean over a 5×5 window, leaving the structure
    /// at ink scale and discarding anything smoother than the window.
    ///
    /// **Needed because the 1-bit route is *meant* to throw the paper away.** The
    /// grid comparison on its own reads a page's broad paper tone, not where the
    /// ink is, and a scan of aged paper has a tone that varies across the sheet.
    /// `1954 - Why.pdf` p3 is the case: the output keeps every word legible and
    /// drops the grey, and the raw grids correlate at **0.435** — below any
    /// threshold that catches destruction. High-passed, the same pair reads
    /// **0.655**, and the corrupted fixtures stay at 0.17–0.26.
    static func highPassed(_ g: [Double], radius r: Int = 2) -> [Double] {
        let cells = Ink.cells
        var out = [Double](repeating: 0, count: g.count)
        for y in 0..<cells {
            for x in 0..<cells {
                var sum = 0.0, n = 0.0
                for dy in -r...r {
                    for dx in -r...r {
                        let yy = y + dy, xx = x + dx
                        guard yy >= 0, yy < cells, xx >= 0, xx < cells else { continue }
                        sum += g[yy * cells + xx]
                        n += 1
                    }
                }
                out[y * cells + x] = g[y * cells + x] - sum / n
            }
        }
        return out
    }

    /// How much an output page still resembles its input, in [-1, 1].
    ///
    /// The **larger** of the raw-grid and high-passed correlations, because the
    /// two see different things and a page only has to be recognisable through
    /// one of them: the raw grid holds where a page whose tone is unchanged, the
    /// high-passed one holds where the rebuild legitimately whitened the paper.
    /// Taking the maximum is what makes one threshold serve both.
    ///
    /// **Except when the page came out much darker, and that exception is load
    /// bearing.** The high pass exists to forgive *paper removal*, which makes a
    /// page lighter. Allowing it unconditionally let one genuinely destroyed page
    /// through: `doc-b p2` with its image stream overwritten scored raw −0.198 and
    /// high-passed **+0.510**, above the floor, reported instead of blocked —
    /// while being **9.2x darker** than its input. Nothing legitimate measured
    /// here exceeds 1.13x. So above `darkerLimit` the raw correlation stands
    /// alone, and that page fails on −0.198 as it should.
    ///
    /// **Calibrated on real material, and the numbers are the whole argument.**
    /// Every legitimate page measured sits at or above 0.655; every page whose
    /// image stream was destroyed sits at or below 0.261:
    ///
    /// ```
    ///                                        raw    high-passed  resemblance
    ///   corrupted doc-b p2   9.2x darker   -0.198     0.510       -0.198
    ///   corrupted doc-a p1   7.9x darker   -0.189     0.196       -0.189
    ///   corrupted doc-a p2   4.4x darker   +0.107     0.173       +0.107
    ///   corrupted doc-a p3   5.4x darker   +0.154     0.261       +0.154
    ///   corrupted doc-b p1   4.2x darker   +0.106     0.095       +0.106
    ///   ----------------------------- the 0.45 floor ---------------------
    ///   1954 - Why p3  grey paper gone     +0.435     0.655       +0.655
    ///   1947 magazine p3                   +0.764     0.738       +0.764
    ///   AI 2027 p51                        +0.700     0.794       +0.794
    ///   1954 - Why p5                      +0.720     0.808       +0.808
    ///   tonal-plate fixture (R57's page)   +0.924     0.811       +0.924
    ///   Boltanski p23 (203-page book)      +0.995     0.980       +0.995
    ///   clean fixture doc-a p1             +1.000     0.999       +1.000
    /// ```
    ///
    /// Every corrupted row takes its **raw** value, because every one is more
    /// than `darkerLimit` darker than its input — which is the rule below, and a
    /// first version of this table showed `max(raw, high)` for them and so
    /// contradicted the code four lines away.
    ///
    /// A per-cell standard-deviation grid was measured too and is *worse*: it
    /// scores the corrupted pages 0.387–0.599, because noise has texture.
    ///
    /// ## The known gap: this is a whole-page figure, and it dilutes
    ///
    /// A reviewer of this diff built the gate and measured **0.52** on a page
    /// whose lower 55% had been overwritten — above the floor, so a page with a
    /// screenful of noise came back REPORTED and the run exited 0. Their fixture
    /// had text over the whole sheet; the ones here have it in the upper third,
    /// so destroying the image destroyed the only structure and the figure
    /// collapsed. **The gap is real even though four attempts to reproduce that
    /// number failed** — 400 bytes mid-stream and a corrupted tail, on both a
    /// third-page-text and a full-sheet-text fixture, all four blocked.
    ///
    /// **The obvious repair was built, measured, and reverted.** Scoring a page
    /// as the worst of itself and its sixteen 7×7 regions produced **11
    /// release-blocking findings on 36 real, undamaged documents**, against 0 for
    /// the whole-page figure on the same 1,701 pages. Four of the eleven were
    /// regions where the raw grids were too flat to correlate at all and the
    /// high-passed residual of two nearly-blank regions was compared instead —
    /// noise against noise. The rest (0.39 to 0.72) are legitimate quarter-pages
    /// that simply do not correlate well on their own. A gate with eleven false
    /// blockers is worse than one with a known dilution, so the whole-page figure
    /// stands and this is recorded rather than half-fixed.
    ///
    /// What a real fix needs: a region rule that requires *raw* structure on both
    /// sides before a region may vote, a floor calibrated on regions rather than
    /// inherited from the page, and a corpus run to confirm it. `BUGS.md` T9.
    static func resemblance(_ a: Ink, _ b: Ink) -> (best: Double, raw: Double?, high: Double?)? {
        let both = (0..<a.grid.count).filter { a.covered[$0] && b.covered[$0] }
        guard both.count >= 16 else { return nil }
        let aHigh = highPassed(a.grid), bHigh = highPassed(b.grid)
        let raw = correlation(both.map { a.grid[$0] }, both.map { b.grid[$0] })
        let high = correlation(both.map { aHigh[$0] }, both.map { bHigh[$0] })
        let muchDarker = b.darkness >= 0.01 && a.darkness > darkerLimit * b.darkness
        let candidates = muchDarker ? [raw] : [raw, high]
        guard let best = candidates.compactMap({ $0 }).max() else { return nil }
        return (best, raw, high)
    }

    /// Above this ratio of output ink to input ink, the high-passed correlation is
    /// not allowed to rescue a page. 2.0 against a measured legitimate maximum of
    /// 1.13x and a measured destroyed minimum of 4.24x — a factor of two of margin
    /// on each side.
    static let darkerLimit = 2.0

    /// Below this, an output page does not resemble the page it came from and the
    /// release is blocked. Midway between the worst legitimate page measured
    /// (0.655) and the best destroyed one (0.261).
    static let resemblanceFloor = 0.45
    /// Below this it is reported rather than blocking.
    static let resemblanceWatch = 0.75
    /// **A fade ratio was tried as an R56 detector and it does not work.** Kept as
    /// a *drift* column and nothing more, because the measurement that killed it
    /// is worth more than the idea:
    ///
    /// ```
    ///   pale-drawing fixture   drawing erased    src 0.07178  out 0.02513  0.35009
    ///   text-only fixture      nothing damaged   src 0.07000  out 0.02515  0.35934
    /// ```
    ///
    /// **0.9% apart.** R56's own fixture and an undamaged control are
    /// indistinguishable, because what the ratio measures on the 1-bit route is
    /// the *paper tone the rebuild is meant to discard* — 0.070 to 0.025 in both
    /// — and not the erased drawing. It is the same confound `highPassed` exists
    /// for on the correlation side, and it cannot be fixed by moving a threshold:
    /// there is no threshold between 0.35009 and 0.35934 that means anything.
    ///
    /// This was almost shipped as "the only signal in the tool that can see R56",
    /// with a cutoff of 0.35 derived by **hand-dividing the rounded printout**
    /// (0.0251 / 0.0718 = 0.34958) instead of the numbers the code computes — so
    /// it sat on the wrong side of a strict `<` and could not have fired on R56's
    /// fixture even in principle. An adversarial pass over this diff measured it.
    /// FEATURES.md's shape signal remains the only thing that would see R56, and
    /// `Tools/score-threshold-loss.swift` remains the estimator built for it.
    ///
    /// Counted at this ratio so a run-to-run diff has something to compare; no
    /// page is named on it and no release is blocked by it.
    static let fadeCount = 0.5

    /// Renders a page and measures its ink.
    ///
    /// sRGB rather than DeviceGray deliberately: **PDFKit draws no highlight
    /// into a grey context** (CLAUDE.md), and an instrument that silently cannot
    /// see a whole class of mark is A12.5's shape.
    static func ink(of page: PDFPage, edge: Int = 220) -> Ink? {
        // **The media box, and not the crop box.** Measured: comparing an
        // output's crop box against its input's produced a **-0.49894**
        // correlation on an ordinary 203-page book and 177 release-blocking
        // findings across 36 documents, all of them false. The reason is the
        // property CLAUDE.md states — "media box for what is kept, crop box for
        // what is shown" — so a rebuilt page's crop box is its whole sheet while
        // the source's is a window on it:
        //
        //     Boltanski p23  source  crop 779x628 at (45,81)   media 1031x727
        //                    output  crop 1031x727 at (0,0)    media 1031x727
        //
        // A cropped window against a whole sheet is two different regions, and a
        // correlation between them is noise with a sign. Both sides take the
        // media box, which is the region the app itself preserves.
        let box = page.bounds(for: .mediaBox)
        guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0
        else { return nil }
        // `/Rotate` is applied by `draw(with:to:)` and *not* by `bounds(for:)`.
        // `Flattener.boxSize` carries the same comment, and A12.5 is what
        // ignoring it costs: score-annotations sized its buffer from the
        // unrotated box, drew with rotation applied, and skipped every mark on
        // every quarter-turned page while exiting 0.
        let turned = abs(page.rotation / 90) % 2 == 1
        let ptW = turned ? box.height : box.width
        let ptH = turned ? box.width : box.height
        let scale = Double(edge) / Double(max(ptW, ptH))
        let w = max(1, Int((Double(ptW) * scale).rounded()))
        let h = max(1, Int((Double(ptH) * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h,
                                 bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                 bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        // Paper first. A PDF page draws nothing where it has nothing and a fresh
        // context is black, so an unpainted background would read as a sheet of
        // solid ink — which is the same sign as the failure being looked for.
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        page.draw(with: .mediaBox, to: ctx)
        guard let raw = ctx.data else { return nil }
        let px = raw.assumingMemoryBound(to: UInt8.self)
        let cells = Ink.cells
        var sum = 0, lo = 255, hi = 0
        var cellSum = [Double](repeating: 0, count: cells * cells)
        var cellN = [Double](repeating: 0, count: cells * cells)
        for y in 0..<h {
            let row = y * ctx.bytesPerRow
            // The context's row 0 is the bottom of the page; the grid runs from
            // the top, so that two grids of the same page always align whichever
            // way each was produced.
            let cy = min(cells - 1, (h - 1 - y) * cells / h)
            for x in 0..<w {
                let p = row + x * 4
                // Rec. 601 luma in integers; the weights sum to 256.
                let l = (54 * Int(px[p]) + 183 * Int(px[p + 1]) + 19 * Int(px[p + 2])) >> 8
                sum += l
                lo = min(lo, l)
                hi = max(hi, l)
                let c = cy * cells + min(cells - 1, x * cells / w)
                cellSum[c] += Double(255 - l)
                cellN[c] += 1
            }
        }
        let mean = Double(sum) / Double(w * h)
        // A cell that received no pixels is *unknown*, not white. Filling it with
        // 0.0 in both grids put a perfectly-correlated point into every
        // comparison, and on a page whose aspect ratio leaves whole rows of cells
        // empty that inflates the correlation towards 1 — the one direction a
        // gate must never drift. `covered` carries which cells mean anything and
        // the comparison intersects the two.
        var covered = [Bool](repeating: false, count: cells * cells)
        let grid = (0..<(cells * cells)).map { i -> Double in
            guard cellN[i] > 0 else { return 0 }
            covered[i] = true
            return cellSum[i] / cellN[i] / 255
        }
        return Ink(darkness: max(0, (255 - mean) / 255), spread: hi - lo,
                   grid: grid, covered: covered)
    }

    static func fmt(_ d: Double) -> String { String(format: "%.5f", d) }

    // MARK: - Run

    /// Every PDF under `root`, in the order `start()` would see them.
    static func corpus(under root: String) -> [URL] {
        var files: [URL] = []
        if let e = FileManager.default.enumerator(at: URL(fileURLWithPath: root),
                                                 includingPropertiesForKeys: nil) {
            for case let u as URL in e where u.pathExtension.lowercased() == "pdf" {
                files.append(u)
            }
        }
        files.sort { $0.path < $1.path }
        return files
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        // Spelled out, because getting it wrong was silent in both directions:
        // `--verify <one path>` fell through to *run* mode with "--verify" as the
        // corpus root — printing a refusal about republishing over the very
        // directory it had been asked to read — and a bare `gate` indexed out of
        // range. Both measured.
        let args = CommandLine.arguments
        let verifyOnly = args.count > 1 && args[1] == "--verify"
        guard args.count >= (verifyOnly ? 4 : 3) else {
            let me = (args[0] as NSString).lastPathComponent
            print("usage: \(me) <corpus-dir> <empty-output-dir>")
            print("       \(me) --verify <corpus-dir> <output-dir>")
            print("")
            print("The first form runs every document through OCRModel.start() and then")
            print("verifies the products. The second only verifies an existing pair, which")
            print("is how the verification itself gets tested.")
            fflush(stdout)
            exit(64)
        }
        let root = args[verifyOnly ? 2 : 1]
        outDir = URL(fileURLWithPath: args[verifyOnly ? 3 : 2])
        let fm = FileManager.default

        if verifyOnly {
            let files = Self.corpus(under: root)
            if files.isEmpty {
                print("score-gate: no PDFs under \(root) — nothing to verify.")
                fflush(stdout)
                exit(2)
            }
            print("verify only: \(files.count) input(s) against \(outDir.path)")
            fflush(stdout)
            // Everything present is treated as a success to be verified; the
            // run-shaped tallies are skipped, because there was no run.
            report(inputs: files, succeeded: Set(files), didRun: false, minutes: 0)
            return
        }

        try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)

        // Refused rather than tolerated: see the header. A used output directory
        // makes both the tallies and any byte comparison against the previous
        // run meaningless, and the failure is silent.
        var existing = 0
        if let e = fm.enumerator(at: outDir, includingPropertiesForKeys: nil) {
            for case let u as URL in e where u.pathExtension.lowercased() == "pdf" { existing += 1 }
        }
        if existing > 0 {
            print("score-gate: \(outDir.path) already holds \(existing) PDF(s). "
                  + "Point at an empty directory — this run would publish over them, "
                  + "and their pages would be counted as its own.")
            fflush(stdout)
            exit(2)
        }

        let d = UserDefaults.standard
        Prefs.register()
        // No modal can be allowed to stop a headless run: the digital-text
        // warning is exactly the prompt that would sit there for nine hours.
        d.set(false, forKey: Prefs.warnDigitalText)
        d.set(false, forKey: Prefs.besideOriginal)
        d.set(outDir.path, forKey: Prefs.outputFolder)
        d.set(false, forKey: Prefs.openWhenDone)
        d.set(Prefs.Mode.searchablePDF.rawValue, forKey: Prefs.mode)
        d.set(true, forKey: Prefs.rebuildImages)
        d.set(true, forKey: Prefs.useJBIG2)

        let files = Self.corpus(under: root)
        total = files.count
        // A mistyped corpus path used to reach `start()` with nothing to do and
        // then wait for a completion that could not arrive (A12.6).
        if files.isEmpty {
            print("score-gate: no PDFs under \(root) — nothing to gate.")
            fflush(stdout)
            exit(2)
        }

        model = OCRModel()
        _ = model.add(files)
        print("documents: \(model.files.count) (found \(total))  concurrency: \(Prefs.defaultConcurrency)")
        // Stated, not assumed, and stated as what this run will actually *do*
        // rather than as what is available. A run without the helper is a
        // different measurement — same correctness, 2.5x the minutes — and the
        // two are indistinguishable from the output otherwise. The first version
        // of this line reported the helper as present and said nothing about
        // whether the batch would reach for it, which on a one-document run is
        // exactly the wrong answer: `helperIsWorthIt` declines below two files.
        let concurrency = max(1, min(d.integer(forKey: Prefs.concurrency), Prefs.maxConcurrency))
        let wanted = Recogniser.helperIsWorthIt(concurrency: concurrency,
                                                files: model.files.count)
        switch (wanted, Recogniser.helperPath()) {
        case (true, .some(let path)): print("recognition: helper processes (\(path))")
        case (true, .none):
            print("recognition: IN-PROCESS — no helper found, expect ~2.5x the time")
        case (false, _):
            print("recognition: in-process — this batch is too small to overlap "
                  + "(\(model.files.count) file(s) at \(concurrency) at a time)")
        }
        fflush(stdout)
        started = Date()
        model.start()

        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] t in
            guard let self else { return }
            MainActor.assumeIsolated {
                let done = self.model.outcomes.count
                let mins = Int(Date().timeIntervalSince(self.started) / 60)
                if !self.model.isRunning && done > 0 {
                    t.invalidate()
                    self.finish(minutes: mins)
                    return
                }
                // **This covers a run that never starts, and nothing else.**
                // Once any document has finished, `done > 0` and the `else`
                // resets the counter, so a batch that stalls *mid-run* still
                // prints its progress line for ever — A12.6's hang in the one
                // form still reachable, left open deliberately rather than
                // claimed closed: a stall bound over a corpus needs to survive a
                // single 64.84 MP page, and guessing one here is how R44
                // happened. `isCommitted`, not `isRunning`, because the
                // pre-flight is minutes during which `isRunning` is false.
                if !self.model.isCommitted && done == 0 {
                    self.idleTicks += 1
                    if self.idleTicks >= 2 {
                        t.invalidate()
                        print("score-gate: the batch never started — "
                              + "\(self.model.files.count) file(s) queued, no outcome after "
                              + "\(mins) min and nothing committed. `start()` refused, or the "
                              + "pre-flight did.")
                        for line in self.model.log.suffix(6) { print("  \(line.text)") }
                        fflush(stdout)
                        exit(3)
                    }
                } else {
                    self.idleTicks = 0
                }
                print("  \(done)/\(self.model.files.count)  \(mins) min")
                fflush(stdout)
            }
        }
    }

    @MainActor func finish(minutes: Int) {
        var succeeded: Set<URL> = []
        var failed = 0
        for (url, o) in model.outcomes {
            if case .succeeded = o { succeeded.insert(url) } else { failed += 1 }
        }
        report(inputs: model.files, succeeded: succeeded, didRun: true, minutes: minutes,
               failed: failed)
    }

    /// Verifies the products and prints the result block.
    ///
    /// Separated from `finish` so `--verify` can drive it over a corpus and an
    /// output directory that already exist. `didRun` is what distinguishes the
    /// two: the run-shaped tallies (successes plus failures equalling documents,
    /// outputs equalling successes) are meaningless without a run, and asserting
    /// them anyway would be a check that cannot fail in one mode and cannot pass
    /// in the other.
    func report(inputs: [URL], succeeded: Set<URL>, didRun: Bool, minutes: Int,
                failed: Int = 0) {
        let ok = succeeded.count

        // The mapping `run()` used, recomputed from `run()`'s own function
        // rather than inferred from the names on disk — and then checked against
        // the names on disk, so a drift between this and `run()` shows up as a
        // loud failure instead of a corpus that was never verified. The suffix
        // and extension mirror `run()`'s `isSearchable` branch; the mode is
        // forced to `searchablePDF` above, and the cross-check below is what
        // keeps that from being a second, quietly diverging copy of the rule
        // (A12.4's shape).
        let expected = OCRModel.uniqueOutputs(for: inputs, besideOriginal: false,
                                              folder: outDir, suffix: ".ocr", extension: "pdf")

        var hard: [String] = [], soft: [String] = []
        var chars = 0, colour = 0, outs = 0, bytes = 0, pagesSeen = 0, blankPages = 0
        var fadedPages = 0
        var darknessTotal = 0.0
        // Per document as well as in total, written beside the outputs. The
        // 2026-08-13 run came back 23 characters short of the previous one out of
        // 34.2 million — 1 part in 1.5 million, with every direct comparison of
        // the two routes exact — and it could not be localised, because a single
        // total says only that something moved somewhere. A diff of two of these
        // files names the document in one command. `pages`, `ink` and `blank`
        // are here for the same reason and are the only thing that localises a
        // *partial* pixel loss, which the absolute check below cannot see.
        var perDocument: [(name: String, chars: Int, bytes: Int,
                           pages: Int, ink: Double, blank: Int, worst: Double,
                           faded: Int, dimmest: Double)] = []
        let fm = FileManager.default

        for input in inputs.sorted(by: { $0.path < $1.path }) {
            guard succeeded.contains(input) else { continue }
            guard let out = expected[input] else {
                hard.append("\(input.lastPathComponent): no output path resolved for a success")
                continue
            }
            guard fm.fileExists(atPath: out.path) else {
                hard.append(didRun
                            ? "\(out.lastPathComponent): reported success, nothing at the destination"
                            : "\(out.lastPathComponent): no such output for \(input.lastPathComponent)")
                continue
            }
            outs += 1
            let size = ((try? fm.attributesOfItem(atPath: out.path))?[.size] as? Int) ?? 0
            bytes += size
            guard let doc = PDFDocument(url: out) else {
                hard.append("\(out.lastPathComponent): does not open")
                continue
            }
            let these = doc.string?.count ?? 0
            chars += these
            // Whole file, not the first 4 MB. The prefix scan biased the colour
            // count against exactly the picture-heavy documents most likely to
            // carry colour (A12.8). Still a *syntax* test: a `/DeviceRGB` inside
            // a compressed object stream is invisible to it, so this remains a
            // lower bound — just not one that shrinks with file size.
            if let raw = try? Data(contentsOf: out, options: .mappedIfSafe),
               raw.range(of: Data("/DeviceRGB".utf8)) != nil { colour += 1 }

            let src = PDFDocument(url: input)
            if let srcPages = src?.pageCount, srcPages != doc.pageCount {
                hard.append("\(out.lastPathComponent): \(doc.pageCount) pages "
                            + "against the input's \(srcPages)")
            }
            var darkSum = 0.0, blanks = 0, worst = 1.0, faded = 0, dimmest = 1.0
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else {
                    hard.append("\(out.lastPathComponent) p\(i + 1): no page object")
                    continue
                }
                guard let ink = Self.ink(of: page) else {
                    hard.append("\(out.lastPathComponent) p\(i + 1): does not render")
                    continue
                }
                darkSum += ink.darkness
                darknessTotal += ink.darkness
                pagesSeen += 1
                if ink.isFlat { blanks += 1; blankPages += 1 }

                guard let sp = src?.page(at: i), let si = Self.ink(of: sp) else {
                    soft.append("\(out.lastPathComponent) p\(i + 1): the input page could not be "
                                + "rendered, so this page's pixels are unverified "
                                + "(output darkness \(Self.fmt(ink.darkness)))")
                    continue
                }
                let where_ = "\(out.lastPathComponent) p\(i + 1)"
                let inks = "darkness \(Self.fmt(ink.darkness)) against \(Self.fmt(si.darkness))"
                // Ink that fell away without the layout changing. Tracked
                // separately from resemblance because the two see different
                // failures, and R56 is only visible to this one.
                // Counted and recorded, never reported as a finding: see
                // `fadeCount` for the measurement that says this number is paper
                // tone rather than ink loss.
                if si.darkness >= 0.01 {
                    let ratio = ink.darkness / si.darkness
                    if ratio < Self.fadeCount { faded += 1; fadedPages += 1 }
                    dimmest = min(dimmest, ratio)
                }
                switch (Self.resemblance(ink, si), ink.isFlat, si.isFlat) {
                case (_, true, true) where ink.darkness < 0.5:
                    // Flat in, flat out, and pale: a scanned blank verso, which is
                    // real and common. Correlating two featureless sheets is
                    // meaningless.
                    break
                case (_, true, true):
                    // Flat both sides and *dark* — a solid sheet is not a blank
                    // one, and `spread == 0` alone would have called it blank and
                    // said nothing.
                    hard.append("\(where_): renders as one flat dark sheet — \(inks)")
                case (_, true, false):
                    hard.append("\(where_): renders featureless over an input page with "
                                + "structure — \(inks)")
                case (_, false, true):
                    soft.append("\(where_): has structure over a featureless input page "
                                + "— \(inks)")
                case (.none, _, _):
                    soft.append("\(where_): neither page has enough structure to compare "
                                + "(\(inks))")
                case (.some(let r), _, _):
                    worst = min(worst, r.best)
                    let detail = "resemblance \(Self.fmt(r.best)) "
                        + "(raw \(r.raw.map(Self.fmt) ?? "nil"), "
                        + "high-passed \(r.high.map(Self.fmt) ?? "nil")), \(inks)"
                    if r.best < Self.resemblanceFloor {
                        hard.append("\(where_): the ink is not where the input's is — \(detail)")
                    } else if r.best < Self.resemblanceWatch {
                        soft.append("\(where_): weak resemblance to the input page — \(detail)")
                    }
                }
            }
            perDocument.append((out.lastPathComponent, these, size, doc.pageCount,
                                doc.pageCount > 0 ? darkSum / Double(doc.pageCount) : 0,
                                blanks, worst, faded, dimmest))
        }

        // Tallies that add up, asserted rather than assumed. Invariant 1's shape
        // inside the instrument that enforces invariant 1 (A12.6).
        if didRun {
            // A failed document is a release-blocking result, and it was not.
            // `failed` never produced a `hard` entry, so only a tally
            // *inconsistency* blocked — and successes + failures = documents is
            // perfectly consistent with a document the app could not convert.
            // Measured: a three-document corpus with one unreadable file printed
            // "failed 1" and exited **0**, so `gate testdocs /tmp/out && ship`
            // shipped. Found by an adversarial pass over this diff.
            if failed > 0 {
                hard.append("\(failed) document(s) did not convert — a gate that exits 0 "
                            + "with a failure in the run is a gate nobody can chain")
                for input in inputs.sorted(by: { $0.path < $1.path })
                where !succeeded.contains(input) {
                    hard.append("  \(input.lastPathComponent): not converted")
                }
            }
            if ok + failed != inputs.count {
                hard.append("tally: \(ok) succeeded + \(failed) failed against "
                            + "\(inputs.count) documents")
            }
            if outs != ok {
                hard.append("tally: \(outs) outputs verified against \(ok) successes")
            }
            // Anything in the output directory this run did not resolve. The old
            // version enumerated the directory and reported whatever it found as
            // this run's products, so a previous run's leftovers were counted as
            // outputs and their pages as pages (A12.6). Reaching this now means
            // the suffix rule above has drifted from `run()`'s, because the
            // directory was empty before the run.
            let produced = Set(expected.values.map { $0.standardizedFileURL.path })
            if let e = fm.enumerator(at: outDir, includingPropertiesForKeys: nil) {
                for case let u as URL in e where u.pathExtension.lowercased() == "pdf" {
                    if !produced.contains(u.standardizedFileURL.path) {
                        hard.append("\(u.lastPathComponent): in the output directory and not one "
                                    + "of this run's resolved outputs — the output-path rule here "
                                    + "has drifted from run()'s")
                    }
                }
            }
        }

        // Never overwritten. `per-document.tsv` is the file this tool's own header
        // points at as the only thing that localises a partial pixel loss, and
        // rewriting it in place destroyed the baseline **by the act of
        // re-measuring** — including under `--verify`, which is nothing but a
        // re-measurement. The empty-directory refusal does not protect it either:
        // it counts PDFs, and keeping the tsv while deleting multi-gigabyte
        // outputs is the plausible thing to do.
        let stem = didRun ? "per-document" : "per-document-verify"
        var breakdown = outDir.appendingPathComponent("\(stem).tsv")
        var attempt = 2
        while FileManager.default.fileExists(atPath: breakdown.path), attempt < 1000 {
            breakdown = outDir.appendingPathComponent("\(stem) \(attempt).tsv")
            attempt += 1
        }
        try? Data((["file\tcharacters\tbytes\tpages\tink\tblank\tworstPage\tfaded\tdimmest"]
                   + perDocument.sorted { $0.name < $1.name }.map {
                       "\($0.name)\t\($0.chars)\t\($0.bytes)\t\($0.pages)"
                       + "\t\(Self.fmt($0.ink))\t\($0.blank)\t\(Self.fmt($0.worst))"
                       + "\t\($0.faded)\t\(Self.fmt($0.dimmest))"
                   })
                  .joined(separator: "\n").appending("\n").utf8)
            .write(to: breakdown, options: .atomic)
        print("""

        === RESULT ===
          documents    \(inputs.count)
          succeeded    \(ok)
          failed       \(failed)
          outputs      \(outs)
          pages        \(pagesSeen)
          characters   \(chars)
          colour       \(colour)
          mean ink     \(Self.fmt(pagesSeen > 0 ? darknessTotal / Double(pagesSeen) : 0))
          blank pages  \(blankPages)
          faded pages  \(fadedPages)
          worst page   \(Self.fmt(perDocument.map(\.worst).min() ?? 1))
          dimmest page \(Self.fmt(perDocument.map(\.dimmest).min() ?? 1))
          output bytes \(bytes / 1_048_576) MB
          minutes      \(minutes)
        === 1.7.0 baseline: 255 ok, 0 failed, 12.6M chars, 15 colour, 23 min ===
        === note: 232 testdocs, NOT the 255-document library set ===
        === note: pages, mean ink, blank/faded pages, worst and dimmest page are \
        new with A12.1's fix and have no baseline before it ===
        === per-document characters, bytes, pages, ink, blanks, resemblance, fade: \(breakdown.path) ===
        """)
        if !soft.isEmpty {
            print("\n=== REPORTED (\(soft.count)) — not release-blocking ===")
            for line in soft.prefix(40) { print("  \(line)") }
            if soft.count > 40 { print("  … \(soft.count - 40) more") }
        }
        if !hard.isEmpty {
            print("\n=== RELEASE-BLOCKING (\(hard.count)) ===")
            for line in hard.prefix(60) { print("  \(line)") }
            if hard.count > 60 { print("  … \(hard.count - 60) more") }
            fflush(stdout)
            exit(1)
        }
        fflush(stdout)
        // exit(0) rather than NSApp.terminate in --verify mode: nothing has been
        // started that needs unwinding, and terminate on a run loop that was
        // never entered does not return.
        if didRun { NSApp.terminate(nil) } else { exit(0) }
    }
}

let app = NSApplication.shared
let h = Harness()
app.delegate = h
app.setActivationPolicy(.accessory)
app.run()
