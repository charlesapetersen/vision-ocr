// C24, closed: what does each page **draw**, against what its `/Resources` reaches?
//
// `Flattener.largestImage` walks the page's resource dictionary, and 4 of the corpus's 208
// multi-page documents share one dictionary across every page. The structural half closed
// on 2026-08-16 — a page that invokes no XObject at all now has no image — and **45 pages
// invoked a *different* image than the shared dictionary holds**, so they took a neighbour's
// plate resolution. This tool is what measured them: **39 smaller and 6 wider**, and the
// entry's word for all 45 was "smaller". See the `wider` note below.
//
// **The wiring landed on 2026-08-17 and this tool is the gate that measured it.**
// `Flattener.rebuildDPI(of:)` now applies the shipped policy to `drawnLargestImage`, so
// `dictRebuildDPI` below is what production did *before* that commit and `shippedRebuildDPI`
// is what it does now. `policyMoves` is therefore a before/after diff in one sweep, and over
// the corpus it reads `moves` on exactly the 45 and `same` on the other 16,942. Two things
// follow for a reader:
//
//   * `dictRebuildDPI` is `rebuildDPI(from: largestImage(of:))` — the old body verbatim, not
//     a re-derivation. This column used to hold `rebuildDPI(of:)`, which was the same thing
//     until the wiring landed and would have become a copy of `drawnRebuildDPI` after it: a
//     tool comparing production against itself, printing `same` on all 16,987 rows and
//     reading as "the wiring changed nothing".
//   * the anchor is `DRAWN-2026-08-16.tsv`, produced by the *old* production path before the
//     change existed. Its `shippedRebuildDPI` column equals this one's `dictRebuildDPI` on
//     every row it holds, which is what makes the diff a measurement rather than this tool
//     agreeing with itself.
//
// Restricting the walk to the invoked names is structural and needs no threshold, which is
// why `Flattener.drawnLargestImage` exists. This header said it needed a constant
// recalibrated first: `minimumScanPixelWidth = 600` separated 47 logos of 16–96 px from 37
// page-sized scans of 1936–2592 px, measured against each document's **maximum**, and C24's
// first repair sent `Batzell` p22 from 369.6 DPI to **70.6** because that page's own figure
// is 600 px wide. It then said "rendering a page of type at 70 DPI is C9 again", **which was
// reasoned and is measured false** — `Tools/score-rebuild-dpi.swift`, C24 2026-08-17: p22 at
// 70.6 DPI retains 92.8% of its own words against 94.2% at 369.6, and the constant judges
// all three of the pages it faces correctly. No recalibration was wanted.
//
// One row per page, no rendering and no OCR, so it is metadata-speed. The policy applied to
// both measurements is `Flattener.rebuildDPI(from:)` itself — the shipped three branches,
// not a copy of them, because T15 is what a drifting copy costs.
//
//   mkdir -p /tmp/d && cp Tools/score-drawn-images.swift /tmp/d/main.swift
//   swiftc -O -o /tmp/drawn -target "$(uname -m)-apple-macos13.0" \
//     $(ls Sources/*.swift | grep -v App.swift) /tmp/d/main.swift
//   /tmp/drawn testdocs/*/*.pdf > drawn.tsv
//
// Rows stream in **input order**, one document at a time, because the census's own diff
// recipe was wrong for exactly the opposite reason: it streamed in completion order while
// its header claimed input order, and the `diff` it prescribed reported 5,370 changed lines
// over 210 changed pages. Nothing here is concurrent, so the order is the argument order.
//
// The interesting query is the last column:
//
//   awk -F'\t' 'NR>1 && $12!="agree"' drawn.tsv | cut -f12 | sort | uniq -c
//   awk -F'\t' 'NR>1 && $12=="smaller"' drawn.tsv          # the population C24 moved
//
// and the wiring's own gate is column 11 against the dated record that predates it:
//
//   awk -F'\t' 'NR>1 && $11=="moves"' drawn.tsv | wc -l    # expect 45
//   awk -F'\t' 'NR>1 {print $1"\t"$2"\t"$6}' drawn.tsv     # must match DRAWN-2026-08-16's $6
//
// `minimumScanPixelWidth` is consulted on every page whose drawn DPI falls below
// `minimumPlausibleScanDPI` — **820 of the corpus's 16,987**, measured 2026-08-17, so this
// query is not the small one an earlier draft of this comment assumed:
//
//   awk -F'\t' 'NR>1 && $9!="-" && $9+0 < 150' drawn.tsv | cut -f1,2,8,9    # 820 pages
//
// The three the *wiring* put in front of it are that query narrowed to the rows that move —
// `Batzell` p9 and p22 and `AI 2027` p1, and C24 renders all three both ways:
//
//   awk -F'\t' 'NR>1 && $11=="moves" && $9!="-" && $9+0 < 150' drawn.tsv    # 3 pages
//
// ── The form-nesting census, added 2026-08-26 for the queue's `bare-form-reach` ─────────
//
// The two walks have **unequal reach**, and it is bare forms rather than the caps. A Form
// XObject carrying no `/Resources` of its own resolves its names in the scope that invoked
// it, so `largestImage` does not descend it and loses nothing — the image is listed in the
// dictionary it is already scanning — while `drawnLargestImage` must follow the `Do` and
// spends a level on every form it enters, bare or not. Each bare form therefore narrows the
// drawn walk alone. C24 `#### The two caps, and the chain they are equal on` measured it on
// page 14 of `shared-resources.pdf`: four bare levels, `largestImage` answers 1800 px, the
// drawn walk answers `.noImage`, and `rebuildDPI` routes `.noImage` to the 300 fallback
// rather than to `largestImage` — so a resolution that WAS read is discarded.
//
// The queue asked for a measurement and not a fix, and the last three columns are it. They
// count **structure**, not an answer: how deep the page's `Do` chains actually go and how
// many of the forms in them are bare, with **no cap at either 3 or 4**, so the shape both
// shipped caps are blind to is visible.
//
//   * `formDepth`  the greatest number of forms entered along any one chain.
//   * `bareDepth`  the greatest number of BARE forms along any one chain.
//   * `nestVerdict` the reach consequence, from the arithmetic in `nestVerdict(_:)`.
//
// The arithmetic, which is the whole of the claim. An image drawn inside a chain of `n`
// forms of which `b` are bare is listed in the innermost resource-carrying scope, whose
// dictionary depth is `r = n - b`. The dictionary walk scans dictionaries at depth 0…3, so
// it reaches the image iff `r <= 3`; the drawn walk enters at most three forms, so it
// reaches it iff `n <= 3`. So `n >= 4 AND n - b <= 3` is **sufficient** for divergence, which
// needs `b >= 1`, and page 14's `n = 4, b = 4` is its smallest all-bare instance. The
// fixture's pages 11 and 13 are the negative controls the same arithmetic predicts:
// `n = 4, b = 0`, so `r = 4` and NEITHER walk reaches — that is `bothBlind`, and it costs
// nothing because the policy falls back either way.
//
// ⛔ **`r = n - b` IS AN UPPER BOUND ON THE DICTIONARY DEPTH, NOT THE DEPTH — so the rule is
// SUFFICIENT and not "exactly", and `bothBlind` can be a FALSE NEGATIVE.** A
// resource-carrying form deepens `largestImage`'s walk only if its `/Resources` is a
// dictionary that walk has not already scanned at a shallower depth, and `Flattener.swift`
// says in terms that *"a form's /Resources is frequently an indirect reference to the page's
// own, and forms on one page routinely share a single dictionary"* — its `walkedAt` memo then
// makes that level a no-op. Worked case: page resources `R` list `/F1…/F4` and `/Im`, each
// `Fi` carries `/Resources R`, and `F1` draws `F2` … `F4` draws `Im`. The census reads
// `n = 4, b = 0, r = 4` and says `bothBlind`; `largestImage` finds `Im` at depth **0** and
// answers; the drawn walk is refused at the fourth form. That is a real divergence filed as
// "nothing lost". Direction matters: `diverges` has **no false positives** (`r <= 3` implies
// the true depth is `<= 3`), and the false negatives are all in `bothBlind`, which is the
// unsafe direction. The `diverges && dict == nil` guard below cannot see it — the failure
// mode is `bothBlind && dict != nil`, which is unguardable because a `bothBlind` page may
// legitimately hold a shallow image. ⚠️ Untested: fixture p5 is the only `r = 4` page and it
// uses four DISTINCT freshly-built resource dictionaries, so the shared-`/Resources` shape
// has no fixture. It does not touch the 2026-08-26 corpus result — `formDepth` max is 1
// there, so `n >= 4` is unreachable and both verdicts are 0 either way. Found by the
// adversarial review of the diff that adopted this census.
//
// ⚠️ **This is a second implementation of the traversal, not a call into production's.**
// Neither shipped walk exposes its depths, and adding an accessor to `Flattener` for an
// instrument is a seam with no caller — the shape C28 rejected. What bounds the drift is
// the `--self-test`, which builds nine pages whose answers are known and asserts the
// census AND `largestImage` AND `drawnLargestImage` on every one, so the boundary between
// `withinCap` and `diverges` is pinned from both sides by production's own answers. It runs
// on **every invocation**, so a sweep cannot be taken from a build whose model has drifted.
// The sweep also carries a cheap online guard: `diverges` says the dictionary walk scanned
// the dictionary holding that image, so `dictWidth` must not be `-`, and a row where it is
// takes the run down with exit 5.
//
//   Tools/score-drawn-images --self-test              # 46 checks, exit 4 on failure
//   awk -F'\t' 'NR>1 {print $16}' drawn.tsv | sort | uniq -c        # the census
//   awk -F'\t' 'NR>1 {print $15}' drawn.tsv | sort -n | uniq -c     # bare-form depths
//
// ⛔ `formDepth` is capped at `censusDepthBound` and NOT at either shipped number, so a
// page deeper than that reads `partial` rather than a maximum it cannot support.
import Foundation
import PDFKit

