// score-annot-marks — which of C29 (B)'s refusals a mixed document hits, and why.
//
// C29 (B) splices a born-digital page back into the JBIG2 document instead of letting
// one such page cost every other page its compression. It refuses to do that in three
// places, and this tool asks all three of a real document. The queue item is
// `c29-count-clause-corpus`, opened because the SECOND refusal grew a clause after the
// population was measured:
//
//   `Annotations.pageCarriesMark` refuses a page whose raw `/Annots` array is LONGER
//   than what PDFKit surfaced. That is new on the path every mixed document takes, and
//   the published "16 of the 42 carry an outline, so 26 of 42 get the splice" was
//   measured against the predicate WITHOUT it. So the 26 is not known to be current.
//
// ⛔ **IT RAN. THE ANSWER IS 22 OF 42, AND THE NEW CLAUSE IS NOT WHY**
// (`C29-MARKS-2026-08-26.tsv`, 392 born-digital pages in the 42 documents of
// `C29-CORPUS-2026-08-25.tsv`). The clause the item was opened about fires on **0 of the
// 392**: `rawAnnots == surfacedN` on **392 of 392** rows, `nilN` 0 everywhere, and no page
// read `blind`. What costs the other four documents is the *ordinary* answer — a real
// reader's mark on a born-digital page, `subtype` on 8 pages in 4 documents, none of them
// among the 16 with an outline. So **26 → 22** is the mark refusal doing its job, and the
// two refusals are DISJOINT: 16 + 4 + 0 all-passthrough = 20 refused, 22 eligible.
// ⚠️ **The outline column reproduces the published 16 through a different reader** —
// `SearchableWriter.readOutline` (PDFKit) against the `qpdf --json --json-key=outlines`
// pass that priced it — and `1954 - Why.pdf` reads `outlineN` 0 here, as that measurement
// said. That is the run's only control across two DIFFERENT readers. ⚠️ There is a second,
// weaker one worth stating rather than discarding: `(doc, digitalN)` and `(doc, pages)`
// reproduce `C29-CORPUS-2026-08-25.tsv`'s `digitalPages` and `pages` on **42 of 42**. Same
// `Flattener.digitalTextPages` both times, so it is a determinism re-run and not two
// readers — but it is what says the shell glob in USAGE resolved the intended 42 files,
// which is a live failure mode on filenames holding spaces and U+00A0.
// ⚠️ **`/Link`'s exclusion from `copiedSubtypes` is what makes the fix reach anything**:
// 776 of the 830 annotations on those 392 pages are `/Link`, and the 22 eligible documents
// carry 253 of them. Put `/Link` in the set and the splice would refuse most of its own
// population.
//
// ⛔ **WHAT IT MEASURES IS ELIGIBILITY AT THREE SEAMS, NOT "THIS DOCUMENT WILL SPLICE".**
// The production condition is `Sources/Model.swift:2300-2305`:
//
//   if wantJBIG2, encoded.count == expected,
//      encoded.count == bitmaps.count,
//      outline.isEmpty || carriedThrough.isEmpty,
//      !Annotations.anyCopiableMark(in: file, password: password, onPages: carriedThrough),
//      encoded.count > carriedThrough.count, let qpdf = JBIG2.merger {
//
// Three of those six terms are answerable without a rebuild and are what `splice` below
// is: the outline term, the mark term, and `encoded.count > carriedThrough.count`. The
// other three are NOT asked here — `wantJBIG2` is a setting, `encoded.count == expected`
// and `== bitmaps.count` need a whole `flatten` plus a `jbig2enc` pass, and
// `JBIG2.merger` is a `qpdf` on `PATH`. A document this tool calls `splice=yes` can still
// take the Flate route for any of those three. Read the column as "not refused by the
// three cheap terms".
//
// ⛔ **THE CLAUSE LABEL IS A DIFFERENTIAL PROBE OVER THE SHIPPED FUNCTION, NOT A COPY OF
// IT.** `Annotations.pageCarriesMark` returns one `Bool` and cannot say which of its four
// ways of answering `true` fired, which is the whole question here. So `clauseOf` never
// re-implements the predicate: it calls it again with one clause neutralised and reads the
// difference — `rawAnnotationCount: surfaced.count` makes the `>` comparison false while
// leaving the subtype loop untouched, and `surfaced.compactMap { $0 }` removes the
// `nil` half of that loop while leaving the membership test. This matters because
// `BUGS.md`'s `alltext-replica` is a tool that replicated a shipped guard with one term
// missing and read `all-text` on exactly the pages the shipped guard refuses — wrong in
// the direction that hid the defect. A differential probe cannot drift that way: if the
// shipped function changes, the labels change with it.
// ⛔ **BUT "ASK THE SHIPPED FUNCTION WHETHER THE LABEL AGREES WITH IT" IS A TAUTOLOGY, AND
// THIS FILE SHIPPED IT AS FIFTEEN CHECKS AND A WHOLE EXIT BEFORE ITS OWN REVIEW CAUGHT
// IT** — `clauseOf` returns `.none` from exactly one place, its opening guard, which *is*
// that call. What guards the labels instead is `labelViolations`: laws relating the label
// to the **printed columns** (`rawAnnots`, `nilN`, `copiedSubtypes` membership), which are
// independent of the probe and can catch a mislabel *among* `count`/`subtype`/`nilType`/
// `blind` — the failure the tautology was structurally blind to. Group 1b of the
// self-test is those laws on synthetic inputs, group 1c is nine deliberately wrong labels
// each of which must be REFUSED (so the laws cannot themselves be vacuous), and a real
// page that breaks one is **exit 6** rather than a printed row.
// ⚠️ `spliceEligible` IS a replica — of the three-term subset of the call site quoted
// above, which is inline in a 400-line function and cannot be called. Group 3 pins its
// truth table against that quotation; nothing can stop the call site drifting away from
// it, and `Tools/score-text-route.swift`'s `verdict` column is the recorded precedent for
// how that goes wrong (three repairs of one `let`). Re-read the quote before trusting a
// figure from here.
//
// ⛔ **THE LABEL NAMES THE DECISIVE CLAUSE, NOT THE ONE THAT HAPPENED TO RETURN FIRST,
// and the difference is this run's whole point.** `pageCarriesMark` tests the count
// arithmetic before the subtype loop, so on a page holding a `/Highlight` AND a longer
// `/Annots` array than PDFKit surfaced, the clause that literally returns is `count` —
// and labelling it `count` would say a document lost (B)'s compression to the new clause
// when the highlight had already refused it. So `count` means *decisive*: neutralising
// the arithmetic flips the answer. `blind` is the one exception and is unconditional,
// because `rawAnnots < 0` is a statement about the READER failing rather than about the
// marks, and it outranks anything that reader thinks it saw. Where both halves of the
// loop refuse, the label is `subtype` — the concrete one — and `nilN` is printed as its
// own column so the `nil` half is never hidden behind a label.
// ⚠️ **The header said `blind > count > subtype > nilType` and the self-test refused it
// on its first run** — `(["Highlight"], raw: 3)` wants `subtype` under the rule above and
// the draft asserted `count`. Recorded rather than quietly corrected: the sentence was a
// claim about a probe that had not been run, which is CONTRIBUTING §3 in one line.
// ⚠️ Every row prints `rawAnnots` and `surfacedN`, so `raw > surfacedN` is readable off
// any row whatever its label says. The label is about decisiveness; the arithmetic is
// still there.
//
// ⚠️ `file` vs `inputFile`. The call site asks the outline of `inputFile` and the marks of
// `file`, and `file` starts as `inputFile` (`Model.swift:1894`) and is only reassigned
// when an image input was wrapped into a PDF. Every document in `testdocs/` is a PDF, so
// the two are the same URL here; on an image input they would not be.
//
// USAGE
//
//   mkdir -p /tmp/h && cp Tools/score-annot-marks.swift /tmp/h/main.swift
//   swiftc -O -o /tmp/score-annot-marks -target "$(uname -m)-apple-macos13.0" \
//     $(ls Sources/*.swift | grep -v App.swift) /tmp/h/main.swift
//   /tmp/score-annot-marks --self-test
//   /tmp/score-annot-marks "<pdf>" ["<pdf>" …]
//   PASSWORD=… /tmp/score-annot-marks "<pdf>"     # one password for every file given
//
// ⚠️ The copied file must be named `main.swift` or swiftc rejects top-level code.
//
// The 42 affected documents come from `C29-CORPUS-2026-08-25.tsv`, whose `doc` column is
// a basename. Corpus filenames hold spaces and U+00A0, so resolve them with a glob and
// never by retyping:
//
//   awk -F'\t' 'NR>1 && $5>0 {print $1}' C29-CORPUS-2026-08-25.tsv \
//     | while IFS= read -r n; do printf '%s\0' testdocs/*/"$n"; done \
//     | xargs -0 /tmp/score-annot-marks
//
// EXITS
//   0  measured every file given
//   2  usage: no paths, or `--self-test` with paths beside it
//   3  at least one file could not be opened, or held no born-digital page — named, and
//      loudly, because a silent skip on a population walk is how a corpus figure becomes
//      a claim about the documents that happened to work
//   5  the self-test failed — it runs on EVERY invocation, not only under `--self-test`
//   6  a clause label on a real page broke a law its own printed columns imply. The tool
//      is wrong, not the document; nothing it printed is usable.
//
// ⚠️ **No `Tools/fault-inject.sh` row, and that is a debt rather than a decision.** Exits
// 2, 3, 5 and 6 are four error branches with no case, which is CONTRIBUTING §4c's class;
// `score-text-voids`' README row is the precedent for naming which exits are unwatched
// instead of leaving a reader to assume they all are. Carried as the queue's
// `annot-marks-refusals`.
//
// COLUMNS  (one row per born-digital page; the document-level columns repeat down its rows)
//
//   doc        basename, tabs and newlines stripped
//   pages      `PDFDocument.pageCount`
//   digitalN   `Flattener.digitalTextPages` — the passthrough set's size
//   page       this page, 1-based
//   rawAnnots  `Annotations.rawAnnotationCount` — the page's own `/Annots` length, or -1
//              if the page dictionary could not be read at all
//   surfacedN  how many annotations PDFKit handed over on this page
//   nilN       how many of those had no readable subtype
//   subtypes   their subtypes, comma-joined, PDFKit's spelling (no leading slash); `-`
//              when none, `?` for a nil one
//   clause     blind | count | subtype | nilType | none — the DECISIVE one, see above.
//              `count` is the queue item's own question: a page refused by the new
//              arithmetic and by nothing else
//   pageMark   `Annotations.pageCarriesMark` for this page
//   docMark    `Annotations.anyCopiableMark` over the whole passthrough set — the value
//              the call site actually reads, so it can be `yes` on a row whose own
//              `pageMark` is `no`
//   outlineN   `SearchableWriter.readOutline` entry count. ⚠️ Production's own reader,
//              where the published 16-of-42 came from a `qpdf` pass — so a disagreement
//              between this column and that figure is two readers, not a change
//   allPass    every page is a passthrough page, so `encoded.count > carriedThrough.count`
//              refuses. `assemble` refuses an empty page list and such a document has
//              nothing to compress anyway
//   splice     the three cheap terms together — see the eligibility caveat above

