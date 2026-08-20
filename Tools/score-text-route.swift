// What would it actually save to route an all-text page off the layered route and
// onto the 1-bit one?
//
// TODO.md item 1 ("move `isPicture` after recognition") is priced in two places
// with two different numbers. One says a 568-page book "carries tone layers on 522
// pages that a correctly-routed book would not carry at all — the remaining 4 MB
// over the original". The other says "a text page routed to 1-bit costs 44 KB where
// a layered one costs 46". The first is the cost of the tone layers; the second is
// the *net* difference, and they disagree by about 4x, because a whole-page Otsu
// stencil is bigger than the Sauvola stencil confined to Vision's word boxes. The
// tone layers you stop paying for are partly re-spent on a fatter stencil.
//
// This measures the published bytes, per page, both ways, using the shipped code
// for each:
//
//   layered   `Flattener.mrcLayers` (so R50's all-text shrink applies exactly as it
//             ships) + `JBIG2.encode` of its stencil + the two tone JPEGs.
//   1-bit     `Flattener.flatten` in **Black & white** mode over the same single
//             page — which is what a correctly-routed page costs, by definition —
//             + `JBIG2.encode` of the PNG it writes.
//
// Neither number is reconstructed here. The reason `bilevelImage` is not called
// directly is that it is file-private, and reproducing its bit packing in a tool is
// the divergence this directory's README warns about; driving `flatten` costs one
// extra render and cannot drift.
//
// It also prints `inkOutsideText`, which is R50's signal and the one a routing
// decision after recognition would have to use, so the pages where the two routes
// are close can be read against how confidently the page is text at all.
//
// **And it prices a different bar on that signal, which is C26's sub-step 3.**
// `INKBAR=<bar>` publishes every page twice — once at the shipped
// `textPageInkOutsideThreshold` and once at the bar given — and prints what the
// difference costs in bytes. That was the measurement C26 was blocked on: three
// drawings were erased because `inkOut` reads 0.049–0.066 against what was then a bar
// of 0.08, a bar at 0.045 refuses all three, and R49/R50 are the entries about what
// refusing a page costs.
//
// ⛔ **The shipped bar became 0.045 on 2026-08-19, so `INKBAR=0.045` — the command this
// header used to give, and the one every record of that campaign quotes — now exits 2**
// on the guard below: a bar equal to the shipped one has nothing to compare. **Drive it
// with `INKBAR=0.08` to reproduce those measurements.** It is the same comparison with
// the columns swapped — `layered` is now the new behaviour and `layeredAtBar` the old
// one — so a page reported as costing 4.54x reads as the same ratio the other way
// round. The arithmetic did not move; which side is called "shipped" did. `Flattener.textPageInkOutsideThresholdOverride` is the seam, and it
// substitutes the *comparand* rather than the verdict, so R56's `paleDrawing` term
// keeps participating — see that property's doc comment, including why
// `keepEveryPixel` is NOT part of that argument.
//
// ⚠️ **One PDF per invocation.** Every argument after the path is a page number, so a
// glob of the corpus silently measures document 1 and prints a summary that reads like
// a corpus run. A sweep needs a driver loop; `score-threshold-loss` is the tool that
// takes a path list. And the default sample is up to **12** pages a document, not 2.
//
// The stencil is **not** re-encoded for the second measurement: it comes from the
// Sauvola mask intersected with the region, neither of which reads a downsample
// factor, so the two runs' stencils are the same bytes. That is checked per page
// rather than assumed — a row whose stencil moves says `STENCIL-MOVED` and
// re-encodes.
//
// **`INKDUMP=<dir>` writes the layers out, which is C26 sub-step 4.** Sub-step 3
// priced the bar in bytes; sub-step 4 asks whether those bytes buy anything, and no
// column here can answer that — a page paying 4.54x to keep a drawing and a page of
// plain type paying it for nothing print the same `barDelta`. What separates them is
// the tone layers themselves. Because the stencil is byte-identical at both bars, the
// *whole* difference between what ships and what the bar would ship is in the files
// this writes, so comparing `bg-shipped` against `bg-bar` is comparing exactly what
// the constant changes and nothing else.
//
// ⛔ **PICK THE BAR FROM THE PAGE, NOT FROM THIS HEADER — `INKBAR=0.08` CAN COMPARE A PAGE
// WITH ITSELF.** The two verdicts are `inkOut < shipped && noPaleDrawing` and
// `inkOut < INKBAR && noPaleDrawing`, so a page on the same side of both bars is published
// identically twice: `barVerdict` matches `verdict`, `barDelta` prints `same`, and `INKDUMP`
// writes **byte-identical** tone layers while still reporting "wrote 7 file(s)". Measured
// 2026-08-20 on `Broadhead - 1994` p3 (`inkOut` 0.0450) at `INKBAR=0.08`: `all-text` both
// sides, 284 px vs 284 px, one sha256 for both backgrounds. A reader diffing that pair
// concludes the page loses nothing — on a page that loses two lines of prose.
//
// So `INKBAR=0.08` reaches only pages whose `inkOut` is in **[0.045, 0.08)** — **17 rows of
// the 2,129** in `INKBAR-2026-08-19.tsv` — and then only where `extent <= 0.05` and the
// caller is not at `PhotoDetail.maximum` (`keepEveryPixel` short-circuits the whole rule).
// A page **at or above** 0.08 compares with itself just as one below 0.045 does: 87 sampled
// pages are at or above it and 86 already print `barDelta same`. ⚠️ This paragraph said
// "at or above 0.045" in its first version, which is wrong on 87 pages against 17 right —
// the adversarial review of that diff sized it. For a page *below* the shipped bar (C28's
// 73) the bar must be **at or below that page's own `inkOut`** — and since this column PRINTS four
// places, use a bar strictly below the printed value: a page whose true `inkOut` is 0.01365 prints
// `0.0137`, and `INKBAR=0.0137` would leave it shrunk, which is this warning's own failure mode
// arriving through the rounding. `INKBAR=0.02` covers C28's eight
// near-misses. `BUGS.md` C28 `#### The eight near-misses, RENDERED` is the measurement, and
// this warning is here because the entry's own instrument line said 0.08.
//
// ⛔ **AND THERE IS A FLOOR: A PAGE WHOSE `inkOut` IS 0 CANNOT BE PRICED THROUGH THIS SEAM AT
// ALL.** `pageIsAllText()` compares `inkOutsideText(…) < bar` with a strict `<`, and the guard
// below refuses an `INKBAR` outside `(0, 1)` — correctly, for the reason it gives — so there is
// no legal bar at or below zero. Measured 2026-08-20 over C28's 24-page sub-step: **11 of 24
// pages print `barDelta same` at `INKBAR=0.00001`**, and **27 of the 73** rows this population
// comes from print `inkOut` `0.0000`. ⚠️ The printed value is NOT the test, `barDelta` is:
// `Riesman - 1954` p12 prints `0.0000` and *did* flip, so its true value is in
// [0.00001, 0.00005). ⚠️ Nor can the summary line tell you which tiny bar ran — it formats the
// bar with `%.4f`, so `INKBAR=0.00001` prints as `INKBAR 0.0000 against the shipped 0.0450`.
//
// What reads those pages instead needs no override and no second `mrcLayers` run — just the two
// files this tool already dumps, `-source.png` and `-stencil.png`:
//
//   magick "$s-source.png"  -auto-threshold OTSU -negate ink.png
//   magick "$s-stencil.png" -morphology Erode Disk:3 notsten.png   # dilates the stencil's INK
//   magick ink.png notsten.png -compose Multiply -composite out.png # 0/255 AND, commutative
//
// i.e. ink with no stencil within 3 px, which is the set stored only in the background. The
// dilation is load-bearing: `inkOutsideText` thresholds with a page-wide Otsu while the stencil
// is an adaptive Sauvola mask, so every stencilled glyph leaves a rim. Measured over C28's twelve
// positive-`inkOut` pages the rim is worth **0.97x to 19.4x** the whole of `inkOut` — negligible on
// eight of them, and worst on `Atkinson_1939` p1 (34,158 px at r=0, 15 px at r=3, on a page whose
// `inkOut` is 0.0000), so it is a per-page hazard rather than a constant. Use `Multiply` and not
// `Minus`: `-compose Minus` computes `dst - src` and measures the stencil minus the ink. Both
// mistakes were made and caught here; `BUGS.md` C28's 24-page section has the validation against
// a page with a known loss and a page with none, where the map names the lost words.
//
// ⛔ **AND CROP TO THE INTERIOR BEFORE COUNTING ANYTHING — BOTH IMAGES, WHICH THE RECIPE ABOVE DID
// NOT SAY.** `Flattener.inkOutsideText` walks only x ∈ [w/16, w−w/16) and y ∈ [h/16, h−h/16) and
// divides by *interior* ink, so it never sees a photographed surround, a platen edge or a scanner
// border. The fraction is outside/ink, so cropping only the map understates it — measured, 0.0048
// instead of 0.0087 on `Ford_1941_Speech_` p1, 1.8x in the direction that hides the problem, and the
// first version of this paragraph made exactly that mistake:
//
//   mx=$((w/16)); my=$((h/16)); c="$((w-2*mx))x$((h-2*my))+$mx+$my"
//   magick ink.png -crop "$c" +repage ink-int.png
//   magick out.png -crop "$c" +repage out-int.png
//
// Measured 2026-08-20 over C28's 20-page sub-step 3: uncropped, this map's fraction reads **0.4479**
// on `Ford_1941_Speech_` p1 against an `inkOut` of 0.0051 and **0.8199** on
// `1976 - Regis McKenna Papers` p4 against 0.0287 — and the worst *ratio* is neither, but **256x** on
// `Stanford_1891` p4 (0.0256 against 0.0001). Cropped, the twenty read **0.56x to 16.0x**. Note the
// 0.97x-19.4x band above is NOT void: sub-step 2's figures were already interior, it was only its
// published shell recipe that omitted the crop. Six of the twenty read below 1.0 and the cause is
// **not established** — the erosion, ImageMagick's OTSU against `otsuThreshold(of:)`, and the dumped
// stencil being the Sauvola mask ∧ `region` while the guard tests `region` alone are three candidates
// and none was isolated. ⛔ Either way the number is a locator and not a measure: sorted by the
// cropped fraction those twenty pages' losing and non-losing verdicts interleave, which is the third
// scalar C28 has measured and refused.
//
//   mkdir -p /tmp/h && cp Tools/score-text-route.swift /tmp/h/main.swift
//   swiftc -O -o /tmp/score-text-route -target "$(uname -m)-apple-macos13.0" \
//     $(ls Sources/*.swift | grep -v App.swift) /tmp/h/main.swift
//   /tmp/score-text-route "<pdf>" [page…]        # 1-indexed; default: a spread
//   INKBAR=0.08 /tmp/score-text-route "<pdf>"    # + the priced columns; inkOut in [0.045,0.08)
//   INKBAR=0.08 INKDUMP=/tmp/look /tmp/score-text-route "<pdf>" 4
//   INKBAR=0.02 INKDUMP=/tmp/look /tmp/score-text-route "<pdf>" 3   # a page BELOW the bar
//   (0.045 in both until 2026-08-19, when it became the shipped bar and started
//    exiting 2 — see the ⛔ paragraph above)
//
// Exit codes: 1 unreadable PDF, 2 a refused `INKBAR`/`INKDUMP`, 3 no jbig2,
// **4 an INKDUMP that did not write everything it promised** — the totals are still
// printed and still valid on a 4, because only the dump failed — and 5 a failed
// self-test, which measures nothing. `Tools/sweep-ink-bar.py` treats 2 and 3 as
// configuration aborts and never sets `INKDUMP`, so it cannot see 4.
//
// ⚠️ **5 is NOT in that driver's `CONFIG_EXITS`, and it is systematic, so the driver would
// record 233 identical failure rows rather than aborting** — the exact shape its abort
// exists to prevent. Left as it is deliberately: adding 5 there means moving a constant
// its own `--self-test` asserts (`CONFIG_EXITS == {2, 3}`) plus a mutant, and a 5 can only
// happen if someone breaks the self-test above in the same commit they run a corpus sweep.
// Named rather than fixed, and the remedy is one line if that ever stops being true.
//
// Needs jbig2 on PATH — without it there is no size question to answer, and it
// says so rather than reporting halves.
import AppKit
import CoreGraphics
import Foundation
import PDFKit