let args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else {
    FileHandle.standardError.write(
        Data(("usage: score-drawn-images <pdf> [pdf …]   (one row per page, TSV on stdout)\n"
              + "       score-drawn-images --self-test   (the form-nesting census, on fixtures)\n"
              + "\nColumns 14-16 are the form-nesting census; see this file's header.\n").utf8))
    exit(2)
}

// ── The census ─────────────────────────────────────────────────────────────────────────

/// A hard bound on the census recursion, and **not** a model of either shipped cap. It is
/// here so a cyclic or absurdly nested file cannot run the sweep away; a page that reaches
/// it reads `partial`, which is the honest answer rather than a maximum that is a floor.
let censusDepthBound = 8

/// The page's form-nesting structure, measured with no cap at 3 or 4.
struct FormNesting {
    /// Forms entered along the deepest chain. 0 means the page draws no form at all.
    var formDepth = 0
    /// Forms carrying no `/Resources` of their own along the chain with the most of them.
    var bareDepth = 0
    /// An image is drawn at `n >= 4` with `n - b <= 3`: the dictionary walk lists it and the
    /// drawn walk is refused before it reaches the operator. Page 14's shape.
    var divergent = false
    /// An image is drawn at `n >= 4` with `n - b >= 4`: *probably* beyond both walks, so the
    /// policy falls back either way. Pages 11 and 13's shape.
    /// ⛔ **This is the one verdict that can be WRONG, and in the unsafe direction.** `n - b`
    /// only bounds the dictionary depth from above (see the header): if the chain's forms share
    /// a `/Resources` dictionary, `largestImage` reaches the image anyway and the page is a
    /// real divergence recorded as harmless. Do not read `bothBlind` as "nothing was lost".
    var bothBlind = false
    /// A name that would not resolve, or `censusDepthBound` reached. The maxima above are
    /// then floors and the verdict cannot be trusted.
    var partial = false
}