import Foundation
import PDFKit

// ─────────────────────────────────────────────────────────────────────────────
// The clause label
// ─────────────────────────────────────────────────────────────────────────────

enum Clause: String {
    /// `rawAnnotationCount` was negative: the page's dictionary could not be read,
    /// so nothing about its annotations is known. A locked document does this.
    /// Unconditional — see the header. The reader failed, and that is the finding
    /// whatever else it thinks it saw.
    case blind
    /// The page's `/Annots` array is longer than what PDFKit surfaced, **and that
    /// is the only reason this page refuses the splice** — the clause this whole
    /// run exists to size. A page where a real mark also refuses reads `subtype`.
    case count
    /// PDFKit surfaced a subtype that is one of `Annotations.copiedSubtypes`. The
    /// ordinary answer: a real reader's mark.
    case subtype
    /// PDFKit surfaced an annotation whose subtype it could not name, and no named
    /// mark beside it.
    case nilType
    /// No mark. This page does not refuse the splice.
    case none
}

/// Which of `pageCarriesMark`'s four routes to `true` answered for this page.
///
/// Every branch is a call back into the shipped predicate with one clause
/// neutralised; see the header's note on why this is not a replica.
func clauseOf(surfaced: [String?], rawAnnots: Int) -> Clause {
    guard Annotations.pageCarriesMark(surfaced: surfaced,
                                     rawAnnotationCount: rawAnnots) else { return .none }
    if rawAnnots < 0 { return .blind }
    // Neutralise the `rawAnnotationCount > surfaced.count` comparison by making it
    // false, leaving the subtype loop exactly as it was.
    let loopAnswers = Annotations.pageCarriesMark(surfaced: surfaced,
                                                 rawAnnotationCount: surfaced.count)
    if !loopAnswers { return .count }
    // The loop answered. Drop the unnamed entries and ask whether a named subtype
    // is enough on its own.
    let named = surfaced.compactMap { $0 }
    let namedAnswers = Annotations.pageCarriesMark(surfaced: named.map { Optional($0) },
                                                  rawAnnotationCount: named.count)
    return namedAnswers ? .subtype : .nilType
}