let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write(Data("usage: score-text-route <pdf> [page…]\n".utf8))
    exit(2)
}
let src = URL(fileURLWithPath: args[1])
guard let jbig2 = JBIG2.encoder else {
    FileHandle.standardError.write(Data("jbig2 not found; nothing to measure\n".utf8))
    exit(3)
}
Prefs.register(migrate: false)
let settings = Prefs.Snapshot.current()

let work = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("textroute-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }

guard let doc = PDFDocument(url: src), doc.pageCount > 0 else {
    FileHandle.standardError.write(Data("cannot open \(src.path)\n".utf8))
    exit(1)
}
let requested = args.dropFirst(2).compactMap { Int($0) }
// One-based, because `isolate` takes a page *number*. `sampleIndices` is the
// app's own stride and does not repeat; the expression here used to be
// `(1...min(12, n)).map { $0 * n / 13 }.filter { $0 > 0 }`, which at n=5 is
// [1, 1, 1] — **page 1 measured three times and pages 2 to 5 not at all**, in a
// tool whose whole output is per-page byte counts and their averages. 27 of 233
// corpus documents are short enough to land in that (A12.8).
let pages: [Int] = requested.isEmpty
    ? Flattener.sampleIndices(count: doc.pageCount, wanted: 12).map { $0 + 1 }
    : requested

func bytes(_ url: URL) -> Int { (try? Data(contentsOf: url).count) ?? 0 }

/// One page, alone in its own PDF, because both routes below take a document.
func isolate(_ index: Int) -> URL? {
    guard let page = doc.page(at: index - 1) else { return nil }
    let one = PDFDocument()
    one.insert(page, at: 0)
    let url = work.appendingPathComponent("p\(index).pdf")
    return one.write(to: url) ? url : nil
}

/// C26 sub-step 3. A second bar on `inkOutsideText` to price, or `nil` for none.
///
/// An environment variable rather than an argument, because the trailing arguments
/// are already page numbers and a sweep driver sets it once for a whole corpus.
/// Refused loudly outside `(0, 1)`: that range is what a *fraction of the page's
/// ink* can be, and a typo like `INKBAR=45` would otherwise price a bar no page can
/// fail, print `same` on every row, and read as "the change costs nothing".
let priceBar: Double? = {
    guard let raw = ProcessInfo.processInfo.environment["INKBAR"], !raw.isEmpty
    else { return nil }
    guard let bar = Double(raw), bar > 0, bar < 1 else {
        FileHandle.standardError.write(Data(
            "INKBAR=\(raw) is not a fraction in (0,1); nothing to price\n".utf8))
        exit(2)
    }
    if bar == Flattener.textPageInkOutsideThreshold {
        FileHandle.standardError.write(Data(
            "INKBAR equals the shipped bar, so there is nothing to compare\n".utf8))
        exit(2)
    }
    return bar
}()

/// C26 sub-step 4. Where to write the layers this run publishes, or `nil` for none.
///
/// An environment variable for the same reason `INKBAR` is one, and here the reason is
/// sharper than convention: every trailing argument is a page number and `requested` is
/// `compactMap { Int($0) }`, so a `--dump` flag would be **silently swallowed** by the
/// page parser. The tool would accept it, write nothing, and print a clean run — which
/// is precisely the failure `score-threshold-loss`'s `dumpFailures` list exists for,
/// arriving through the argument parser instead of through the writer.
///
/// Refused loudly rather than created quietly on a bad path: a dump is evidence, and an
/// empty directory reads as "there was nothing on those pages", which would settle
/// C26's remaining question the wrong way round. (That question was answered on
/// 2026-08-20 by this very mode and C26 is `FIXED`. The refusal stays: the same trap
/// applies to every dump `C28` will want.)
let dumpDirectory: URL? = {
    guard let raw = ProcessInfo.processInfo.environment["INKDUMP"], !raw.isEmpty
    else { return nil }
    let url = URL(fileURLWithPath: raw, isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    } catch {
        FileHandle.standardError.write(Data(
            "INKDUMP=\(raw) cannot be created: \(error.localizedDescription)\n".utf8))
        exit(2)
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        FileHandle.standardError.write(Data("INKDUMP=\(raw) is not a directory\n".utf8))
        exit(2)
    }
    return url
}()

/// How many pages `INKDUMP` wrote in full, and how many promised files never reached
/// disk. Both are needed: `dumpMissing == 0` over `dumpedPages == 0` is the silent
/// failure, and it looks identical to success from inside the loop.
/// …and how many pages ever REACHED the dump, which is the third thing and the one the
/// first version of this block left out. Five `continue`s sit above the dump — already
/// 1-bit, an A12.2 DPI drift, a failed render, a failed isolation — so
/// `INKDUMP … doc.pdf 3` over a 1-bit page 3 is a run with **nothing to dump**, and
/// without this counter it was indistinguishable from a broken writer: it printed a
/// correct row and then "INKDUMP wrote NOTHING, read that as an instrument failure",
/// which is the exact inversion of the distinction this accounting exists for. Caught by
/// the adversarial review of this diff, which also noted that `score-mrc`'s sibling fix in
/// the same commit had the qualifier (`dumped == 0 && layered > 0`) and this did not.
var dumpedPages = 0, dumpMissing = 0, dumpablePages = 0

/// The exit status a finished run deserves, as a function of its four inputs and
/// nothing else.
///
/// Pulled out of `finish()` so it can be asserted rather than reasoned about. Ten checks
/// in this register could not fail, and the shape they share is a verdict computed inline
/// where nothing can call it — so the enumeration below is CONTRIBUTING 4d's
/// states-by-doors table at its smallest: every combination of "was a dump asked for",
/// "did any page write in full" and "did any promised file go missing", including the
/// inverse rows where no dump was asked for and the answer must be 0 whatever the
/// counters say.
func dumpExitCode(asked: Bool, dumpable: Int, wrote: Int, missing: Int) -> Int32 {
    guard asked else { return 0 }
    return (missing > 0 || (dumpable > 0 && wrote == 0)) ? 4 : 0
}

// Runs on every invocation, `score-mrc` and `score-threshold-loss`'s pattern. Cheap
// enough to be unconditional, and the point of it is the FOURTH row: a run that wrote
// nothing and lost nothing is the silent failure, and it is the one a reader would
// mistake for "there was nothing on those pages".
for (asked, dumpable, wrote, missing, want) in [
    (false, 0, 0, 0, Int32(0)),   // no dump asked for: 0
    (false, 3, 0, 9, Int32(0)),   // …even if the counters are somehow non-zero
    (false, 3, 3, 0, Int32(0)),   // …and with a full dump's counters, still 0
    (true, 3, 3, 0, Int32(0)),    // three dumpable, three written, nothing lost: 0
    (true, 3, 0, 0, Int32(4)),    // ⚠️ THE SILENT ONE: pages to dump, none written
    (true, 0, 0, 0, Int32(0)),    // ⚠️ AND ITS TWIN: nothing to dump, so 0 is the answer
    (true, 0, 0, 6, Int32(4)),    // files went missing even with no dumpable page: 4
    (true, 3, 2, 1, Int32(4)),    // partial across pages: still 4
] where dumpExitCode(asked: asked, dumpable: dumpable, wrote: wrote, missing: missing) != want {
    FileHandle.standardError.write(Data(
        ("score-text-route: self-test failed on (asked: \(asked), dumpable: \(dumpable), "
         + "wrote: \(wrote), missing: \(missing)) — wanted \(want), got "
         + "\(dumpExitCode(asked: asked, dumpable: dumpable, wrote: wrote, missing: missing)); "
         + "measuring nothing\n").utf8))
    exit(5)
}

/// Exit, carrying an incomplete dump in the status. Two `exit`s below reach the end of
/// the run — the "no picture-route pages measured" guard and the normal fall-through —
/// and a dump failure has to survive both. The totals are printed either way, because
/// they are unaffected by whether the images were written.
/// ⚠️ It also removes `work`, and that is not housekeeping. The top-level `defer` below
/// only runs when this file falls off its own end; before this function existed, the
/// normal path *did* fall off the end, so routing it through `exit` would silently start
/// leaking a scratch directory holding up to twelve pages of renders and layers on every
/// run. `score-mrc.swift`'s `stop` carries the same note and the same reason.
func finish() -> Never {
    let silent = dumpDirectory != nil && dumpablePages > 0 && dumpedPages == 0
    if dumpDirectory != nil {
        print("INKDUMP: \(dumpedPages) page(s) written in full of \(dumpablePages) that "
              + "reached the dump, \(dumpMissing) promised file(s) missing")
        if dumpablePages == 0 {
            print("  no page reached the layering decision, so there was nothing to dump — "
                  + "an empty answer, not an instrument failure")
        }
        if silent {
            print("  ⚠️ INKDUMP wrote NOTHING. Read that as an instrument failure, not "
                  + "as an empty answer about these pages.")
        }
    }
    try? FileManager.default.removeItem(at: work)
    exit(dumpExitCode(asked: dumpDirectory != nil, dumpable: dumpablePages,
                      wrote: dumpedPages, missing: dumpMissing))
}

/// The one printer, and the thirteen columns in one place.
///
/// Every row came out of its own `print` before, and two of the four were the wrong
/// width: the `already 1-bit` row printed **10** fields under this 9-column header
/// and the `encode failed` row printed **3**, so `verdict` landed under `drift` on
/// one and under `sat` on the other. A comment beside the third row reasoned the
/// dash count out ("eight dashes, not nine" — there are seven) and got the row
/// right, which is the argument for not counting dashes at all. Third instance of
/// this shape in the register: T14's SKIP row, A12.3's `score-mrc`, this.
///
/// The last four are C26's. `extent` is `paleDrawing(…).extent`, the guard's *second*
/// term, printed so a row that does not move can be read for which term held it;
/// `barVerdict`, `layeredAtBar` and `barDelta` are `-` unless `INKBAR` is set.
let columns = ["page", "route", "sat", "tone", "inkOut", "layered", "1bit",
               "delta", "verdict", "extent", "barVerdict", "layeredAtBar", "barDelta"]
func row(_ page: Int, _ route: String = "-", sat: String = "-", tone: String = "-",
         inkOut: String = "-", layered: String = "-", bilevel: String = "-",
         delta: String = "-", verdict: String, extent: String = "-",
         barVerdict: String = "-", layeredAtBar: String = "-", barDelta: String = "-") {
    let fields = ["p\(page)", route, sat, tone, inkOut, layered, bilevel, delta,
                  verdict.replacingOccurrences(of: "\t", with: " "),
                  extent, barVerdict, layeredAtBar, barDelta]
    precondition(fields.count == columns.count)
    print(fields.joined(separator: "\t"))
}

print(columns.joined(separator: "\t"))
var totalLayered = 0, totalBilevel = 0, counted = 0
var allTextLayered = 0, allTextBilevel = 0, allTextPages = 0
// C26. Pages the priced bar moves off the shrink, and what it costs to move them.
// `comparedPages` is counted so the summary cannot report a property of a comparison
// that never ran — `score-corpus`'s `SKIP` row and `score-threshold-loss`'s exit 3 are
// both this lesson.
var movedPages = 0, movedShipped = 0, movedAtBar = 0
var stencilMoved = 0, comparedPages = 0, replicaDisagreed = 0

for index in pages {
    guard let single = isolate(index), let page = doc.page(at: index - 1) else { continue }

    // A12.2. Isolating the page can change the resolution the rebuild renders it
    // at — `largestImage` walks a `/Resources` that 4 of 208 multi-page corpus
    // documents share across every page, so the whole file and the extract answer
    // differently. This tool is *cited* as pricing TODO item 1 at 8.2 KB a page —
    // cited rather than responsible, because C25 records that no committed version of
    // this file has ever compiled — and a row measured at the wrong resolution would
    // not be that page's price either. qpdf --pages does
    // not help; `BUGS.md` C24 records why the app-side repair has no threshold to
    // stand on.
    if let isolated = PDFDocument(url: single)?.page(at: 0) {
        let before = Flattener.rebuildDPI(of: page)
        let after = Flattener.rebuildDPI(of: isolated)
        if abs(before - after) > 0.5 {
            row(index, verdict: String(format:
                "SKIP isolation moved the rebuild DPI %.0f->%.0f (A12.2)",
                before, after))
            continue
        }
    }

    // --- what the app does today, at this page's own routing decision ---
    let autoDir = work.appendingPathComponent("auto\(index)")
    try? FileManager.default.createDirectory(at: autoDir, withIntermediateDirectories: true)
    guard let auto = try? Flattener.flatten(single, to: work.appendingPathComponent("a\(index).pdf"),
                                            mode: .auto, pngDirectory: autoDir),
          let first = auto.first else { continue }
    let route: String
    var isColour = false
    switch first.content {
    case .bilevel: route = "bilevel"
    case .jpeg: route = first.isColour ? "colour" : "grey"; isColour = first.isColour
    }
    // A page already on the 1-bit route is not what this is about.
    guard case .jpeg(let jpegURL) = first.content else {
        row(index, route, verdict: "already 1-bit")
        continue
    }

    // --- the signals, and the boxes a post-recognition decision would use ---
    let box = Flattener.fullBox(of: page)
    let dpi = Flattener.rebuildDPI(of: page)
    let scale = dpi / 72.0
    let w = max(Int((box.width * scale).rounded()), 1)
    let h = max(Int((box.height * scale).rounded()), 1)
    guard let grey = Flattener.renderGrey(page, box: box, scale: scale,
                                          width: w, height: h, from: .mediaBox) else { continue }
    let threshold = Flattener.otsuThreshold(of: grey)
    let tone = Flattener.toneFraction(of: grey, threshold: threshold)
    let sat = Flattener.saturation(of: page)

    // Recognise the bitmap the app publishes, not a re-render of the page: the
    // whole point of R40 is that those are the same pixels.
    var boxes: [SearchableWriter.BoundingBox] = []
    if let source = CGImageSourceCreateWithURL(jpegURL as CFURL, nil),
       let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
       let observations = try? Recogniser.recognise(image, settings: settings) {
        boxes = observations.map { $0.boundingBox }
    }
    let region = Flattener.textRegionMask(boxes, width: w, height: h)
    let inkOut = Flattener.inkOutsideText(grey, region: region, width: w, height: h,
                                          threshold: threshold)
    // `Flattener.toneOutsideText` was printed in a `toneOut` column here and
    // **has never existed in any commit of this repository** — `git log -S` over
    // all history finds it in this file and nowhere else. So this tool has not
    // compiled since the line was added, in the R56/R57 commit, while its own
    // header carries the build command that fails and three documents cite it as
    // the way to re-measure. See `BUGS.md` C25.
    //
    // Removed rather than implemented: the tool's stated principle is that it
    // drives shipped code so it cannot drift, and there is no shipped signal for
    // continuous tone outside the recognised words. Adding one to `Flattener` for
    // a tool's benefit would put dead code on the app's side, which is the call
    // `score-skew` and `score-threshold-loss` both already record.
    // **Both** of `pageIsAllText()`'s terms, not just the first. This read
    // `inkOut < textPageInkOutsideThreshold` alone until 2026-08-18, which is a
    // replica of a shipped guard missing a clause — CONTRIBUTING 4b's shape, found
    // by C26's sibling sweep. R56 added the second term precisely so a page carrying
    // a pale drawing is *not* shrunk, so a tool that omits it prints `all-text` over
    // exactly the pages R56 exists to protect. Measured on `1954 - Why.pdf` p4/p6/p7
    // the verdict does not move — `extent` is 0.00000 there, which is C26.
    //
    // ⚠️ **That is one document, and `allText` is not only the `verdict` column** — it
    // also gates the `allTextLayered`/`allTextBilevel`/`allTextPages` aggregate and the
    // summary line, which `Tools/README.md` records as the source of the figure that
    // prices TODO item 1. Any page with `inkOut` under the bar *and* `extent` over
    // `paleDrawingThreshold` now leaves that aggregate;
    // `THRESHOLD-LOSS-2026-08-18.tsv` has 2 such pages in 61 picture-route rows, and
    // what that does to the corpus figure is not measured. Found by the review of this
    // diff, which was right that "no number moves" was a claim about one document.
    //
    // The third condition, `keepEveryPixel`, is deliberately not mirrored: it belongs
    // to the caller's Photo detail, and this tool measures the default.
    //
    // `extent` is hoisted to a `let` because C26's priced bar needs the same value
    // for both verdicts. Only the first term moves with `INKBAR`, so computing the
    // second twice would be two chances to disagree about one page.
    let extent = Flattener.paleDrawing(Flattener.pageMarks(grey, width: w, height: h,
                                                           threshold: threshold, dpi: dpi),
                                       dpi: dpi).extent
    let noPaleDrawing = extent <= Flattener.paleDrawingThreshold
    let allText = inkOut < Flattener.textPageInkOutsideThreshold && noPaleDrawing
    // C26. The same page against the bar being priced. A *lower* bar can only take
    // pages off the shrink, but the sign is not assumed: `INKBAR` above the shipped
    // value is legal and prices the other direction.
    let allTextAtBar = priceBar.map { inkOut < $0 && noPaleDrawing }

    // --- layered, exactly as it ships ---
    var layered = 0, stencilBytes = 0, shippedBackgroundWidth = 0
    var shippedMask: Data?
    // Held for `INKDUMP` below. The struct is three URLs and four dimensions, so
    // keeping it costs nothing and reading the files back out of `work` after the loop
    // body would be reading paths this tool composed by hand rather than the ones
    // `mrcLayers` returned.
    var shippedLayers: Flattener.MRCLayers?
    if !boxes.isEmpty,
       let layers = Flattener.mrcLayers(for: page, boxes: boxes, into: work,
                                       stem: "m\(index)", inColour: isColour) {
        // Assigned OUTSIDE the encode guard, deliberately: an external `jbig2` failing has
        // nothing to do with whether `mrcLayers` wrote its three files, and inside the guard
        // a failed encode collapsed the dump to one grey PNG while still reporting "written
        // in full". Found by the adversarial review of this diff.
        shippedLayers = layers
        let stencil = work.appendingPathComponent("m\(index).jbig2")
        if (try? JBIG2.encode(png: layers.mask, to: stencil, using: jbig2)) != nil {
            stencilBytes = bytes(stencil)
            layered = stencilBytes + bytes(layers.background) + bytes(layers.foreground)
            shippedMask = try? Data(contentsOf: layers.mask)
            shippedBackgroundWidth = layers.backgroundWidth
        }
    }
    // Layering declining is a real answer: the page keeps its single JPEG.
    if layered == 0 { layered = bytes(jpegURL) }

    // --- C26: layered again, with the priced bar substituted for the shipped one ---
    //
    // Same call, same page, one property different, so the two numbers cannot come
    // from two pieces of code that drifted — T15 is what a second copy of shipped
    // arithmetic costs. The override is cleared immediately after, not at the end of
    // the loop: a `continue` further down would otherwise leak it into the next page.
    //
    // `barBackgroundWidth` is **production's** verdict rather than this file's replica
    // of the guard, and the two are cross-checked below. The replica is still needed
    // for the `barVerdict` column on a page that never layered, but a tool deciding a
    // routing question by a second copy of a shipped guard is what this same commit
    // repaired in `allText` — see `BUGS.md` C26's sibling sweep. It is also the
    // tripwire for a *dead* seam: if the replica says three pages should move and
    // production's widths never budge, the override is not being read and every
    // `barDelta` would otherwise print `same`, which reads as "the change is free".
    var layeredAtBar = 0, movedStencil = false
    var barBackgroundWidth = 0
    var barLayers: Flattener.MRCLayers?
    if let bar = priceBar, stencilBytes > 0 {
        Flattener.textPageInkOutsideThresholdOverride = bar
        if let layers = Flattener.mrcLayers(for: page, boxes: boxes, into: work,
                                           stem: "mb\(index)", inColour: isColour) {
            barBackgroundWidth = layers.backgroundWidth
            barLayers = layers
            var barStencil = stencilBytes
            // The stencil reads no downsample factor, so it should be the same bytes.
            // Checked rather than assumed, and if it ever moves the row says so and
            // pays for a real encode instead of quietly reusing the wrong number.
            if (try? Data(contentsOf: layers.mask)) != shippedMask {
                movedStencil = true
                let s = work.appendingPathComponent("mb\(index).jbig2")
                barStencil = (try? JBIG2.encode(png: layers.mask, to: s, using: jbig2)) != nil
                    ? bytes(s) : 0
            }
            if barStencil > 0 {
                layeredAtBar = barStencil + bytes(layers.background) + bytes(layers.foreground)
            }
        }
        Flattener.textPageInkOutsideThresholdOverride = nil
    }

    // --- C26 sub-step 4: the layers themselves, for a reader rather than a total ---
    //
    // Placed here, immediately after the override is cleared and before the 1-bit
    // route's own `continue`, for the same reason the clear is: a page that fails to
    // encode further down must still have written its evidence, because the bytes are
    // not what this mode is for.
    //
    // The promise is built from what actually got built, not from a fixed list of six
    // names. A page the tool declined to layer has no tone layers to write, and
    // promising them would make that page indistinguishable from a dump that silently
    // failed — which is the one distinction this accounting exists to keep.
    if let dump = dumpDirectory {
        dumpablePages += 1
        // ⚠️ The document's own name is in every filename, and it was NOT in the first
        // version. Among C26's 13 pages `p1` occurs twice and `p8` occurs twice, so nine
        // invocations sharing one `<dir>` — which is what this entry's own re-derivation
        // recipe says to do — silently overwrote two pairs while counting both and exiting
        // 0. Evidence lost while reporting success, in the mode added to stop exactly that.
        // `score-mrc`'s `MRC_DUMP` already prefixed its label; caught by the adversarial
        // review of this diff.
        let stem = "\(src.deletingPathExtension().lastPathComponent.prefix(40))-p\(index)"
        var promised: [(String, () -> Data?)] = [
            ("\(stem)-source.png", { Flattener.greyPNG(grey, width: w, height: h) })
        ]
        if let s = shippedLayers {
            promised += [
                ("\(stem)-bg-shipped.jpg", { try? Data(contentsOf: s.background) }),
                ("\(stem)-fg-shipped.jpg", { try? Data(contentsOf: s.foreground) }),
                ("\(stem)-stencil.png", { try? Data(contentsOf: s.mask) }),
            ]
        }
        if let b = barLayers {
            promised += [
                ("\(stem)-bg-bar.jpg", { try? Data(contentsOf: b.background) }),
                ("\(stem)-fg-bar.jpg", { try? Data(contentsOf: b.foreground) }),
                // The bar's stencil too, so a reader can check this entry's central premise
                // — that the stencil is byte-identical at both bars — from the dump instead
                // of taking the tool's word for it. The first version dumped only the
                // shipped one, which asks to be believed.
                ("\(stem)-stencil-bar.png", { try? Data(contentsOf: b.mask) }),
            ]
        }
        var missing: [String] = []
        for (name, produce) in promised {
            guard let data = produce(), !data.isEmpty,
                  (try? data.write(to: dump.appendingPathComponent(name))) != nil
            else { missing.append(name); continue }
        }
        // Per page on stderr rather than in a column: the row is a TSV a driver parses,
        // and the dump is a thing a person is about to look at. The two background
        // widths go with it because they are what makes the pair worth comparing — equal
        // widths mean the bar did not move this page and the two images are the same
        // picture.
        let note = missing.isEmpty
            ? "wrote \(promised.count) file(s)"
            : "wrote \(promised.count - missing.count) of \(promised.count) file(s), "
              + "MISSING \(missing.joined(separator: " "))"
        FileHandle.standardError.write(Data(
            ("INKDUMP p\(index): \(note); background \(shippedBackgroundWidth)px shipped"
             + " vs \(barBackgroundWidth)px at the bar\n").utf8))
        if missing.isEmpty { dumpedPages += 1 } else { dumpMissing += missing.count }
    }

    // --- 1-bit, via the shipped Black & white route ---
    let bwDir = work.appendingPathComponent("bw\(index)")
    try? FileManager.default.createDirectory(at: bwDir, withIntermediateDirectories: true)
    var bilevel = 0
    if let bw = try? Flattener.flatten(single, to: work.appendingPathComponent("b\(index).pdf"),
                                       mode: .blackAndWhite, pngDirectory: bwDir),
       case .bilevel(let png)? = bw.first?.content {
        let stream = work.appendingPathComponent("b\(index).jbig2")
        if (try? JBIG2.encode(png: png, to: stream, using: jbig2)) != nil {
            bilevel = bytes(stream)
        }
    }
    guard layered > 0, bilevel > 0 else {
        row(index, route, sat: String(format: "%.3f", sat),
            tone: String(format: "%.3f", tone),
            inkOut: String(format: "%.4f", inkOut),
            verdict: "FAIL encode failed")
        continue
    }

    totalLayered += layered; totalBilevel += bilevel; counted += 1
    if allText { allTextLayered += layered; allTextBilevel += bilevel; allTextPages += 1 }
    // C26. A page whose verdict does not move is a measured `same`, not an assumed
    // one: `layeredAtBar` is a second run of `mrcLayers` either way, so an equal pair
    // of byte counts is this row's own negative control on the seam.
    var barVerdict = "-", barBytes = "-", barDelta = "-"
    if let moved = allTextAtBar {
        barVerdict = moved ? "all-text" : "picture"
        if movedStencil { stencilMoved += 1; barVerdict += " STENCIL-MOVED" }
        if layeredAtBar > 0 {
            comparedPages += 1
            // Production's own answer, not the replica's: the two factors differ, so a
            // page whose verdict moved must come back a different width. A row where
            // the replica and the layers disagree is either a dead seam or a term this
            // file does not mirror (`keepEveryPixel`, the megapixel caps), and it is
            // named rather than averaged into the total.
            let widthMoved = barBackgroundWidth != shippedBackgroundWidth
            if widthMoved != (moved != allText) {
                barVerdict += " REPLICA-DISAGREES"
                replicaDisagreed += 1
            }
            barBytes = "\(layeredAtBar)"
            barDelta = layeredAtBar == layered ? "same"
                : String(format: "%+d", layeredAtBar - layered)
            if moved != allText {
                movedPages += 1; movedShipped += layered; movedAtBar += layeredAtBar
            }
        } else if stencilBytes == 0 {
            // The page was never layered at all — no words, or the shipped stencil
            // failed to encode — so there is no priced counterfactual to have. A real
            // answer, and deliberately NOT the same token as an instrument failure: a
            // `grep FAIL` over a corpus log must not conflate the two.
            barBytes = "n/a"; barDelta = "n/a"
        } else {
            barBytes = "FAIL"
        }
    }
    row(index, route, sat: String(format: "%.3f", sat),
        tone: String(format: "%.3f", tone),
        inkOut: String(format: "%.4f", inkOut),
        layered: "\(layered)", bilevel: "\(bilevel)",
        delta: String(format: "%+d", bilevel - layered),
        verdict: allText ? "all-text" : "picture",
        extent: String(format: "%.5f", extent),
        barVerdict: barVerdict, layeredAtBar: barBytes, barDelta: barDelta)
}

print("")
guard counted > 0 else { print("no picture-route pages measured"); finish() }
print("\(counted) picture-route pages: layered \(totalLayered) B, 1-bit \(totalBilevel) B, "
      + String(format: "delta %+d B (%.0f B/page)",
               totalBilevel - totalLayered,
               Double(totalBilevel - totalLayered) / Double(counted)))
if allTextPages > 0 {
    print("\(allTextPages) of them read all-text: layered \(allTextLayered) B, "
          + "1-bit \(allTextBilevel) B, "
          + String(format: "delta %+d B (%.0f B/page)",
                   allTextBilevel - allTextLayered,
                   Double(allTextBilevel - allTextLayered) / Double(allTextPages)))
    print("negative delta = 1-bit is smaller = the prize; positive = the route it "
          + "already takes is cheaper")
}
// C26 sub-step 3's answer, in the two numbers that entry was blocked on: how many
// pages a bar moves, and what moving them costs. (Both were measured 2026-08-19 and
// C26 is `FIXED` 2026-08-20; the columns stay — `C28` asks the same two questions of
// a different mechanism.)
if let bar = priceBar {
    print(String(format: "INKBAR %.4f against the shipped %.4f: %d of %d picture-route "
                 + "pages change verdict", bar, Flattener.textPageInkOutsideThreshold,
                 movedPages, counted))
    if movedPages > 0 {
        print("  those pages: \(movedShipped) B shipped, \(movedAtBar) B at the bar, "
              + String(format: "%+d B (%.0f B/page, %.2fx)", movedAtBar - movedShipped,
                       Double(movedAtBar - movedShipped) / Double(movedPages),
                       Double(movedAtBar) / Double(max(movedShipped, 1))))
    }
    // ⚠️ Both of the next two lines are about a comparison that may not have happened,
    // so `comparedPages` gates them. "The stencil was byte-identical on every page"
    // over zero pages is a success report on a measurement never made, which is the
    // shape `score-corpus`'s `SKIP` row and `score-threshold-loss`'s exit 3 exist for.
    if comparedPages == 0 {
        print("  ⚠️ NO page was priced: nothing was layered twice, so this run says "
              + "nothing about the bar")
    } else {
        print(stencilMoved == 0
              ? "  the stencil was byte-identical on all \(comparedPages) priced page(s), "
                + "as it must be"
              : "  ⚠️ the stencil moved with the bar on \(stencilMoved) of \(comparedPages) "
                + "priced page(s) and was re-encoded")
        // The seam's own tripwire. A dead override prints `same` on every row and "0
        // pages change verdict", which reads as "the change is free" rather than as a
        // broken instrument — the exact misreading the `INKBAR` range guard above
        // exists to prevent, arriving by a different door.
        if replicaDisagreed > 0 {
            print("  ⚠️ this file's replica of the guard and the widths `mrcLayers` "
                  + "returned disagree on \(replicaDisagreed) of \(comparedPages) priced "
                  + "page(s) — suspect a dead override or an unmirrored term before "
                  + "reading any total above")
        }
    }
}
finish()