/// What the census implies about the two walks' reach on this page.
///
/// Order is load-bearing: `partial` first because nothing else can be claimed over an
/// incomplete traversal, then the two image findings, and only then the structural ones.
/// A page can hold both a divergent image and a shallow one; `diverges` is the answer that
/// matters, so it wins.
func nestVerdict(_ n: FormNesting) -> String {
    if n.partial { return "partial" }
    if n.divergent { return "diverges" }
    if n.bothBlind { return "bothBlind" }
    if n.formDepth >= 4 { return "capRefused" }
    if n.formDepth >= 1 { return "withinCap" }
    return "flat"
}

/// Follow every `Do` the page issues and record how deep the form chains go, and how many
/// of the forms in them are bare.
///
/// The traversal mirrors `Flattener.drawnLargestImage` deliberately — the same
/// `CGPDFOperatorTable`, the same `formResources ?? inherited ?? streamDict` scope rule
/// (the review of that function's diff established that the page's scope is the wrong one
/// and that `CGPDFContentStreamGetResource` does not search the parent chain), and the same
/// `/Width`/`/Height` plausibility guards. It differs in exactly two ways, both the point:
/// there is no `depth < 3`, and it counts rather than measuring a width.
func formNesting(of page: PDFPage) -> FormNesting {
    guard let cgPage = page.pageRef else {
        var out = FormNesting(); out.partial = true; return out
    }

    /// One form stream, in one resource scope, at one depth, with one bare count. The
    /// depth and the bare count are in the key because this walk wants **maxima** where
    /// production wants a first answer: a stream already scanned at depth 2 must still be
    /// scanned when a longer path arrives at depth 3, or `formDepth` understates itself.
    /// Bounded work all the same — at most `censusDepthBound²` visits per (stream, scope).
    struct Visit: Hashable {
        let stream: UnsafeRawPointer
        let scope: UnsafeRawPointer
        let depth: Int
        let bare: Int
    }
    final class State {
        var out = FormNesting()
        var depth = 0
        var bare = 0
        var seen: Set<Visit> = []
        var table: CGPDFOperatorTableRef?
        var resources: CGPDFDictionaryRef?
    }
    let state = State()
    if let dict = cgPage.dictionary {
        var resources: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(dict, "Resources", &resources) {
            state.resources = resources
        }
    }
    guard let table = CGPDFOperatorTableCreate() else {
        var out = FormNesting(); out.partial = true; return out
    }
    state.table = table

    CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
        guard let info else { return }
        let s = Unmanaged<State>.fromOpaque(info).takeUnretainedValue()
        var name: UnsafePointer<Int8>?
        let cs = CGPDFScannerGetContentStream(scanner)
        guard CGPDFScannerPopName(scanner, &name), let name,
              let object = CGPDFContentStreamGetResource(cs, "XObject", name) else {
            s.out.partial = true
            return
        }
        var stream: CGPDFStreamRef?
        guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
              let streamDict = CGPDFStreamGetDictionary(stream) else {
            s.out.partial = true
            return
        }
        var subtype: UnsafePointer<Int8>?
        guard CGPDFDictionaryGetName(streamDict, "Subtype", &subtype), let subtype else {
            s.out.partial = true
            return
        }
        switch String(cString: subtype) {
        case "Image":
            // The same guards both shipped walks apply, so an implausible declaration is
            // not counted as an image here either (R24, A7.1).
            var w: CGPDFInteger = 0, h: CGPDFInteger = 0
            guard CGPDFDictionaryGetInteger(streamDict, "Width", &w),
                  CGPDFDictionaryGetInteger(streamDict, "Height", &h),
                  w > 0, h > 0,
                  w <= CGPDFInteger(Flattener.maximumDeclaredImageSide),
                  h <= CGPDFInteger(Flattener.maximumDeclaredImageSide)
            else { return }
            // n and r, from the header's arithmetic. `r = n - b` because every form is
            // either bare or resource-carrying, and only the latter deepen the dictionary.
            let n = s.depth, r = s.depth - s.bare
            if n >= 4 {
                if r <= 3 { s.out.divergent = true } else { s.out.bothBlind = true }
            }
        case "Form":
            guard let table = s.table else { return }
            var formResources: CGPDFDictionaryRef?
            let carries = CGPDFDictionaryGetDictionary(streamDict, "Resources", &formResources)
                && formResources != nil
            let nextDepth = s.depth + 1
            let nextBare = s.bare + (carries ? 0 : 1)
            guard nextDepth <= censusDepthBound else { s.out.partial = true; return }
            s.out.formDepth = max(s.out.formDepth, nextDepth)
            s.out.bareDepth = max(s.out.bareDepth, nextBare)
            let inherited = s.resources
            let resources = formResources ?? inherited ?? streamDict
            let visit = Visit(stream: unsafeBitCast(stream, to: UnsafeRawPointer.self),
                              scope: unsafeBitCast(resources, to: UnsafeRawPointer.self),
                              depth: nextDepth, bare: nextBare)
            guard s.seen.insert(visit).inserted else { return }
            let nested = CGPDFContentStreamCreateWithStream(stream, resources, cs)
            let nestedScanner = CGPDFScannerCreate(nested, table, info)
            s.depth = nextDepth
            s.bare = nextBare
            s.resources = resources
            CGPDFScannerScan(nestedScanner)
            s.resources = inherited
            s.depth = nextDepth - 1
            s.bare = nextBare - (carries ? 0 : 1)
            CGPDFScannerRelease(nestedScanner)
            CGPDFContentStreamRelease(nested)
        default:
            break
        }
    }

    let stream = CGPDFContentStreamCreateWithPage(cgPage)
    let scanner = CGPDFScannerCreate(stream, table,
                                     Unmanaged.passUnretained(state).toOpaque())
    CGPDFScannerScan(scanner)
    CGPDFScannerRelease(scanner)
    CGPDFContentStreamRelease(stream)
    CGPDFOperatorTableRelease(table)
    return state.out
}