/// Which laws relating the LABEL to the PRINTED COLUMNS this row breaks, empty if none.
///
/// ⛔ **This replaced a check that could not fail, and it is the eleventh in this
/// project's history.** The first version compared `clause != .none` against
/// `Annotations.pageCarriesMark` on the same inputs — but `clauseOf` returns `.none`
/// from exactly one place, its opening guard, which *is* that call. So the comparison
/// re-evaluated one pure function twice and could never differ: an exhaustive probe
/// over every array of length 0-3 drawn from `{nil, Highlight, Link, Widget, Ink}`
/// against `raw ∈ [-2, 5]` — 1,728 inputs — found 0 violations under the shipped
/// probe **and 0 under two sabotages of it that break every label**. Fifteen
/// `--self-test` checks and the whole of exit 6 were that comparison. Found by the
/// adversarial review of this file's own diff.
///
/// These laws are derived from the columns a reader can see plus `copiedSubtypes`,
/// which is a data set rather than the predicate's control flow — so they are
/// independent of `clauseOf` and can catch a mislabel *among* `count`, `subtype`,
/// `nilType` and `blind`, which is exactly what the tautology was blind to.
func labelViolations(_ clause: Clause, surfaced: [String?], rawAnnots: Int) -> [String] {
    var broken: [String] = []
    let nilN = surfaced.filter { $0 == nil }.count
    let named = surfaced.compactMap { $0 }.contains { Annotations.copiedSubtypes.contains("/" + $0) }
    // `blind` is the one unconditional label, so this law runs both ways.
    if (clause == .blind) != (rawAnnots < 0) {
        broken.append("blind must mean rawAnnots < 0 and nothing else (clause=\(clause.rawValue),"
                      + " rawAnnots=\(rawAnnots))")
    }
    if clause == .count, !(rawAnnots > surfaced.count) {
        broken.append("count needs rawAnnots > surfacedN (\(rawAnnots) vs \(surfaced.count))")
    }
    if clause == .nilType, nilN == 0 {
        broken.append("nilType needs an unnamed annotation, nilN is 0")
    }
    if clause == .subtype, !named {
        broken.append("subtype needs a copiedSubtypes member among the surfaced list")
    }
    if clause == .none {
        if rawAnnots < 0 { broken.append("none cannot hold with rawAnnots < 0") }
        if rawAnnots > surfaced.count {
            broken.append("none cannot hold with rawAnnots > surfacedN"
                          + " (\(rawAnnots) vs \(surfaced.count))")
        }
        if nilN > 0 { broken.append("none cannot hold with an unnamed annotation") }
        if named { broken.append("none cannot hold with a copiedSubtypes member surfaced") }
    }
    return broken
}

/// The three terms of `Model.swift:2300-2305` this tool can answer, and nothing else.
///
/// `pages` is the document's page count, standing in for `encoded.count == expected`;
/// `passthrough` for `carriedThrough`.
///
/// ⚠️ **The `passthrough == 0` guard is a PRECONDITION OF THE QUESTION, not one of the
/// three terms, and the difference is measured rather than glossed.** With
/// `carriedThrough` empty all three production terms in fact *pass* — term 4's
/// `carriedThrough.isEmpty` is true, `anyCopiableMark` returns `false` on an empty page
/// list so term 5's `!` holds, and term 6 is `encoded.count > 0` — so such a document
/// takes the JBIG2 route and simply never reaches `JBIG2.splice`. "Not refused by the
/// three cheap terms" is therefore the wrong reading of a `no` here; the right one is
/// "there is no passthrough page to splice". No printed row is affected, because such a
/// document is named and skipped at exit 3 before it is asked. Found by the adversarial
/// review of this file's own diff, which had it asserted the other way round.
func spliceEligible(pages: Int, passthrough: Int, outlineN: Int, docMark: Bool) -> Bool {
    guard passthrough > 0 else { return false }   // nothing to splice: see the note above
    if outlineN > 0 { return false }              // `--empty --pages` drops `/Outlines`
    if docMark { return false }                   // a mark would arrive twice and refuse the document
    return pages > passthrough                    // `assemble` refuses an empty page list
}