// One printer over one array. Counting tab escapes by eye has put the wrong number of
// fields under a header three times here — T14's SKIP row, A12.3's `score-mrc`, T18's two.
// Column 6 was `shippedRebuildDPI` and held `rebuildDPI(of:)`. Renamed with C24's wiring:
// production now *is* the drawn walk, so leaving it there made columns 6 and 10 the same
// number by construction. `dictRebuildDPI` keeps the comparison — and keeps this sweep
// comparable with `DRAWN-2026-08-16.tsv`, whose column 6 was that same policy over that same
// walk, taken before the change.
let columns = ["document", "page", "drawsAny",
               "dictWidth", "dictDPI", "dictRebuildDPI",
               "drawnKind", "drawnWidth", "drawnDPI", "drawnRebuildDPI",
               "policyMoves", "verdict", "shippedRebuildDPI",
               // Appended, never inserted: `DRAWN-2026-08-16.tsv` and every query in this
               // header address columns by position.
               "formDepth", "bareDepth", "nestVerdict"]

func row(_ fields: [String]) {
    precondition(fields.count == columns.count,
                 "row has \(fields.count) fields against \(columns.count) columns")
    print(fields.joined(separator: "\t"))
}

// ── The self-test, on nine built pages ──────────────────────────────────────────────────
//
// Nine pages whose nesting is known by construction, and every one of them asserts the
// census **and** both shipped walks. That pairing is the gate: the census is a second
// implementation of the traversal, so what keeps it honest is not its own consistency but
// agreeing with `largestImage` and `drawnLargestImage` about which images each can see.
//
// The boundary is pages 7 and 8 read together. Page 7 is three bare forms and page 6 is
// four, one structural step apart: the dictionary walk answers both, the drawn walk answers
// page 7 and not page 6. Page 5 is the negative control at the SAME `formDepth` of 4 with
// no bare form in it, where `r = 4` and neither walk answers — so `formDepth >= 4` alone is
// not the divergence and the rows say which term does the work. Page 8 is the second
// positive with `b = 2` rather than 4, which is why the verdict is `n - b <= 3` and not
// "every form in the chain is bare". Page 9 brackets the OTHER walk's boundary from the
// reached side — `r = 3`, the deepest dictionary it scans — so a dictionary walk that
// refused at 3 could not pass this table, where page 5 alone left that end unbounded.
//
// ⛔ **The four sabotages this table was watched failing against, 2026-08-26, every one
// predicted by count before the run.** Two in the census (12 failing checks and 1) and --
// the ones that matter -- **two in `Sources/Flattener.swift` itself**: loosening
// `largestImage`'s `depth < 4` reds **exactly one** row (p5's largestImage answer, nothing
// -> 1200) and loosening `drawnLargestImage`'s `s.depth < 3` reds **exactly three** (p5,
// p6 and p8's drawn answers), both at exit 4. So this table pins PRODUCTION's two caps and
// not merely the census's model of them, which is what a second implementation has to earn.
func buildCensusFixture(at url: URL) -> Bool {
    var objects: [String] = []
    func add(_ body: String) -> Int { objects.append(body); return objects.count }
    // 1 is the catalogue and 2 the page tree; both are rewritten once the page list exists.
    _ = add("placeholder"); _ = add("placeholder")

    func image(_ w: Int) -> Int {
        add("<< /Type /XObject /Subtype /Image /Width \(w) /Height \(w) "
            + "/ColorSpace /DeviceGray /BitsPerComponent 8 /Length 3 "
            + ">>\nstream\nabc\nendstream")
    }
    /// `resources: nil` is the whole subject of this file: a **bare** form.
    func form(_ body: String, resources: String?) -> Int {
        var d = "<< /Type /XObject /Subtype /Form /BBox [0 0 612 792] "
        if let resources { d += "/Resources \(resources) " }
        return add(d + "/Length \(body.utf8.count) >>\nstream\n" + body + "endstream")
    }
    func draw(_ name: String) -> String { "q 1 0 0 1 0 0 cm /\(name) Do Q\n" }
    func xobjects(_ pairs: [(String, Int)]) -> String {
        "<< /XObject << " + pairs.map { "/\($0.0) \($0.1) 0 R" }.joined(separator: " ")
            + " >> >>"
    }
    var pageObjects: [Int] = []
    func page(_ resources: String, draws body: String) {
        let contents = add("<< /Length \(body.utf8.count) >>\nstream\n" + body + "endstream")
        pageObjects.append(add("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
                               + "/Resources \(resources) /Contents \(contents) 0 R >>"))
    }

    // p1 — draws nothing at all.
    page("<< >>", draws: "q Q\n")
    // p2 — an image straight off the page's own dictionary. No form anywhere.
    let imA = image(900)
    page(xobjects([("Im", imA)]), draws: draw("Im"))
    // p3 — one resource-carrying form holding the image.
    let imB = image(1000)
    let fB = form(draw("Im"), resources: xobjects([("Im", imB)]))
    page(xobjects([("F", fB)]), draws: draw("F"))
    // p4 — one BARE form; the image is named in the page's dictionary because that is the
    // only scope its `Do` can resolve in.
    let imC = image(1100)
    let fC = form(draw("Im"), resources: nil)
    page(xobjects([("Im", imC), ("F", fC)]), draws: draw("F"))
    // p5 — four resource-carrying levels: n = 4, b = 0, so r = 4 and NEITHER walk reaches.
    let imD = image(1200)
    let d4 = form(draw("Im"), resources: xobjects([("Im", imD)]))
    let d3 = form(draw("F4"), resources: xobjects([("F4", d4)]))
    let d2 = form(draw("F3"), resources: xobjects([("F3", d3)]))
    let d1 = form(draw("F2"), resources: xobjects([("F2", d2)]))
    page(xobjects([("F1", d1)]), draws: draw("F1"))
    // p6 — four BARE levels: page 14 of `shared-resources.pdf`, rebuilt here. n = 4, b = 4,
    // r = 0. The dictionary walk finds the image at depth 0 and the drawn walk never
    // reaches the operator.
    let imE = image(1300)
    let p4f = form(draw("Im"), resources: nil)
    let p3f = form(draw("P4"), resources: nil)
    let p2f = form(draw("P3"), resources: nil)
    let p1f = form(draw("P2"), resources: nil)
    page(xobjects([("Im", imE), ("P1", p1f), ("P2", p2f), ("P3", p3f), ("P4", p4f)]),
         draws: draw("P1"))
    // p7 — three bare levels. One step shallower than p6 and both walks answer it.
    let imF = image(1400)
    let q3 = form(draw("Im"), resources: nil)
    let q2 = form(draw("Q3"), resources: nil)
    let q1 = form(draw("Q2"), resources: nil)
    page(xobjects([("Im", imF), ("Q1", q1), ("Q2", q2), ("Q3", q3)]), draws: draw("Q1"))
    // p8 — two resource-carrying levels then two bare ones: n = 4, b = 2, r = 2. The image
    // is named in the inner form's dictionary, which the dictionary walk reaches at depth 2.
    let imG = image(1500)
    let s2 = form(draw("Im"), resources: nil)
    let s1 = form(draw("S2"), resources: nil)
    let r2 = form(draw("S1"), resources: xobjects([("S1", s1), ("S2", s2), ("Im", imG)]))
    let r1 = form(draw("R2"), resources: xobjects([("R2", r2)]))
    page(xobjects([("R1", r1)]), draws: draw("R1"))
    // p9 — three resource-carrying levels: n = 3, b = 0, r = 3. The dictionary walk's guard
    // is `depth < 4`, so this is the deepest dictionary it scans and p5 is the first it
    // refuses; without this page nothing brackets that boundary from the reached side and a
    // walk that refused at 3 would pass the whole table.
    let imH = image(1600)
    let t3 = form(draw("Im"), resources: xobjects([("Im", imH)]))
    let t2 = form(draw("T3"), resources: xobjects([("T3", t3)]))
    let t1 = form(draw("T2"), resources: xobjects([("T2", t2)]))
    page(xobjects([("T1", t1)]), draws: draw("T1"))

    objects[0] = "<< /Type /Catalog /Pages 2 0 R >>"
    objects[1] = "<< /Type /Pages /Count \(pageObjects.count) /Kids ["
        + pageObjects.map { "\($0) 0 R" }.joined(separator: " ") + "] >>"

    var pdf = "%PDF-1.4\n"
    var offsets: [Int] = []
    for (i, body) in objects.enumerated() {
        offsets.append(pdf.utf8.count)
        pdf += "\(i + 1) 0 obj\n\(body)\nendobj\n"
    }
    let xref = pdf.utf8.count
    pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
    for o in offsets { pdf += String(format: "%010d 00000 n \n", o) }
    pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\n"
    pdf += "startxref\n\(xref)\n%%EOF\n"
    do { try pdf.write(to: url, atomically: true, encoding: .isoLatin1) } catch { return false }
    return true
}