// ─────────────────────────────────────────────────────────────────────────────
// One printer, one column list. CONTRIBUTING §5: counting tab escapes by eye has
// put the wrong number of fields under a header three times here.
// ─────────────────────────────────────────────────────────────────────────────

let columns = ["doc", "pages", "digitalN", "page", "rawAnnots", "surfacedN", "nilN",
               "subtypes", "clause", "pageMark", "docMark", "outlineN", "allPass", "splice"]

func row(_ fields: [String]) -> String {
    precondition(fields.count == columns.count,
                 "row has \(fields.count) fields against \(columns.count) columns")
    return fields.joined(separator: "\t")
}

func clean(_ s: String) -> String {
    s.replacingOccurrences(of: "\t", with: " ")
     .replacingOccurrences(of: "\n", with: " ")
}

func yn(_ b: Bool) -> String { b ? "yes" : "no" }

// ─────────────────────────────────────────────────────────────────────────────
// Self-test
// ─────────────────────────────────────────────────────────────────────────────

func selfTest() -> [String] {
    var failures: [String] = []
    var checks = 0
    func check(_ ok: Bool, _ what: String) {
        checks += 1
        if !ok { failures.append(what) }
    }

    // Group 1 — the differential label against a hand-written expectation, one case per
    // shape. ⛔ **This half is the one that bites**, and its first version was paired
    // with a second that could not — see `labelViolations`. Group 1b is the replacement.
    let cases: [(surfaced: [String?], raw: Int, want: Clause)] = [
        ([], 0, .none),                                  // a bare page
        ([], -1, .blind),                                // dictionary out of reach
        (["Highlight"], -1, .blind),                     // blind outranks a visible mark
        ([], 1, .count),                                 // one annotation PDFKit hid
        (["Link"], 2, .count),                           // a link surfaced, something else did not
        (["Link"], 1, .none),                            // furniture, counted and surfaced
        (["Widget"], 1, .none),                          // a form field is not a reader's mark
        (["Highlight"], 1, .subtype),                    // the ordinary answer
        (["Link", "Ink"], 2, .subtype),                  // found past furniture
        (["Line"], 1, .subtype),                         // the deliberately-added subtype
        ([nil], 1, .nilType),                            // surfaced, unnameable
        ([nil, "Highlight"], 2, .subtype),               // both halves refuse: the concrete one wins
        (["Link", nil], 2, .nilType),                    // nil reached past furniture
        // ⛔ DECISIVENESS, and the pair that pins it. In the shipped predicate BOTH of
        // these return from the count clause, before the loop is entered. The first is
        // labelled `subtype` because removing that clause changes nothing — the
        // highlight refuses the page anyway — and the second `nilType` for the same
        // reason. Only a page nothing else refuses is `count`, which is what makes the
        // corpus histogram answer the queue item instead of double-counting.
        (["Highlight"], 3, .subtype),
        ([nil], 3, .nilType),
        // …and blind is the exception, unconditional: `(["Highlight"], -1)` above.
    ]
    for c in cases {
        let got = clauseOf(surfaced: c.surfaced, rawAnnots: c.raw)
        let shape = "\(c.surfaced.map { $0 ?? "nil" }) raw=\(c.raw)"
        check(got == c.want,
              "clause \(shape) — want \(c.want.rawValue), got \(got.rawValue)")
        // Group 1b — the same label against the LAWS the printed columns imply, which is
        // the check that runs on real pages too (exit 6). Independent of `clauseOf`: it
        // reads `rawAnnots`, the `nil` count and `copiedSubtypes` membership, never the
        // predicate's control flow.
        let broken = labelViolations(got, surfaced: c.surfaced, rawAnnots: c.raw)
        check(broken.isEmpty, "label laws broken on \(shape) (\(got.rawValue)): "
                              + broken.joined(separator: "; "))
    }

    // Group 1c — CAN THE LAWS FAIL? Force each label onto an input it is wrong for and
    // require a violation. Without this, `labelViolations` returning `[]` unconditionally
    // would leave group 1b green and exit 6 dead — which is precisely what the check it
    // replaced did, so this group is the lesson as a check.
    let wrongLabels: [(Clause, [String?], Int, String)] = [
        (.blind,   ["Highlight"], 1, "blind on a readable page"),
        (.count,   ["Highlight"], 1, "count where rawAnnots == surfacedN"),
        (.nilType, ["Highlight"], 1, "nilType with nothing unnamed"),
        (.subtype, ["Link"],      1, "subtype with no copied mark surfaced"),
        (.none,    ["Highlight"], 1, "none over a highlight"),
        (.none,    [],           -1, "none with an unreadable dictionary"),
        (.none,    [],            1, "none where rawAnnots > surfacedN"),
        (.none,    [nil],         1, "none over an unnamed annotation"),
        (.subtype, ["Highlight"], -1, "subtype where blind must win"),
    ]
    for (label, surfaced, raw, what) in wrongLabels {
        check(!labelViolations(label, surfaced: surfaced, rawAnnots: raw).isEmpty,
              "the label laws accept \(what) — they cannot fail, so group 1b and exit 6 are dead")
    }

    // Group 2 — TABLE COVERAGE, not non-vacuity: it can only fail if the case list above
    // shrinks, never on a change to `clauseOf`, because group 1's hand-written `want`s
    // already name all five values. Kept as a guard on the table, labelled honestly —
    // the adversarial review of this file's diff refused the "non-vacuity" claim.
    let wanted = Set(cases.map(\.want))
    for value in [Clause.blind, .count, .subtype, .nilType, .none] {
        check(wanted.contains(value), "no case in group 1 expects \(value.rawValue)")
    }

    // Group 3 — `spliceEligible`'s truth table against the quotation in the header.
    // CONTRIBUTING 4d: enumerate, do not reason about pairs. Three booleans, all eight
    // corners, plus the no-passthrough precondition.
    check(spliceEligible(pages: 10, passthrough: 0, outlineN: 0, docMark: false) == false,
          "a document with no born-digital page has nothing to splice")
    var corners = 0
    var spliced = 0
    for outline in [0, 5] {
        for mark in [false, true] {
            for (pages, pass) in [(10, 1), (3, 3)] {
                corners += 1
                let want = outline == 0 && !mark && pages > pass
                let got = spliceEligible(pages: pages, passthrough: pass,
                                         outlineN: outline, docMark: mark)
                if got { spliced += 1 }
                check(got == want,
                      "spliceEligible(pages: \(pages), passthrough: \(pass), outlineN: \(outline),"
                      + " docMark: \(mark)) — want \(want), got \(got)")
            }
        }
    }
    // The inverse row, in the only form that is not a duplicate of a corner above: the
    // table must contain a `true`, or a combiner that refuses everything satisfies all
    // eight. A first draft asserted the all-clear corner itself, which IS one of the
    // eight — the review of this diff caught it.
    check(corners == 8, "the truth table ran \(corners) corners, expected 8")
    check(spliced == 1, "\(spliced) of 8 corners splice, expected exactly 1")

    // Group 4 — the printer's width. ⚠️ `row()`'s own defence against a wrong-width data
    // row is a `precondition`, which traps rather than returns, so no check here can
    // drive it; what these two cover is the header staying 14 wide and tab-free.
    check(columns.count == 14, "columns is \(columns.count) wide, expected 14")
    check(row(columns).split(separator: "\t", omittingEmptySubsequences: false).count == columns.count,
          "the header does not round-trip through row()")

    // Group 5 — the set the label is read against is not empty or stripped of its
    // marks. A `copiedSubtypes` emptied by a bad edit would make every page read
    // `none`, and group 1's `subtype` cases are the only thing that would notice.
    check(Annotations.copiedSubtypes.contains("/Highlight"), "copiedSubtypes has lost /Highlight")
    check(Annotations.copiedSubtypes.count >= 15,
          "copiedSubtypes holds \(Annotations.copiedSubtypes.count), expected at least 15")
    check(!Annotations.copiedSubtypes.contains("/Link"), "/Link must not be a copied mark")
    check(!Annotations.copiedSubtypes.contains("/Widget"), "/Widget must not be a copied mark")

    selfTestChecks = checks
    return failures
}

/// How many checks the last `selfTest()` ran. A counter rather than a literal, because
/// `score-shape-term:996-999` records a printed literal going stale silently.
var selfTestChecks = 0

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

let arguments = Array(CommandLine.arguments.dropFirst())

// UNCONDITIONAL, before anything is measured: `score-mrc`, `score-threshold-loss`,
// `score-text-route`, `score-line-separation`, `score-routing-census`, `score-run-width`
// and `score-text-voids`' pattern — eight of the nine other Swift tools here with a
// self-test since `score-reading-order` gained one on 2026-08-26, ten in all,
// `score-shape-term` being the only flag-gated one. The reason is in
// `score-text-route:476-478` ("cheap enough to be unconditional") and it is stronger
// here, because this self-test is arithmetic over arrays of three elements. ⛔ **The gate
// that would otherwise run it does not exist**: the pre-commit hook runs `--self-test`
// for staged `Tools/*.py` only, so a flag-gated Swift self-test is type-checked by
// `check-tools-compile.sh` and never executed. A first version of this file was
// flag-gated; the adversarial review of its own diff refused it, citing that decision.
let selfTestFailures = selfTest()
if !selfTestFailures.isEmpty {
    FileHandle.standardError.write(Data(("score-annot-marks: self-test FAILED\n  "
        + selfTestFailures.joined(separator: "\n  ") + "\n").utf8))
    exit(5)
}
if arguments.contains("--self-test") {
    guard arguments.count == 1 else {
        FileHandle.standardError.write(Data("score-annot-marks: --self-test takes no paths\n".utf8))
        exit(2)
    }
    print("score-annot-marks: self-test ok (\(selfTestChecks) checks)")
    exit(0)
}
guard !arguments.isEmpty else {
    FileHandle.standardError.write(Data("""
        score-annot-marks: give it PDF paths, or --self-test.
          score-annot-marks <pdf> [<pdf> …]
        """.utf8))
    exit(2)
}