/// Runs on **every** invocation, not only under `--self-test`, so a sweep cannot be taken
/// from a build whose census has drifted from the walks it is reporting alongside.
/// Exit 4 on failure, which is `score-mrc`'s convention and is deliberately not 2 — a
/// configuration refusal and a broken build must not be confusable.
func runSelfTest() {
    var passed = 0, failed = 0
    func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { passed += 1 } else {
            failed += 1
            FileHandle.standardError.write(
                Data("  FAIL \(label)\(detail.isEmpty ? "" : " — \(detail)")\n".utf8))
        }
    }
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("drawn-census-\(ProcessInfo.processInfo.processIdentifier)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("census.pdf")
    guard buildCensusFixture(at: url), let doc = PDFDocument(url: url) else {
        FileHandle.standardError.write(Data("  FAIL the census fixture could not be built\n".utf8))
        exit(4)
    }
    check("the census fixture is a readable nine-page PDF", doc.pageCount == 9,
          "\(doc.pageCount) pages")

    /// formDepth, bareDepth, verdict, what `largestImage` answers, what the drawn walk does.
    let expected: [(fd: Int, bd: Int, verdict: String, dict: Int?, drawn: Int?)] = [
        (0, 0, "flat",       nil,  nil),   // p1, nothing drawn
        (0, 0, "flat",       900,  900),   // p2, no form in sight
        (1, 0, "withinCap",  1000, 1000),  // p3, one resource-carrying form
        (1, 1, "withinCap",  1100, 1100),  // p4, one bare form
        (4, 0, "bothBlind",  nil,  nil),   // p5, four rc levels: r = 4, both blind
        (4, 4, "diverges",   1300, nil),   // p6, four bare levels: page 14's shape
        (3, 3, "withinCap",  1400, 1400),  // p7, three bare levels: the step below p6
        (4, 2, "diverges",   1500, nil),   // p8, two rc then two bare: b = 2, not 4
        (3, 0, "withinCap",  1600, 1600),  // p9, three rc levels: r = 3, the deepest reached
    ]
    for (i, want) in expected.enumerated() {
        guard let page = doc.page(at: i) else {
            check("census p\(i + 1) is readable", false); continue
        }
        let got = formNesting(of: page)
        check("census p\(i + 1) formDepth is \(want.fd)", got.formDepth == want.fd,
              "\(got.formDepth)")
        check("census p\(i + 1) bareDepth is \(want.bd)", got.bareDepth == want.bd,
              "\(got.bareDepth)")
        check("census p\(i + 1) reads \(want.verdict)", nestVerdict(got) == want.verdict,
              "\(nestVerdict(got)) (fd \(got.formDepth) bd \(got.bareDepth) "
                  + "div \(got.divergent) blind \(got.bothBlind) partial \(got.partial))")
        let dict = Flattener.largestImage(of: page)?.pixelWidth
        check("census p\(i + 1) largestImage answers "
                  + "\(want.dict.map(String.init) ?? "nothing")",
              dict == want.dict, "\(dict.map(String.init) ?? "nil")")
        var drawnWidth: Int?
        if case let .largest(_, w) = Flattener.drawnLargestImage(of: page) { drawnWidth = w }
        check("census p\(i + 1) the drawn walk answers "
                  + "\(want.drawn.map(String.init) ?? "nothing")",
              drawnWidth == want.drawn, "\(drawnWidth.map(String.init) ?? "nil")")
    }

    if failed == 0 {
        FileHandle.standardError.write(Data("self-test ok (\(passed) checks)\n".utf8))
    } else {
        FileHandle.standardError.write(
            Data("SELF-TEST FAILED: \(failed) of \(passed + failed) checks\n".utf8))
        exit(4)
    }
}