let password = ProcessInfo.processInfo.environment["PASSWORD"]

print(columns.joined(separator: "\t"))

var skipped: [String] = []
var disagreed: [String] = []
var docsSeen = 0
var docsSplice = 0
var docsOutline = 0
var docsMark = 0
var docsAllPass = 0
var clauseCounts: [Clause: Int] = [:]
var pagesSeen = 0

for path in arguments {
    let url = URL(fileURLWithPath: path)
    let name = clean(url.lastPathComponent)
    guard let document = Flattener.open(url, password: password) else {
        skipped.append("\(name): would not open")
        continue
    }
    let passthrough = Flattener.digitalTextPages(in: url, password: password)
    guard !passthrough.isEmpty else {
        skipped.append("\(name): no born-digital page")
        continue
    }
    let pages = document.pageCount
    let outlineN = SearchableWriter.readOutline(from: url, password: password).count
    let docMark = Annotations.anyCopiableMark(in: url, password: password, onPages: passthrough)
    let allPass = !(pages > passthrough.count)
    let splice = spliceEligible(pages: pages, passthrough: passthrough.count,
                                outlineN: outlineN, docMark: docMark)

    docsSeen += 1
    if splice { docsSplice += 1 }
    if outlineN > 0 { docsOutline += 1 }
    if docMark { docsMark += 1 }
    if allPass { docsAllPass += 1 }

    for page in passthrough {
        guard page >= 1, page <= pages, let subject = document.page(at: page - 1) else {
            skipped.append("\(name) p\(page): out of range")
            continue
        }
        let surfaced = subject.annotations.map(\.type)
        let raw = Annotations.rawAnnotationCount(of: subject)
        let clause = clauseOf(surfaced: surfaced, rawAnnots: raw)
        let pageMark = Annotations.pageCarriesMark(surfaced: surfaced, rawAnnotationCount: raw)
        // ⛔ The laws, not `(clause != .none) != pageMark` — that comparison re-evaluated
        // one pure function twice and could never differ, which is what made this exit
        // dead code in the first version. `labelViolations`' own comment carries the
        // 1,728-input probe that proved it.
        let broken = labelViolations(clause, surfaced: surfaced, rawAnnots: raw)
        if !broken.isEmpty {
            disagreed.append("\(name) p\(page) (\(clause.rawValue), rawAnnots=\(raw), "
                             + "surfacedN=\(surfaced.count)): " + broken.joined(separator: "; "))
        }
        clauseCounts[clause, default: 0] += 1
        pagesSeen += 1

        print(row([name,
                   "\(pages)",
                   "\(passthrough.count)",
                   "\(page)",
                   "\(raw)",
                   "\(surfaced.count)",
                   "\(surfaced.filter { $0 == nil }.count)",
                   surfaced.isEmpty ? "-" : surfaced.map { clean($0 ?? "?") }.joined(separator: ","),
                   clause.rawValue,
                   yn(pageMark),
                   yn(docMark),
                   "\(outlineN)",
                   yn(allPass),
                   yn(splice)]))
    }
}

let histogram = [Clause.blind, .count, .subtype, .nilType, .none]
    .map { "\($0.rawValue)=\(clauseCounts[$0] ?? 0)" }
    .joined(separator: " ")
print("""

    \(docsSeen) documents, \(pagesSeen) born-digital pages.
    refused by an outline: \(docsOutline); by a mark: \(docsMark); \
    by being all-passthrough: \(docsAllPass).
    eligible at the three cheap terms: \(docsSplice) of \(docsSeen).
    clause over the born-digital pages: \(histogram)
    """)

if !skipped.isEmpty {
    FileHandle.standardError.write(Data(("⛔ \(skipped.count) SKIPPED, and a population figure "
        + "above is a claim about the rest:\n  " + skipped.joined(separator: "\n  ") + "\n").utf8))
}
if !disagreed.isEmpty {
    FileHandle.standardError.write(Data(("⛔ \(disagreed.count) CLAUSE LABELS BREAK THE LAWS THEIR "
        + "OWN COLUMNS IMPLY — the tool is wrong and nothing above is usable:\n  "
        + disagreed.joined(separator: "\n  ") + "\n").utf8))
    exit(6)
}
if !skipped.isEmpty { exit(3) }