runSelfTest()
if args == ["--self-test"] { exit(0) }

print(columns.joined(separator: "\t"))

func dpi(_ v: Double?) -> String { v == nil ? "-" : String(format: "%.1f", v!) }

var totals: [String: Int] = [:]
var pagesSeen = 0
var documentsSeen = 0
/// Pages where `rebuildDPI(of:)` disagreed with this tool's own reading of the drawn walk.
/// Must be empty; a non-empty list is the sweep refusing to be believed.
var divergences: [String] = []
var censusTotals: [String: Int] = [:]
var formDepths: [Int: Int] = [:]
var bareDepths: [Int: Int] = [:]
/// Pages whose census says `diverges` while `largestImage` found nothing — impossible if the
/// census's model of the dictionary walk's reach is right, so a non-empty list means the
/// instrument and not the corpus.
var censusDoubts: [String] = []

for path in args {
    let url = URL(fileURLWithPath: path)
    guard let doc = PDFDocument(url: url), doc.pageCount > 0 else {
        FileHandle.standardError.write(Data("skip \(path): unreadable\n".utf8))
        continue
    }
    documentsSeen += 1
    let name = url.deletingPathExtension().lastPathComponent
    for i in 0..<doc.pageCount {
        guard let page = doc.page(at: i) else {
            FileHandle.standardError.write(Data("skip \(name) p\(i + 1): unreadable page\n".utf8))
            continue
        }
        pagesSeen += 1

        let draws = Flattener.drawsAnyXObject(page)
        let dict = Flattener.largestImage(of: page)
        // The old body of `rebuildDPI(of:)`, verbatim — what production answered before C24's
        // wiring landed, so column 11 is a real before/after and not this tool comparing
        // production against itself.
        let dictRebuild = Flattener.rebuildDPI(from: dict)
        // And what production answers now. Asserted equal to `drawnRebuild` below rather than
        // assumed: a tool that recomputes the policy it is grading has to say so out loud.
        let shipped = Flattener.rebuildDPI(of: page)
        let drawn = Flattener.drawnLargestImage(of: page)

        var kind = "", drawnWidth = "-", drawnDPI = "-"
        var drawnRebuild: Double
        switch drawn {
        case .unreadable:
            kind = "unreadable"
            // What a caller must do with "could not tell": the `/Resources` answer.
            drawnRebuild = dictRebuild
        case .noImage:
            kind = "none"
            drawnRebuild = Flattener.rebuildDPI(from: nil)
        case let .largest(d, w):
            kind = "largest"
            drawnWidth = String(w)
            drawnDPI = String(format: "%.1f", d)
            drawnRebuild = Flattener.rebuildDPI(from: (dpi: d, pixelWidth: w))
        }

        // The verdict compares the two *measurements*; `policyMoves` compares what the
        // shipped policy does with each. They are different questions, and C24's structural
        // half is the case where the first moved and the second did not on 0 pages of 128.
        //
        // **`wider` is not an anomaly, and reading it as one is how C24 came to carry an
        // observation without a cause.** Both walks pick the largest image by *area* and
        // then report its *width*, so the drawn subset's winner can be wider than the whole
        // dictionary's. `AI 2027` p4 draws only `/Im5`, 3000x1011 — while the dictionary's
        // largest by area is `/Im52`, 2929x2370. Neither walk has missed a candidate. The
        // entry's proposed cause was the `walkedAt` memo; that was tested and refuted, and
        // this is what was actually happening.
        //
        // **The drawn answer is asked about first, and the order is the whole correctness of
        // this column.** It read `case (nil, _)` first, which filed every page whose
        // dictionary walk found nothing as `noDictImage` *whatever the drawn walk said* — and
        // an unresolvable name is most likely on exactly such a page, so the `unreadable`
        // count was "unreadable pages that also had a dictionary image" while the register
        // quoted it as the number of pages this could not read. Found by the review of this
        // diff. On the 16,987-page corpus it changed no row — all 285 `noDictImage` pages
        // report `drawnKind=none` — so the count it published was right by luck rather than
        // by construction.
        let verdict: String
        switch (dict, drawn) {
        case (_, .unreadable):
            verdict = "unreadable"
        case (nil, .noImage):
            // Both walks agree there is nothing here. C24's structural half made this the
            // common case: `largestImage` now returns nil on a page that invokes no XObject.
            verdict = "noDictImage"
        case (_, .noImage):
            verdict = "drawsNoImage"
        case (nil, .largest):
            // The drawn walk found an image the dictionary walk did not. **0 pages of 16,987**
            // — named rather than folded into `noDictImage`, because folding it is the defect
            // above and because a caps disagreement between the two walks would land here.
            verdict = "drawnOnly"
        case let (d?, .largest(_, w)):
            if w == d.pixelWidth { verdict = "agree" }
            else if w < d.pixelWidth { verdict = "smaller" }
            else { verdict = "wider" }
        }
        totals[verdict, default: 0] += 1

        // **Production must equal the drawn arm on every page**, and a mismatch is a defect in
        // `rebuildDPI` or in this tool's copy of the three-case switch. Collected rather than
        // asserted, so a divergence is reported with the page that has it instead of taking
        // the sweep down 12,000 rows in.
        if abs(shipped - drawnRebuild) >= 0.05 { divergences.append("\(name) p\(i + 1)") }

        // The census, and its own online guard. `diverges` asserts that an image is drawn
        // at a resource depth of 3 or less, so the dictionary walk scanned the dictionary
        // holding it and `largestImage` cannot be nil. The converse is NOT sound and is not
        // checked — a page may hold a larger shallow image, so the two walks can agree on a
        // width while a deeper one is out of the drawn walk's reach.
        let nest = formNesting(of: page)
        let census = nestVerdict(nest)
        censusTotals[census, default: 0] += 1
        if census != "partial" {
            formDepths[nest.formDepth, default: 0] += 1
            bareDepths[nest.bareDepth, default: 0] += 1
        }
        if census == "diverges" && dict == nil { censusDoubts.append("\(name) p\(i + 1)") }

        row([name, String(i + 1),
             draws == nil ? "unknown" : (draws! ? "yes" : "no"),
             dict == nil ? "-" : String(dict!.pixelWidth), dpi(dict?.dpi), dpi(dictRebuild),
             kind, drawnWidth, drawnDPI, dpi(drawnRebuild),
             abs(drawnRebuild - dictRebuild) < 0.05 ? "same" : "moves",
             verdict, dpi(shipped),
             String(nest.formDepth), String(nest.bareDepth), census])
    }
    fflush(stdout)
}

// To stderr, so the TSV on stdout stays a TSV.
var summary = "\n\(documentsSeen) documents, \(pagesSeen) pages\n"
for (verdict, n) in totals.sorted(by: { $0.value > $1.value }) {
    // Padded in Swift rather than with `%-14s`, which needs a C string and therefore a
    // force-unwrapped `utf8String` — a crash in the summary of a completed sweep.
    let label = verdict.padding(toLength: max(14, verdict.count), withPad: " ",
                                startingAt: 0)
    summary += "  \(label) \(String(format: "%6d", n))\n"
}
// The self-check, printed whichever way it went. A sweep that says nothing about it reads as
// a pass, and "production agrees with the drawn walk on every page" is the claim the wiring
// rests on — so it is stated, with the count, every run.
if divergences.isEmpty {
    summary += "  rebuildDPI(of:) matched the drawn arm on all \(pagesSeen) pages\n"
} else {
    summary += "  ** \(divergences.count) page(s) where rebuildDPI(of:) DISAGREED with the "
        + "drawn arm: \(divergences.prefix(10).joined(separator: ", "))"
        + (divergences.count > 10 ? " …" : "") + "\n"
}
// The census, printed whichever way it went for the same reason: `bare-form-reach`'s
// question is "how many pages have the shape", and a run that says nothing about it reads
// as zero.
summary += "\n  form-nesting census (columns 14-16)\n"
for (verdict, n) in censusTotals.sorted(by: { $0.value > $1.value }) {
    let label = verdict.padding(toLength: max(14, verdict.count), withPad: " ", startingAt: 0)
    summary += "  \(label) \(String(format: "%6d", n))\n"
}
summary += "  formDepth  " + formDepths.sorted { $0.key < $1.key }
    .map { "\($0.key):\($0.value)" }.joined(separator: " ") + "\n"
summary += "  bareDepth  " + bareDepths.sorted { $0.key < $1.key }
    .map { "\($0.key):\($0.value)" }.joined(separator: " ") + "\n"
if censusDoubts.isEmpty {
    summary += "  every diverges row had a dictionary answer, on all \(pagesSeen) pages\n"
} else {
    summary += "  ** \(censusDoubts.count) page(s) reading `diverges` where largestImage "
        + "found NOTHING — the census is wrong, not the corpus: "
        + censusDoubts.prefix(10).joined(separator: ", ")
        + (censusDoubts.count > 10 ? " …" : "") + "\n"
}
FileHandle.standardError.write(Data(summary.utf8))
if !divergences.isEmpty { exit(1) }
// Distinct from 1: that exit means production disagreed with the drawn arm, this one means
// the census disagreed with the dictionary walk. Different instruments, different repairs.
if !censusDoubts.isEmpty { exit(5) }
