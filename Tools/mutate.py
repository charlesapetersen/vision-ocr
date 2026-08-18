#!/usr/bin/env python3
"""Change something in Sources/ that ought to break a check, and see if one breaks.

Why this exists: **nine checks in this project's history have been unable to
fail.** T1's invariant-5 fixture passed twice against a deliberately reintroduced
bug, the crop-box test asserted a page size the bug could not move, and the
2026-08-09 rounds added six more — R25's depth fixture, U20's timing bound and
main-thread read, U20's clock comparison, U18's "normal case" that never entered
the function, C20's probe twice over. Every one was found by hand, by putting the
defect back and watching. CONTRIBUTING has said to do that since 1.0; doing it
reliably is what a person is worst at.

So: do it mechanically. Each mutant is a single edit that a *correct* suite
should notice. A mutant the suite still passes is either a gap in the checks or a
constant nothing depends on — and knowing which is which is the point.

    python3 Tools/mutate.py --list
    python3 Tools/mutate.py                  # the whole catalogue — SEE THE COST BELOW
    python3 Tools/mutate.py --only headroom  # one substring of the mutant id

**⚠️ THE WHOLE CATALOGUE IS HOURS, AND THE PER-RUN COST IS NOT A PROPERTY OF THE
SUITE.** Do not derive the figure and **do not read it from this header** — every
version of this paragraph that quoted a number went stale, twice within one day. The
startup line reads the range off `Tools/mutation-log.tsv`'s newest rows and prints it
before doing any work; that is the only figure here that tracks the machine. Want it
without starting a campaign: `python3 Tools/mutate.py --only nothing-matches-this`.
That prints the range and **stops**. It did neither until 2026-08-17: it printed no
numbers at all and then fell through to the rsync and a full baseline suite, so the
one command this header advertised as free cost ~45 minutes in a tool that does not
take `test-lock.sh`. `startup_line` is what stops it now. The self-test pins both halves — what
`startup_line` returns, and that `run` acts on it: a review mutated `if not proceed:` to
`if False:` and the harness stayed green, so the check that drives `run` with tripwires
over `subprocess.run`, `shutil.rmtree` and `os.makedirs` was added for exactly that.

**What the log established on 2026-08-17, and it is a fact about the machine rather
than the suite.** The C24b campaign's per-mutant rows came in at ~2700 s against
~630 s for the R56/R57 mutants recorded **that same morning** — 09:47, committed
09:59 in `41815b9`, about thirteen hours before the campaign started at 22:46, not
"the evening before" as three of this project's documents said — a 4.3x jump across
the five-row window the estimate spans, on a catalogue that grew by four checks
(1,137 to 1,141) in between. Four checks do not do that. So the sentence this
paragraph carried until then — "it grows every time the suite does" — was keyed on
the wrong variable. The clock matters to the argument and not only to the record:
quiet-morning against loaded-overnight is the comparison being drawn, and dating
the cheap rows to the evening puts both readings in the same half of the day.

**What is measured and what is inferred, kept apart.** Measured: the same five-mutant
catalogue recorded ~630 s and ~2700 s per run on the same machine hours apart, across
four checks of growth. Inferred from that: size cannot be the term that moves it, so
something outside the suite is. Reported by the session that ran the campaign, and NOT
re-observed here: `ps -r` during it showed OneDrive at ~50% of a core and CrashPlanService
at ~24%. The suite is single-core bound at ~96%, so anything else wanting that core lands
on it directly — which makes contention the plausible term, and a 1-minute load average
an insufficient covariate for it, since neither of those processes moves loadavg much.
Nobody has yet run the controlled experiment that would settle it.

Two consequences, both load-bearing:

  * **The printed estimate is a floor, not a forecast, and reading the log does not
    make it a forecast.** Budget its high end. The C24b campaign was announced as
    "20-55 minutes" by the hardcoded arithmetic this replaced and ran 267 minutes —
    4.85x the high end. But run against the log **as it stood when that campaign
    started** (74 rows, newest five 471-632 s) the fixed arithmetic here says
    **47-63 minutes, which is 4.22x low against the same 267**. Measured 2026-08-17,
    by driving these functions over `git show`'s copy of the pre-campaign log. So the
    fix removed a stale *constant*; it did not make the estimate survive a change in
    load, and nothing in this file can, because the term that moved is not in the log.
  * **A duration measured here is not a reading of the suite's size.** The rsync below
    excludes `testdocs`, and one draft of this paragraph argued from that exclusion
    that a mutation run must therefore be much *faster* than a full `./run_tests.sh`.
    It cannot be, and the exclusion is not why: **the suite is corpus-free.**
    `testdocs/` appears in `Tests/main.swift` in three comments and nowhere in
    `Sources/`, `Helper/` or `run_tests.sh` — the suite synthesises its own PDFs and
    OCRs those, and nothing runs the corpus on a commit (`ops/autonomous/README.md`
    says so under its ledger). So the rsync skips no check at all, and 2700 s here
    against 2370 s for a `pre-commit` suite the evening before is **one suite at two
    loads** — which is this paragraph's own argument, and stronger stated that way
    than as two different suites. An earlier draft went the other direction and
    multiplied the catalogue by the full-suite time to announce "~55 hours". Neither
    figure predicts the other, because neither was reading the variable that moves.

And two rows in the log are **not durations at all**, which is worth knowing before
reading it by hand: `logic/R24-safeInt-finite` at 80 s and `logic/R30-monotonic-
underflow` at 89 s are `exit 133` — SIGTRAP, a crash 80 and 89 seconds in
respectively. They are correctly scored as kills. `logged_seconds` excludes them, and
they are why it does not simply trust the seconds column.

Scope it with `--only`, always.

**Sequential on purpose**, and for a second reason besides the arithmetic: the
suite contains real timing assertions (the login-shell bounds, "came back
promptly"). Several suites at once make those flaky, and a flaky check reports a
mutant as KILLED when the suite merely tripped over the load — a false negative
in the one tool whose job is finding false negatives.

**⚠️ It does NOT take `ops/autonomous/test-lock.sh`.** It runs `./run_tests.sh`
directly in its copied tree, and a copy still shares
`~/Library/Preferences/tests.plist` with every other worktree — CLAUDE.md's first
environment trap. The lock's `pgrep -x tests` belt means other callers will yield
to a mutation run, but this tool will not yield to THEM: starting it while the
daemon's hook or health gate is mid-suite corrupts both. Check first
(`ops/autonomous/test-lock.sh status`) until this goes through the lock properly.

Runs against a **copy of the working tree**, so the tree itself is never touched
and an interrupted run leaves nothing behind. It copies what is on disk, not
`HEAD`: the first version used `git worktree add --detach HEAD` and cheerfully
reported eight survivors against the previous commit while the checks written to
kill them sat uncommitted three feet away. A tool that silently measures
something other than what you are holding is worse than no tool.

The baseline is run first and must be green; every verdict is relative to it, and
a mutant whose run reports a different number of checks than the baseline is
flagged rather than believed.

Results append to Tools/mutation-log.tsv; re-running skips mutants already
recorded, so a campaign can be stopped and resumed.
"""
import argparse, json, os, re, shutil, subprocess, sys, time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG = os.path.join(REPO, "Tools", "mutation-log.tsv")

# ---------------------------------------------------------------- the catalogue

# Constants whose doc comments say "measured" or "calibrated". If one of these
# can be moved without a check going red, either the calibration is unguarded or
# the constant does not matter — both worth knowing. The replacement is a
# *meaningful* perturbation, not a rounding: enough to change behaviour a person
# would notice, so a survivor cannot be blamed on the step being too small.
CONSTANTS = [
    # SearchableWriter — the text layer, invariant 3's four properties
    ("SearchableWriter.swift", "baselineFraction", "0.22", "0.40"),
    ("SearchableWriter.swift", "headroomFactor", "1.5", "0.95"),
    ("SearchableWriter.swift", "reserveEms", "0.25", "0.0"),
    ("SearchableWriter.swift", "minimumVertical", "0.25", "0.5"),
    ("SearchableWriter.swift", "sameLineBaselineFraction", "0.4", "0.05"),
    # 1.0, not 0.9: `shared` can never exceed the narrower box, so 1.0 is not a
    # loose threshold — it is the code before R81, admitting every box that
    # starts right of my left edge. The mutant puts A1.2 back exactly.
    ("SearchableWriter.swift", "sharedInkFraction", "0.5", "1.0"),
    ("SearchableWriter.swift", "duplicateBaselineFraction", "0.3", "1.0"),
    ("SearchableWriter.swift", "maximumOutlineDepth", "32", "4000"),
    # Rejoining words broken across a line. edgeOfPage was guessed at 0.18 and
    # admitted nothing — the deepest hyphenated line measured sits at 0.82 and
    # 1 - 0.18 is exactly 0.82 — so it is now measured, and worth guarding.
    ("SearchableWriter.swift", "edgeOfPage", "0.25", "0.02"),
    # -1.0, not 0.0: two columns do not merely fail to overlap, they overlap
    # *negatively*, so a floor of zero still refuses them and the mutant
    # survived while testing nothing.
    ("SearchableWriter.swift", "minimumColumnOverlap", "0.6", "-1.0"),
    ("SearchableWriter.swift", "continuationCandidates", "3", "1"),
    ("Model.swift", "sizeNoteRatio", "1.25", "99.0"),
    # Flattener — routing, resolution and the crash guards
    ("Flattener.swift", "pictureInkThreshold", "0.15", "0.9"),
    ("Flattener.swift", "pictureToneThreshold", "0.12", "0.9"),
    # R38's gate. 0.0, not a large value: the defect it closes is the gate being
    # *absent*, and setting the minimum to zero is exactly the absent gate —
    # every ink-triggered page becomes a picture again, including the four that
    # inflated up to 9.45x. A large value tests the opposite failure and the
    # catalogue wants the one the register records.
    ("Flattener.swift", "pictureInkMinimumTone", "0.03", "0.0"),
    ("Flattener.swift", "pictureSaturationThreshold", "0.06", "0.9"),
    # R56 / R57, the shape signals. Each mutant is the *defect*, not an arbitrary
    # perturbation, which is the rule R38's entry above sets out.
    #
    # `minimumMarkContrast` at 4.0 is the degenerate floor put back: on a scan whose
    # white is clipped the spread of the paper peak is 0.0, so `paper - 4` is what
    # the rule reduced to before this constant existed — and it read 228 of
    # `Himanen_2001`'s 255 pages as carrying pale content.
    ("Flattener.swift", "minimumMarkContrast", "24.0", "4.0"),
    # 0.9 makes both pale fixtures text again, which is R56 itself. The catalogue
    # said 0.006 against a source declaring 0.012, so it was NOT-APPLIED and the one
    # constant that decides R56's verdict had no live mutant — caught by the review of
    # the diff that added it, and the reason `mutate.py` prints NOT-APPLIED at all.
    ("Flattener.swift", "paleDrawingThreshold", "0.05", "0.9"),
    # R56's discriminator, and the fixtures **cannot** kill it: `pale-drawing` sits on
    # bare paper and reads the same at every value including zero. `pale-chart` is the
    # fixture that can — its axis numerals are inside the plot frame — and it is here
    # for that reason. 0.0 refuses every mark with any of the page's ink under it.
    ("Flattener.swift", "maximumInkUnderADrawing", "0.05", "0.0"),
    # The analysis resolution. 20 cells an inch is below the floor the whole signal
    # rests on, and the constant's own comment is three paragraphs about why.
    ("Flattener.swift", "markCellsPerInch", "150.0", "20.0"),
    # The quarter inch that separates a drawing from show-through. Large, so every
    # pale mark is type-sized and the drawing is never found.
    ("Flattener.swift", "typeCeilingInches", "0.25", "99.0"),
    # A drawing is a stroke; shading is a filled block. At 0.0 nothing is a drawing.
    ("Flattener.swift", "solidMarkFill", "0.6", "0.0"),
    # 0.9 means no component is ever big enough to have its own tone asked about,
    # which is R57 restored.
    ("Flattener.swift", "largeMarkShare", "0.02", "0.9"),
    # …and its partner. 0.0 admits a page *frame* as a plate and then measures the tone
    # of the type it encloses — the defect the review of R57's diff measured at 1.54x
    # the whole-sheet figure, not an arbitrary perturbation.
    ("Flattener.swift", "minimumPlateFill", "0.25", "0.0"),
    # The paper-colour estimate. Drop the floor and every dark pixel counts as
    # paper, so the "paper" is the page mean and the correction removes whatever
    # cast the *content* had; raise the fraction and the correction never runs at
    # all, which is the 709 MB behaviour restored.
    ("Flattener.swift", "paperLuminanceFloor", "176.0", "10.0"),
    ("Flattener.swift", "minimumPaperFraction", "0.15", "0.99"),
    # Layering holds ~8 bytes a pixel against the render's 5.5, so it needs its
    # own bound. R29 is what happens when a sibling allocation does not get one.
    ("Flattener.swift", "maximumMRCPageMegapixels", "100", "40000"),
    # A3.1's colour bound. Derived from the other three constants, so the check
    # that guards it asserts the derivation rather than the literal — and a
    # mutant is the only thing that says the derivation is load-bearing.
    ("Flattener.swift", "maximumColourMRCPageMegapixels", "88", "40000"),
    # A11.5. The third arithmetic-over-constants pair, which was not in this
    # catalogue at all: `colourBoundIsWithinTheGreyOne` over the colour render
    # bound. Colour holds three planes where grey holds one, and the property is
    # that colour cannot reach a high-water mark grey could not already.
    ("Flattener.swift", "maximumColourPageMegapixels", "100", "40000"),
    ("Flattener.swift", "minimumPlausibleScanDPI", "150", "10"),
    ("Flattener.swift", "fallbackRebuildDPI", "300", "72"),
    ("Flattener.swift", "minimumScanPixelWidth", "600", "10"),
    ("Flattener.swift", "maximumPageMegapixels", "400", "40000"),
    ("Flattener.swift", "maximumDeclaredImageSide", "200_000", "20_000_000_000"),
    ("Flattener.swift", "maximumThumbnailEdge", "4_000", "4_000_000"),
    # R40. The bound on a silent helper. Made small rather than large: the
    # failure worth guarding is the app giving up on a helper that is merely
    # working, which sends every document round a second time in-process and
    # hands back exactly the 2.5x R40 exists to remove. The parity check notices,
    # because it asserts recognition did *not* fall back.
    ("Recogniser.swift", "helperStallSeconds", "900.0", "0.001"),
]


# Single-token logic edits in code written to close a defect. Each one undoes a
# specific decision the register records, so each SHOULD be caught.
OPERATORS = [
    # Two sites, identical text: readOutline's convert and copyOutline's
    # rebuild. One pattern covered both and silently mutated only the first, so
    # R23's own mirror — the whole point of R23 — was never perturbed (T7). Each
    # is now anchored to its function's return type.
    ("SearchableWriter.swift",
     "-> OutlineItem? {\n            guard depth < maximumOutlineDepth, budget > 0 else { return nil }",
     "-> OutlineItem? {\n            guard depth < 4_000_000, budget > 0 else { return nil }",
     "R19-readOutline-bound"),
    ("SearchableWriter.swift",
     "-> PDFOutline? {\n            guard depth < maximumOutlineDepth, budget > 0 else { return nil }",
     "-> PDFOutline? {\n            guard depth < 4_000_000, budget > 0 else { return nil }",
     "R23-copyOutline-bound"),
    ("SearchableWriter.swift", "guard !isSameVisualLine(me, other, in: box) else { continue }",
     "if false { continue }", "C20-headroom-sameline"),
    ("SearchableWriter.swift",
     "guard isSameVisualLine(me, other, in: box, .taller) else { continue }",
     "if false { continue }", "C20-rightlimit-sameline"),
    # R82. The scale the reserve asks for, put back to the one that welded. Not a
    # constant, so it cannot live in CONSTANTS — and the entry above had to be
    # re-anchored when the argument appeared, or it would have gone on reporting
    # NOT APPLIED over a line it no longer matched.
    ("SearchableWriter.swift",
     "guard isSameVisualLine(me, other, in: box, .taller) else { continue }",
     "guard isSameVisualLine(me, other, in: box, .shorter) else { continue }",
     "R82-reserve-taller-scale"),
    # `guard true else` is a compile error in Swift, so the removal has to be
    # spelled as a no-op branch. The first attempt was recorded INVALID, which is
    # the harness reporting honestly rather than scoring an untested mutant.
    ("Flattener.swift", "guard value.isFinite else { return 0 }",
     "if !value.isFinite && false { return 0 }", "R24-safeInt-finite"),
    # MRC. The stencil polarity cannot be reasoned out from the specification —
    # inverted, the foreground shows everywhere except the text and the page
    # floods solid, which no page count can see. In OPERATORS rather than
    # CONSTANTS because the constant pattern anchors on \b, which cannot match
    # after a closing quote: the first attempt was recorded NOT-APPLIED, the
    # harness declining to score a mutant it had not actually planted.
    ("JBIG2.swift", 'static let maskDecode = "[ 1 0 ]"',
     'static let maskDecode = "[ 0 1 ]"', "mrc-stencil-polarity"),
    # R39's mutant lived here, and it is gone with the code it perturbed: the
    # DPI negotiation existed only to talk to a subprocess that re-rasterised our
    # PDF, and recognition is in process now. Its replacement is the language
    # detection flag, which is the one request property where *leaving it alone*
    # is wrong — with no language named, Vision falls back to a default list
    # instead of detecting, which no character count on English material would
    # notice.
    # R40. Which batches get helper processes. Widened rather than removed: a
    # helper for a single file is the case the measurement rejected — it pays
    # Vision's ~0.20s start-up twice and overlaps with nothing — and "always on"
    # is the mistake a reader of this code is most likely to make.
    ("Recogniser.swift", "concurrency > 1 && files > 1", "concurrency > 0 && files > 0",
     "R40-helper-eligibility"),
    ("Recogniser.swift",
     "request.automaticallyDetectsLanguage = languages.isEmpty",
     "request.automaticallyDetectsLanguage = false",
     "detects-language-when-none-named"),
    # R38. The gate itself, not its constant. The drift guard in T5 kills any
    # edit to `pictureInkMinimumTone` for free — it asserts the literal — so a
    # constant mutant proves nothing about whether anything *reads* it. This one
    # plants the original defect: ink alone routes a page to pictures again.
    ("Flattener.swift", "if tone > pictureInkMinimumTone,\n           inkCoverage(",
     "if true,\n           inkCoverage(", "R38-ink-needs-tone"),
    ("Flattener.swift", "if let seen = walkedAt[identity], seen <= depth { return }",
     "if walkedAt[identity] != nil { return }", "R25-depth-aware-prune"),
    # R56's second half, and the one a constant mutant cannot reach. Closing R56 in
    # `isPicture` alone would have moved the harm rather than removed it: the page
    # reaches the picture path and `mrcLayers` then stores it at an eighth of its
    # resolution, because the all-text rule's signal is ink and the drawing is not
    # ink. This plants that back — the sibling defect, not the reported one
    # (CONTRIBUTING 4b).
    ("Flattener.swift",
     "dpi: dpi).extent <= paleDrawingThreshold",
     "dpi: dpi).extent <= 99.0", "R56-alltext-sees-drawings"),
    # R57's mechanism rather than its constant: tone asked about the whole sheet
    # again instead of the region the tone is in. This is the entry's own diagnosis —
    # "a plate over a fifth of a page dilutes its own tone by five" — planted.
    ("Flattener.swift",
     "        if largeMarkTone(marks, grey: grey, width: width, height: height,\n"
     "                         threshold: threshold) > pictureToneThreshold",
     "        if toneFraction(of: grey, threshold: threshold) > pictureToneThreshold",
     "R57-tone-of-the-region"),
    # C24's structural half. The mutant is the defect: a page that draws nothing is
    # told its resolution by whatever the shared /Resources can reach. Not a constant —
    # the whole point of this repair is that it needs none, which is why the entry's
    # first two attempts died.
    ("Flattener.swift", "guard drawsAnyXObject(page) != false else { return nil }",
     "guard true else { return nil }", "C24-page-draws-nothing"),
    # …and the half of it that is about the *instrument*: `nil` means "could not tell"
    # and must behave as before. Reading it as "draws nothing" would refuse the image
    # on any page whose content stream the scanner could not read — losing detail on a
    # real scan to fix a byte problem, which is the wrong direction (T14).
    ("Flattener.swift", "return seen.operators > 0 ? false : nil",
     "return false", "C24-unknown-is-not-no"),
    # C24's open half, as a measurement: `drawnLargestImage`. Five mutants — the sixth and
    # seventh tuples below, `C24-override-ignored` and `C24-override-nil-means-fallback`, are
    # later additions about the measurement *seam* and are not among these five. Five because the
    # entry's two refused repairs each died on a *different* one of these branches, and a
    # constant mutant can reach none of them — the whole claim of this walk is that it
    # needs no constant.
    #
    # Repair 2 died here. A walk that does not scan a form's own content stream reports
    # "draws no image" on the 114 of 114 pages of `Lyons oral history` whose scan sits one
    # level down inside a form, which is what scanner drivers routinely produce.
    ("Flattener.swift", "guard s.depth < 3, let table = s.table else { return }",
     "guard s.depth < 0, let table = s.table else { return }",
     "C24b-form-not-followed"),
    # …and the narrower version of the same blindness: a form is followed, but only when it
    # carries `/Resources` of its own. PDF resolves a bare form's names in the scope that
    # invoked it, and dropping that fallback loses the image again.
    ("Flattener.swift",
     "let resources = formResources ?? inherited ?? streamDict",
     "guard let resources = formResources else { return }",
     "C24b-bare-form-resources"),
    # The scope must *descend*. Without this assignment a bare form nested inside a form
    # that carries its own `/Resources` resolves against the page rather than its invoker,
    # which is what the first version of this walk did and what the ninth page of
    # `shared-resources.pdf` exists to see. `_ = resources` rather than a deletion, so the
    # mutant is a behaviour change and not a compile error — mutate.py scores those
    # differently and a NOT-APPLIED verdict would tell us nothing about the checks.
    ("Flattener.swift", "                s.resources = resources\n",
     "                _ = resources\n", "C24b-scope-does-not-descend"),
    # T14's rule at a new site, in the direction that costs detail: reading "draws no
    # image" as "could not tell" makes the measurement useless — every page would fall back
    # to the `/Resources` answer, which is the defect this function exists to measure.
    ("Flattener.swift", "guard state.width > 0 else { return .noImage }",
     "guard state.width > 0 else { return .unreadable }",
     "C24b-no-image-is-not-unknown"),
    # …and the same rule in the direction that costs bytes and content: a `Do` whose name
    # will not resolve reported as "draws nothing". Anchored on the line above because the
    # same assignment guards three branches, and T7 is what an ambiguous pattern costs.
    ("Flattener.swift",
     "                  let object = CGPDFContentStreamGetResource(cs, \"XObject\", name) else {\n"
     "                s.unreadable = true",
     "                  let object = CGPDFContentStreamGetResource(cs, \"XObject\", name) else {\n"
     "                s.unreadable = false",
     "C24b-unresolved-name-is-not-nothing"),
    # The measurement seam C24b's blocker needed, ignored. `rebuildDPIOverride` is `nil` in
    # the app, so this mutant cannot change a single published byte — what it breaks is the
    # instrument, and an instrument that silently reports the shipped resolution under every
    # override prints one row per candidate with the same number in each and reads as
    # "resolution makes no difference on this page". That is the false-green shape this
    # register has paid for ten times. `_ = ` rather than a deletion so it is a behaviour
    # change and not a compile error. Killed by the enumerated doors: `rebuildDPI` itself,
    # `flatten`'s raster, `Recogniser.render`'s and `mrcLayers`' layer widths.
    ("Flattener.swift",
     "        if let override = rebuildDPIOverride, let answer = override(page) { return answer }\n",
     "        _ = rebuildDPIOverride\n",
     "C24-override-ignored"),
    # The *nearer* wrong implementation, and the one nine checks could not see: `nil` from the
    # closure read as "use the fallback" rather than "no opinion about this page". It survived
    # every row written on 2026-08-17 because the only declined page in that fixture is the one
    # whose shipped answer already IS the fallback, so all nine agreed with it — found by an
    # adversarial review, not by this tool, because nothing had encoded it. Killed now by the
    # inverted-closure rows and, as far as the checks go, by nothing else. Both tuples are worth
    # keeping: `C24-override-ignored` says the hook is read at all, this one says its `nil`
    # means what its doc comment at `Flattener.swift` says it means.
    ("Flattener.swift",
     "        if let override = rebuildDPIOverride, let answer = override(page) { return answer }\n",
     "        if let override = rebuildDPIOverride { return override(page) ?? fallbackRebuildDPI }\n",
     "C24-override-nil-means-fallback"),
    # C24's wiring, closed 2026-08-17: the whole defect put back. `rebuildDPI` applying the
    # shipped policy to the `/Resources` walk instead of the drawn one is what sent 45 corpus
    # pages to a *neighbour's* plate resolution. Run by hand before it was catalogued — a
    # scratch copy of `Sources/` plus an extracted single-section probe — and the three rows
    # it kills are the 600 px page, the logo page and the empty-form page.
    ("Flattener.swift",
     "        case .unreadable: return rebuildDPI(from: largestImage(of: page))\n"
     "        case .noImage: return rebuildDPI(from: nil)\n"
     "        case let .largest(dpi, pixelWidth):\n"
     "            return rebuildDPI(from: (dpi: dpi, pixelWidth: pixelWidth))\n",
     "        case .unreadable, .noImage, .largest:\n"
     "            return rebuildDPI(from: largestImage(of: page))\n",
     "C24-rebuild-reads-dictionary"),
    # T14's rule at the *caller*, in the direction that costs content: a `Do` this could not
    # resolve read as "there is no image", which refuses a real scan's resolution on the
    # strength of a failed read. 3 corpus pages, all of `Astin__The Challenge of Open
    # Admissions`. Anchored on the one arm so the mutant is a behaviour change.
    ("Flattener.swift",
     "        case .unreadable: return rebuildDPI(from: largestImage(of: page))\n",
     "        case .unreadable: return rebuildDPI(from: nil)\n",
     "C24-rebuild-unreadable-is-nothing"),
    # The policy handed the drawn DPI but not the drawn *width*, so `minimumScanPixelWidth`
    # judges a number no page measured. Every page of `shared-resources.pdf` but the tenth
    # ends in a resolution the policy already trusts, which is why that page was added with
    # this wiring: on the other nine this mutant answers identically. Run by hand before it
    # was catalogued and it takes **three** rows red — the tenth page's, plus two C9 rows on
    # `born.pdf`, whose 16 px logo reaches the same branch. So this one was already reachable;
    # what the tenth page adds is a page where the two walks *disagree* and the answer turns
    # on the width, which is `AI 2027` p1's shape and 1 of the 45 the wiring moves.
    ("Flattener.swift",
     "        case let .largest(dpi, pixelWidth):\n"
     "            return rebuildDPI(from: (dpi: dpi, pixelWidth: pixelWidth))\n",
     "        case let .largest(dpi, _):\n"
     "            return rebuildDPI(from: (dpi: dpi, pixelWidth: Int.max))\n",
     "C24-rebuild-width-invented"),
    ("Model.swift", "guard !isCommitted else { return .refusedRunInProgress }",
     "guard !isRunning else { return .refusedRunInProgress }", "U19-add-guard"),
    # A5.3. The interlock as a flag again: the first walk to land lowers it while
    # the others are still going. Run by hand before the catalogue got it: the
    # two-import check goes red, and it is order-independent, so it is not a race.
    ("Model.swift", "self.importsInFlight = max(0, self.importsInFlight - 1)",
     "self.importsInFlight = 0", "A5.3-import-count"),
    # A5.3's other half: the interlock enforced only where the button is drawn.
    ("Model.swift",
     "guard !files.isEmpty, !isRunning, !isPreflighting, !isImporting else { return }",
     "guard !files.isEmpty, !isRunning, !isPreflighting else { return }",
     "A5.3-start-checks-importing"),
    ("Model.swift", "guard !isCommitted, !isImporting else { return false }",
     "guard !isCommitted else { return false }", "A5.3-clearFiles-importing"),
    # A5.2. The put-back that never ran. Removing the restore leaves the model
    # gutted after a pre-flight Cancel, under a log line saying nothing changed.
    ("Model.swift", "                    self.abandonRetry()\n                }",
     "                    self.continuesRetryChain = false\n                }",
     "A5.2-cancel-puts-back"),
    # T10 / A11.1. The tenth un-failable check guarded exactly this, and deleting
    # the gate it named left the suite 862/862 green. Run by hand before the
    # catalogue got it: 3 checks red, and the good file at the destination went
    # from 107,847 bytes to 809.
    ("Model.swift",
     "        if let refusal = incompleteRefusal(staged, expecting: expected) {\n"
     "            throw Failure.incompleteResult(refusal)\n        }\n"
     "        try publish(staged, to: output)",
     "        try publish(staged, to: output)", "A11.1-publishVerified-gate"),
    # R60. Content destruction: without the carried-forward reservations a retry
    # claims the path the batch it came from reserved away from it. The unit checks
    # pass `alsoClaimed`/`releasing` explicitly and would survive this, which is
    # why the end-to-end check exists — it is what goes red, on the user's file.
    ("Model.swift", "alsoClaimed: claimedByEarlierAttempts, releasing: releasing)",
     "alsoClaimed: [], releasing: [])", "R60-retry-reservations"),
    # A8.1. The setting unwired: the transplant runs whatever the user chose. Every
    # other annotation check calls transplant directly, so before A8.1's checks this
    # mutant would have survived a full suite - which is exactly H1's shape, a switch
    # in the panel that does nothing.
    ("Model.swift", "            if settings.preserveAnnotations {",
     "            if true {", "A8.1-preserveAnnotations-gates"),
    ("Model.swift", "defer { self.isPreflighting = false }",
     "self.isPreflighting = false", "U21-committed-across-alert"),
    # R63. A cancelled file reported as a failure again: red rows, "Cancelled." as
    # the reason it failed, counted as failures in the report, and left in
    # failedFiles for Retry Failed to offer.
    ("Model.swift",
     "        cancelled ? (.cancelled, \"Cancelled.\") : (.failed, error.localizedDescription)",
     "        (.failed, error.localizedDescription)", "R63-cancel-is-not-a-failure"),
    # A2.2's text half. Without this the cancelled run's text replaces the previous
    # run's output at the user's own destination - invariant 2, on the one route
    # that writes there directly.
    ("Recogniser.swift",
     "        if isCancelled() { throw Failure.cancelled }\n"
     "        try Data(body.utf8).write(to: target, options: .atomic)",
     "        try Data(body.utf8).write(to: target, options: .atomic)",
     "A2.2-text-cancel-before-write"),
    # A13.3. The newline guard back to "\n" only, so a path ending in CR passes it
    # and merges with the manifest separator into one Character.
    ("Recogniser.swift",
     "        guard !images.contains(where: {\n"
     "            $0.path.rangeOfCharacter(from: .newlines) != nil\n        }) else {",
     "        guard !images.contains(where: { $0.path.contains(\"\\n\") }) else {",
     "A13.3-newline-guard-is-every-newline"),
    # A13.2. A document Vision read nothing from publishing silently again.
    ("Model.swift", "            if byPage.values.allSatisfy(\\.isEmpty) {",
     "            if false, byPage.values.allSatisfy(\\.isEmpty) {",
     "A13.2-empty-document-says-so"),
    # A13.1, and this one's verdict needs reading rather than trusting. Without the
    # guard, a NUL with anything after it makes `Process.arguments` raise
    # NSInvalidArgumentException - not a Swift error, so the do/catch around
    # process.run() cannot catch it: SIGABRT, exit 134, and in the app the whole
    # batch with every concurrent file in it. A NUL in the *final* position does not
    # raise; it silently truncates the value instead. So the run produces one FAIL
    # line (from a truncating case) and then dies (on an embedded one), and
    # `killed` here means both things. mutation-out/ has the output.
    ("Recogniser.swift",
     "        guard !settings.languages.utf8.contains(0),\n"
     "              !settings.customWords.utf8.contains(0) else {\n"
     "            throw HelperFailure.unusableSettings\n        }",
     "        // guard removed by mutation", "A13.1-nul-in-settings"),
    # A10.1. The predicate back to the panel's old opinion of it: in Extract Text
    # the question then depends on a toggle that mode does not have, which is how a
    # dismissed alert became unreachable and Extract Text silently OCR'd a picture
    # of good text.
    ("Model.swift", "        case .text: return true",
     "        case .text: return rebuildImages", "A10.1-warn-applies-in-text"),
    # A10.1's other half: the alert naming a harm that cannot happen in that mode.
    ("Model.swift", "        let harm = mode == .text",
     "        let harm = false && mode == .text", "A10.1-alert-wording-by-mode"),
    # A4.2. The update URL unvalidated again, so the response body chooses what the
    # Download button opens - file:// and any registered scheme handler included.
    ("Updater.swift", "              isOfferableURL(url) else { return .unreadable }",
     "              true else { return .unreadable }", "A4.2-update-url-scheme"),
    # A10.3. Newspaper's blurb claiming a behaviour that is the registered default,
    # over values byte-identical to Book scan's.
    ("Prefs.swift",
     "                return \"Dense columns on poor paper — the settings this app already \"\n"
     "                     + \"defaults to, which suit newsprint as they come.\"",
     "                return \"Dense columns on poor paper. Keeps every uncertain word, \"\n"
     "                     + \"because a rough guess at a smudged word is still findable.\"",
     "A10.3-newspaper-blurb"),
    # R64 / A4.1. Puts the document's own text back into the message that goes into
    # a file the user is invited to mail to someone. Run by hand before the
    # catalogue got it: 2 checks red, and the failure detail printed the excerpt.
    ("Model.swift", '.map { "p\\($0.page) (\\($0.reason))" }',
     '.map { "p\\($0.page) \\"\\($0.text.prefix(24))\\" (\\($0.reason))" }',
     "A4.1-unplaced-carries-text"),
    ("Runner.swift", "guard deadline > now else { return 0 }",
     "guard true else { return 0 }", "R30-monotonic-underflow"),
    # A9.3. stop() giving up on an exited child again, so the grandchild holding the
    # pipe is stranded - one per tool name per Settings open, since SettingsView
    # calls forgetToolPaths() on every appear.
    ("Runner.swift",
     "        guard process.isRunning else {\n"
     "            // The child is gone; anything it started and left holding the pipe is\n"
     "            // not. Killing an empty group is a no-op, so this costs nothing when\n"
     "            // the child really did clean up after itself.\n"
     "            if let knownGroup { kill(-knownGroup, SIGKILL) }\n"
     "            return\n        }",
     "        guard process.isRunning else { return }", "A9.3-stop-collects-the-group"),
    # A9.6. The accumulator unbounded again: bounded in time, unbounded in memory.
    ("Runner.swift", "            if data.count >= byteCap { overflowed = true; return }",
     "            if false { overflowed = true; return }", "A9.6-capture-byte-cap"),
    # A9.7. Ask-then-write, so two concurrent writers are both told the name is free
    # and one atomic write replaces the other's report.
    ("RunReport.swift", "                let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)",
     "                let fd = FileManager.default.fileExists(atPath: url.path)\n"
     "                    ? -1 : open(url.path, O_WRONLY | O_CREAT, 0o644)",
     "A9.7-report-name-is-exclusive"),
    # A9.1. Trim the whole output again, so one line from a login startup file
    # hides an installed jbig2/qpdf for the rest of the session - and the nil is
    # memoised, so it is every batch until the app is relaunched.
    ("Runner.swift",
     "        let path = out.split(whereSeparator: \\.isNewline).last\n"
     "            .map(String.init)?.trimmingCharacters(in: .whitespaces) ?? \"\"",
     "        let path = out.trimmingCharacters(in: .whitespacesAndNewlines)",
     "A9.1-loginshell-last-line"),
    # A9.2. The report's JBIG2 row back to the checkbox. Three of the four states
    # that reach it then say "on" about a step that did not run.
    ("RunReport.swift",
     "            rows.append((\"JBIG2 compression\", {\n"
     "                guard c.settings.useJBIG2 else { return \"off\" }",
     "            rows.append((\"JBIG2 compression\", {\n"
     "                guard false else { return c.settings.useJBIG2 ? \"on\" : \"off\" }",
     "A9.2-jbig2-row-is-the-route"),
    # The bundled compression tools are single-architecture, so this check is
    # what keeps an arm64-only jbig2 from being handed to an Intel Mac.
    ("Runner.swift", "return isRunnable(path) && containsNativeSlice(path) ? path : nil",
     "return isRunnable(path) ? path : nil", "bundle-arch-check"),
    ("Runner.swift", "case 0xcffa_edfe, 0xcefa_edfe:                     // little-endian file\n            return word(4, bigEndian: false) == native",
     "case 0xcffa_edfe, 0xcefa_edfe:\n            return word(4, bigEndian: true) == native", "bundle-arch-endianness"),
    # R61. The two conversions safeInt did not cover, and the two clamps around
    # them. Each of these four plants a *trap*, so the check that dies is the
    # `--probe-hostile-numbers` child — which is the point of running the hostile
    # calls out of process: a mutant that takes the suite down instead of failing
    # a check is a mutant whose verdict nobody can read.
    ("Flattener.swift", "let quarterInch = safeInt(dpi / 4)",
     "let quarterInch = Int(dpi / 4)", "A7.1-sauvola-window-safeint"),
    # The fix must not also be a threshold change. This mutant is the first version
    # of the fix as written, caught in review: rounding moves the shipped window by a
    # pixel on about half of all pages, which no trap test would ever notice.
    ("Flattener.swift", "let quarterInch = safeInt(dpi / 4)",
     "let quarterInch = safeInt((dpi / 4).rounded())", "A7.1-sauvola-window-truncates"),
    ("Flattener.swift", "return min(max(quarterInch, 3), ceiling)",
     "return max(quarterInch, 3)", "A7.1-sauvola-window-ceiling"),
    ("Flattener.swift", "let r = min(max(window / 2, 1), max(w, h))",
     "let r = max(window / 2, 1)", "A7.1-sauvola-radius-bound"),
    ("Flattener.swift",
     "guard b.x.isFinite, b.y.isFinite, b.width.isFinite, b.height.isFinite\n            else { continue }",
     "if false { continue }", "A3.2-textregion-finite"),
    # R62. Numerator and denominator from one population. The mutant restores the
    # 10.0-coverage version, which no page count and no routing decision on today's
    # callers would notice — which is why it is here rather than trusted to a
    # caller that happens to protect it.
    ("Flattener.swift", "let pixels = min(grey.count, width * height)",
     "let pixels = grey.count", "A7.2-inkcoverage-population"),
]


def catalogue():
    out = []
    for f, name, old, new in CONSTANTS:
        out.append({
            "id": f"const/{name}", "file": f, "kind": "constant",
            # Anchored to the declaration so a bare number elsewhere is not hit.
            "pattern": rf"(static (?:var|let) {re.escape(name)}[^=\n]*=\s*){re.escape(old)}\b",
            "replacement": rf"\g<1>{new}",
            "note": f"{old} -> {new}",
        })
    for f, old, new, label in OPERATORS:
        out.append({
            "id": f"logic/{label}", "file": f, "kind": "logic",
            "pattern": re.escape(old), "replacement": new.replace("\\", "\\\\"),
            "note": label,
        })
    return out


# ------------------------------------------------------------------- the runner

def already_done(path=None):
    """`{mutant id: verdict}` for rows this tool wrote. Exact field count, like
    `logged_seconds` — and for the same reason, found by asking who else parses this
    log with a lower bound.

    This read `len(parts) >= 2` while the docstring below called that pattern a defect
    three times over (T14, A12.3, T18). It is the more expensive one of the two, not
    the cheaper: a malformed row accepted here means a mutant **treated as already
    recorded and never run**, which is a silent gap in the gate. Refusing it costs one
    re-run of a mutant, ~45 minutes — and one thing it DOES report falsely, which is
    worth knowing before widening the guard again: `run`'s closing "never applied, so
    nothing is known about them" line is computed from this dict, so a refused row makes
    a mutant that *has* a verdict on disk read as one that has none. The trade is
    deliberate (a duplicate row and a wrong "never applied" beat a mutant silently
    counted as gated), and `record` writes four fields, so no row on disk hits it today. `record` writes exactly
    four fields, so four is the count; all 79 rows of the log on disk have four, so this
    changed no verdict when it landed.

    Takes `path` so the self-test can drive it. It did not, which is why nothing checked
    it — the whole reason `logged_seconds` grew the same parameter.
    """
    p = path or LOG
    if not os.path.exists(p):
        return {}
    done = {}
    with open(p) as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) == 4 and parts[0] != "mutant":
                done[parts[0]] = parts[1]
    return done


def record(mid, verdict, seconds, detail):
    # Empty counts as new, not just absent. Truncating the log to start a fresh
    # campaign (`: > Tools/mutation-log.tsv`) left it headerless, so the first
    # record looked like the header to anything reading it with `tail -n +2`.
    new = not os.path.exists(LOG) or os.path.getsize(LOG) == 0
    with open(LOG, "a") as fh:
        if new:
            fh.write("mutant\tverdict\tseconds\tdetail\n")
        fh.write(f"{mid}\t{verdict}\t{seconds:.0f}\t{detail}\n")


# Only a real verdict counts as done. Treating any logged row as recorded meant a
# mutant whose pattern stopped matching after a refactor was skipped for ever, and
# every later run printed a clean bill of health for a catalogue it had quietly
# stopped applying (T7). Module scope so the estimate and `--self-test` can reach it.
VERDICTS = ("SURVIVED", "killed")

# Which verdicts stand behind a suite that actually ran to completion, which is a
# DIFFERENT question from `VERDICTS`' "counts as done, do not run it again". MISMATCH
# is the one that separates them: the mutant compiled, the suite ran end to end and
# printed a total, and only the check *count* differed from the baseline — so the
# verdict means nothing but the duration is as representative as any row in the log.
# There are no MISMATCH rows today; there will be the first time the suite gains a
# check mid-campaign, and that is exactly when an estimate must not silently reach
# back into a cheaper era for its window.
TIMED_VERDICTS = ("SURVIVED", "killed", "MISMATCH")

# A `killed` row whose detail starts like this is a CRASH, not a fast suite. `run`
# writes it when the exit code is nonzero and no FAIL line was printed, so the run
# died partway: the log's two cheapest rows, `logic/R24-safeInt-finite` at 80 s and
# `logic/R30-monotonic-underflow` at 89 s, are both `exit 133` — SIGTRAP, 80 seconds
# in. They are correctly scored as kills and they are not durations. Reading them as
# durations is what put "80 s" in this file's own header as the floor of a per-run
# range, and the floor of an estimate is the number a session budgets against.
ABORTED_DETAIL = re.compile(r"^exit \d+, no FAIL line")

# How many of the newest recorded runs the estimate spans. The whole log is the wrong
# window: it reaches back to a smaller suite on a quieter machine, and mixing eras
# puts the floor of every estimate below anything this machine has done in months.
ESTIMATE_SAMPLE = 5


def logged_seconds(path=None):
    """Durations of suite runs that ran to completion, oldest first.

    Exact field count — `len(f) != 4`, never `>= 3`. Three field-count defects here
    (T14, A12.3, T18) each got through a consumer that checked only a lower bound,
    and this file writes the log it is now also reading.

    Four things are not durations: an INVALID row (the mutant did not compile, so no
    suite ran), a NOT-APPLIED row (the pattern stopped matching; `record` writes
    seconds=0), an aborted run (see `ABORTED_DETAIL`), and a zero-second row from any
    source.

    **The coverage figure for `--self-test` is 21 of 26 mutations killed**, measured
    2026-08-17 by applying each one to a copy of this file and running the flag. Every
    mutation, its verdict and its killing checks are in
    `SELFTEST-MUTANTS-2026-08-17.tsv`, so the count is auditable and re-derivable
    rather than a sentence. It read "12 of 14" for a few hours on 2026-08-17, written from
    reasoning and not from a run, and it was wrong in both the numerator and the denominator;
    it then read "16 of 20" and "18 of 22" as review rounds enumerated mutations nobody had
    thought of. Do not update it by argument, and expect the denominator to keep growing —
    that is what an honest one does.

    Note the asymmetry with `already_done`, which parses the same rows: its header term
    IS load-bearing, because it has no verdict filter standing behind it. The same
    guard is redundant in one function and the only thing in the other.

    **Five mutations survive. Four are provably no-ops** — a different claim from "not
    covered", and the reason the figure is worth having — **and one is a real gap, named
    rather than hidden**: dropping `run`'s `print(text)` entirely survives, because the check
    that drives `run` asserts its return value and its tripwires and not its stdout. That
    loses a message and starts nothing, which is why it is recorded and not fixed. The four
    no-ops:

      * dropping the `f[0] == "mutant"` header term changes nothing, because a header
        row's second field is the literal "verdict", which no verdict tuple holds;
      * admitting "NOT-APPLIED" to `TIMED_VERDICTS` changes nothing — not a term, a
        value inside one — because those rows carry seconds=0 and `secs > 0` catches
        them anyway. The INVALID row is what pins the verdict term instead: a non-run
        with a *nonzero* duration;
      * `ABORTED_DETAIL.match` -> `.search`, and dropping the `^` from the pattern,
        each survive because **each alone is behaviourally identical**: `.search` on a
        `^`-anchored pattern can only match at position 0, and `.match` anchors there
        whatever the pattern says. Measured, not argued — all three of anchored-match,
        anchored-search and bare-match answer the same on both a mid-string and a
        leading detail. Only *both at once* reads a detail that merely mentions the
        abort shape as an abort, and the "mentions the abort shape" check below kills
        that pair. A 2026-08-17 review reported these two as uncovered survivors; they
        are survivors, and the reason is redundancy rather than blindness.

    The header term is kept as belt to the verdict brace, because a future hand
    broadening `TIMED_VERDICTS` should not silently start reading headers. No survivor
    here is a check that cannot fail; each is a guard whose neighbour covers it.
    """
    p = path or LOG
    if not os.path.exists(p):
        return []
    out = []
    with open(p) as fh:
        for line in fh:
            f = line.rstrip("\n").split("\t")
            # The header guard is redundant today and deliberately kept: see the
            # docstring's note on which two terms a mutation of this function
            # survives. `record` writes a header into an empty log, so a fresh
            # campaign's file has one even though the log on disk here does not.
            if len(f) != 4 or f[0] == "mutant":
                continue
            if f[1] not in TIMED_VERDICTS or ABORTED_DETAIL.match(f[3]):
                continue
            try:
                secs = int(f[2])
            except ValueError:
                continue
            if secs > 0:
                out.append(secs)
    return out


def estimate_minutes(n_todo, seconds, baseline=True):
    """`(low, high, sample_size)` minutes, or None when there is nothing to say.

    Returns None for two distinguishable reasons and the caller must tell them
    apart — "the log records no run" and "there is nothing to run" are different
    sentences, and printing the first over a log holding 77 completed runs is a false
    claim about this tool's own data. (79 rows, less the two crashes below: any figure
    in this file that says "74" predates the C24b campaign's own five.)

    Reads the newest recorded runs. This was two constants — `len(todo) * 4` to
    `len(todo) * 11` — under a comment calling itself "a RANGE read off this tool's
    own log, not a constant", and nothing could tell the difference because nothing
    outside `run` could call it.

    The baseline counts. It is a full suite run, it happens on every campaign, and
    omitting it understated even a correctly-measured campaign by one whole suite.
    """
    if not seconds or n_todo <= 0:
        return None
    sample = seconds[-ESTIMATE_SAMPLE:]
    runs = n_todo + (1 if baseline else 0)
    return (runs * min(sample) / 60.0, runs * max(sample) / 60.0, len(sample))


def estimate_window(seconds):
    """The rows the estimate actually spanned, for a caller that wants to quote them."""
    return seconds[-ESTIMATE_SAMPLE:] if seconds else []


def startup_line(n_mutants, n_todo, seconds):
    """`(text, proceed)` — the line printed before any work, and whether there is any.

    `proceed is False` means **stop**, and that is the whole reason this is a function.
    The branch it replaces printed "nothing to do" and then fell straight through to
    the rsync and a full baseline suite, while this file's header advertised
    `--only nothing-matches-this` as the free way to read the estimate. It was neither
    free nor informative: no numbers, ~45 minutes, and `mutate.py` does not take
    `ops/autonomous/test-lock.sh`, so the advertised no-op could corrupt a hook's suite.

    Pulled out of `run` because `run` cannot be driven from a self-test — it parses
    argv, copies the tree and starts suites. This takes its three inputs as arguments
    and returns a string, so the branches are checkable for free, including their
    ORDER: `estimate_minutes` returns None both when the log is empty and when there
    is nothing to run, and those are different sentences. Deciding the estimate first
    makes the nothing-to-run case report "records no run that went the distance" over
    a log holding 77 of them.
    """
    window = estimate_window(seconds)
    span = f"{min(window)}-{max(window)} s each" if window else ""
    head = (f"{n_mutants} mutants, {n_mutants - n_todo} already recorded, "
            f"{n_todo} to run")
    nolog = (f"{os.path.basename(LOG)} records no run that went the distance")
    if n_todo <= 0:
        # Minutes as well as seconds: the header calls this the free way to read "the
        # estimate", and a caller deciding whether to wait thinks in minutes. There is no
        # campaign total to print here, because there is no campaign.
        tail = (f"The {len(window)} newest recorded runs: {span} "
                f"({min(window) / 60.0:.0f}-{max(window) / 60.0:.0f} min each)." if window
                else f"And {nolog}.")
        return (f"{head} — nothing to do, so nothing runs, not even the baseline. "
                f"{tail}", False)
    est = estimate_minutes(n_todo, seconds)
    if est is None:
        return (f"{head} — no estimate: {nolog}", True)
    lo, hi, n = est
    # The WINDOW's span, not the whole log's. Quoting min/max over all 79 rows put the
    # 80 s floor next to a claim about contention, when the 80 s row is a crashed run
    # from a smaller suite — two different causes on one line.
    return (f"{head} + 1 baseline = {n_todo + 1} suite runs — roughly "
            f"{lo:.0f}-{hi:.0f} minutes off the {n} newest rows of "
            f"{os.path.basename(LOG)} ({span}). "
            f"**Budget the {hi:.0f}.** Even that is a floor and not a forecast: "
            f"contention moves the per-run cost more than the suite's size does, and "
            f"this same arithmetic run against the log as it stood before the C24b "
            f"campaign was 4.2x low against what that campaign took. Read it again "
            f"after every campaign.", True)


def self_test():
    """Check `logged_seconds` and `estimate_minutes`. Run by the pre-commit hook.

    This file had no self-test at all while being the tool the whole mutation gate
    runs through, and the only figure it printed before doing four hours of work was
    wrong by 5x. Both functions are pure and take their input as arguments, so they
    can be driven without a suite, a copy of the tree, or a mutant.
    """
    failures = []

    def check(name, ok):
        print(f"  {'ok  ' if ok else 'FAIL'} {name}")
        if not ok:
            failures.append(name)

    import atexit
    import tempfile

    # One directory, removed by atexit rather than by a loop at the end of this
    # function. The loop leaked all four files whenever a check *raised* instead of
    # returning False — and a check that raises is the normal way an implementation
    # returning None fails here. atexit runs on the traceback path too.
    tmp = tempfile.mkdtemp(prefix="mutate-selftest-")
    atexit.register(shutil.rmtree, tmp, ignore_errors=True)
    seq = [0]

    def log_with(rows):
        seq[0] += 1
        p = os.path.join(tmp, f"log{seq[0]}.tsv")
        with open(p, "w") as fh:
            fh.write("mutant\tverdict\tseconds\tdetail\n")
            for r in rows:
                fh.write("\t".join(str(c) for c in r) + "\n")
        return p

    # The real shape of the log as of 2026-08-17: old cheap rows, then the C24b
    # campaign's two at ~2700 s. Any window wide enough to include the 80 s row
    # reports a floor this machine has not produced since the suite was a third
    # its present size.
    real = [("a", "killed", 80, "d"), ("b", "killed", 632, "d"),
            ("c", "SURVIVED", 283, "d"), ("d", "killed", 2700, "d"),
            ("e", "killed", 2693, "d")]

    made = []

    def log_of(*extra):
        p = log_with(real + list(extra))
        made.append(p)
        return p

    p = log_of()
    secs = logged_seconds(p)
    check("every completed run is read, oldest first",
          secs == [80, 632, 283, 2700, 2693])

    # ONE ROW PER GUARD, so no guard is pinned only by a row a neighbour also
    # catches. The first version of this self-test fed a single NOT-APPLIED row,
    # which is excluded by verdict AND by `seconds > 0` — so either guard alone
    # satisfied the check, and removing either one on its own left it green. A
    # review found that by deleting them one at a time; the INVALID row (a non-run
    # with a nonzero duration) and the zero-second `killed` row are what separate
    # the two. The NOT-APPLIED row below is kept because it is the shape the log
    # really holds, not because it isolates anything.
    check("a NOT-APPLIED row is not a duration (no suite ran)",
          logged_seconds(log_of(("f", "NOT-APPLIED", 0, "pattern did not match"))) == secs)
    check("an INVALID row is not a duration (the mutant did not compile)",
          logged_seconds(log_of(("i", "INVALID", 45, "did not compile"))) == secs)
    check("a zero-second row is not a duration, whatever its verdict",
          logged_seconds(log_of(("j", "killed", 0, "1 check(s): instant"))) == secs)
    # The two cheapest rows in the real log are `exit 133` crashes 80 s in. They
    # are kills, and they are not measurements of how long a suite takes.
    check("an aborted run is not a duration",
          logged_seconds(log_of(
              ("k", "killed", 81, "exit 133, no FAIL line: Trace/BPT trap"))) == secs)
    # ...and the converse, or the abort filter could be a `killed`-is-never-timed
    # rule wearing a disguise.
    check("a killed row that did print FAILs IS a duration",
          logged_seconds(log_of(("l", "killed", 777, "2 check(s): a; b"))) == secs + [777])
    # `.match` and the `^`, not `.search`. A detail that MENTIONS the abort shape
    # partway through belongs to a run that went the distance, and this row is the
    # only thing in this file that says so: `ABORTED_DETAIL.search(f[3])` and dropping
    # the `^` from the pattern both survived every other check here, measured by
    # applying them one at a time and watching the self-test stay green.
    check("a detail that mentions the abort shape without starting with it IS a duration",
          logged_seconds(log_of(
              ("o", "killed", 700,
               "1 check(s): exit 133, no FAIL line is what this reports"))) == secs + [700])
    # `int`, not `float`. `record` writes the seconds column with `int`, so a
    # fractional value in it means something other than this tool wrote the row —
    # refuse it rather than round it. The "n/a" row above does not pin this: "n/a" is
    # not a float either, so `float(f[2])` survived it.
    check("a fractional seconds field is refused, not rounded into a duration",
          logged_seconds(log_of(("q", "killed", "45.5", "1 check(s): x"))) == secs)
    # MISMATCH ran a whole suite; only its check count differed. Its duration is
    # as good as any row's, and it is the row class that appears exactly when the
    # window must not reach back into a cheaper era.
    check("a MISMATCH row IS a duration",
          logged_seconds(log_of(
              ("m", "MISMATCH", 888, "1140 checks, baseline was 1141"))) == secs + [888])

    # Field count exactly 4. A row with a stray tab in its detail column is
    # malformed, not a short row to be salvaged: T14, A12.3 and T18 were each a
    # consumer accepting one because it only checked `>=`.
    check("a 5-field row is refused, not truncated into a duration",
          999 not in logged_seconds(log_of(("g", "killed", 999, "detail\twith a tab"))))
    check("a 3-field row is refused too",
          998 not in logged_seconds(log_of(("h", "killed", 998))))
    check("a non-integer seconds field is refused, not crashed on",
          logged_seconds(log_of(("n", "killed", "n/a", "1 check(s): x"))) == secs)
    check("a header row is not a duration",
          logged_seconds(log_of(("mutant", "verdict", "seconds", "detail"))) == secs)

    check("an absent log yields no durations and no estimate",
          logged_seconds(p + ".nope") == []
          and estimate_minutes(5, logged_seconds(p + ".nope")) is None)

    # `already_done` is the OTHER consumer of this log, and it read `len(parts) >= 2`
    # while the docstring above called that a defect three times. It is the expensive
    # side of the two: a malformed row accepted here is a mutant marked recorded and
    # never run — a silent hole in the gate rather than a wrong number.
    check("a well-formed row marks its mutant recorded",
          already_done(log_of()).get("d") == "killed")
    check("a row with a stray tab does not mark its mutant recorded",
          "g" not in already_done(log_of(("g", "killed", 999, "detail\twith a tab"))))
    check("a short row does not mark its mutant recorded",
          "h" not in already_done(log_of(("h", "killed", 998))))
    check("the header is not a mutant id, and an absent log records nothing",
          "mutant" not in already_done(log_of()) and already_done(p + ".nope") == {})

    # THE DEFECT, pinned as one exact tuple rather than a handful of thresholds.
    # 6 runs (5 mutants + baseline) over the five newest rows, min 80 s and max
    # 2700 s: 6 x 80/60 = 8.0 low, 6 x 2700/60 = 270.0 high, 5 rows sampled.
    # Every wrong version a review could construct fails this ONE line — the old
    # hardcoded (n*4, n*11) gives (20, 55); dropping the baseline gives
    # (6.67, 225); taking max at both ends gives (270, 270); averaging gives
    # (127.06, 127.06). A threshold like `hi >= 200` catches the first and none of
    # the others, which is how it was written the first time.
    check("the estimate is min..max over the newest five, baseline included",
          estimate_minutes(5, secs) == (8.0, 270.0, 5))

    # The window is the NEWEST rows, so a long tail of cheap runs from a smaller
    # suite cannot set the floor. The 5 is written out rather than taken from
    # ESTIMATE_SAMPLE: a fixture derived from the constant it is meant to pin
    # passes at every value of that constant, which a review confirmed by setting
    # it to 1 and to 50 and watching this check stay green.
    # The name is static on purpose: interpolating the result into it means an
    # implementation returning None raises a TypeError from the f-string before
    # `check` is ever called, and a traceback where a FAIL line should be is a
    # worse diagnostic even though the exit code is still nonzero.
    check("a cheap older era is outside the window, which is 5 rows wide",
          estimate_minutes(1, [80] * 50 + [2700] * 5) == (90.0, 90.0, 5))

    # And the estimate is a function of the log at all. No constant satisfies this,
    # whatever its value.
    check("the estimate moves when the log moves",
          estimate_minutes(5, [100] * 5) != estimate_minutes(5, [2700] * 5))

    # `baseline=False` is the knob the runner never passes; exercised so it cannot
    # rot into a parameter that silently does nothing.
    check("without a baseline, 1 mutant at 600 s is one run of 10 minutes",
          estimate_minutes(1, [600], baseline=False) == (10.0, 10.0, 1))
    check("with one, it is two runs of 20",
          estimate_minutes(1, [600]) == (20.0, 20.0, 1))

    check("nothing to run gets no estimate",
          estimate_minutes(0, secs) is None)

    # SIX rows in, not five. `secs` is exactly ESTIMATE_SAMPLE long, and over an input
    # that length `seconds[-5:]`, `list(seconds)`, `seconds[:5]` and `seconds[-6:]` are
    # all the same list — so the version of this check that fed `secs` passed against
    # every wrong `estimate_window` there is. That is the eleventh check in this
    # register unable to fail, and it was found by mutating the function it guards
    # rather than by reading it: a fixture whose length equals the constant under test
    # cannot see a window at all. The second clause pins the claim the name makes —
    # that the quotable window and the sampled window are the same rows — by asserting
    # the estimate over the same six-row input: 2 runs x 283 s low, x 2700 s high.
    six = secs + [777]
    check("the window a caller can quote is the window the estimate used",
          estimate_window(six) == [632, 283, 2700, 2693, 777]
          and estimate_minutes(1, six) == (2 * 283 / 60.0, 2 * 2700 / 60.0, 5)
          and estimate_window([]) == [])

    # `startup_line` — the branches `run` cannot be driven through. The one that
    # matters is `proceed`: this branch used to print "nothing to do" and then rsync
    # the tree and run a full baseline suite, in a tool that does not take the suite
    # lock, while the header called it the free way to read the estimate.
    # `six`, not `secs`, for the same reason the check above uses it: over a five-row
    # input the window IS the whole log, so `min(seconds)` in place of `min(window)`
    # here reads identically and survives. The first version of these two checks fed
    # `secs` and did exactly that — written minutes after the comment above explaining
    # why not to, and caught by the same harness. The window of `six` starts at 283 s;
    # the whole log starts at 80 s, which is a crashed run from a smaller suite.
    t, proceed = startup_line(89, 0, six)
    check("nothing to run stops before the baseline, and still quotes the window",
          proceed is False and "283-2700 s each" in t and "(5-45 min each)" in t
          and "roughly" not in t)
    t, proceed = startup_line(89, 5, six)
    check("something to run proceeds, and budgets the high end",
          proceed is True and "28-270 minutes" in t and "Budget the 270" in t
          and "283-2700 s each" in t)
    # Branch ORDER, which is a contract and not a style: `estimate_minutes` returns
    # None both for "no log" and for "nothing to run". Deciding the estimate before
    # the nothing-to-run case makes the check above report "records no run that went
    # the distance" over a log holding five of them.
    t, proceed = startup_line(89, 5, [])
    check("an empty log with work to do says so, and still proceeds",
          proceed is True and "records no run that went the distance" in t)
    t, proceed = startup_line(89, 0, [])
    check("an empty log with nothing to do stops without claiming an estimate",
          proceed is False and "roughly" not in t and "nothing runs" in t)

    # ...and `run` must ACT on `proceed`. The four checks above pin only what
    # `startup_line` RETURNS: a review mutated `if not proceed:` to `if False:`, and to
    # `print(text)` alone, and this harness stayed green both times — restoring the exact
    # defect it was written for, an advertised free command that rsyncs the tree and
    # starts an unlocked ~45-minute suite. So drive the real `run` over an `--only` that
    # matches nothing, with every call that could copy a tree or start a process replaced
    # by a tripwire. This is the only check here that touches `run`, and the tripwires are
    # what make it safe to: if the guard ever regresses, this raises instead of running a
    # suite inside the pre-commit hook.
    tripped = []
    saved = (subprocess.run, shutil.rmtree, os.makedirs)

    def tripwire(name):
        def fired(*a, **k):
            tripped.append(name)
            raise AssertionError(f"run() reached {name} with nothing to run")
        return fired

    try:
        subprocess.run = tripwire("subprocess.run")
        shutil.rmtree = tripwire("shutil.rmtree")
        os.makedirs = tripwire("os.makedirs")
        try:
            rc = run(["--only", "no-mutant-id-contains-this-substring"])
        except AssertionError:
            rc = "tripped"
    finally:
        subprocess.run, shutil.rmtree, os.makedirs = saved
    check("run() returns before anything that copies a tree or starts a suite",
          rc == 0 and tripped == [])

    print(f"self-test: {len(failures)} failure(s)")
    return 1 if failures else 0


def run(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true", help="print the catalogue and stop")
    ap.add_argument("--only", default="", help="run mutants whose id contains this")
    ap.add_argument("--rerun", action="store_true", help="ignore the existing log")
    ap.add_argument("--self-test", action="store_true",
                    help="check the log reader and the estimate; runs no suite")
    args = ap.parse_args(argv)

    # Before anything that copies a tree or starts a suite. The hook runs this on
    # every commit that stages this file, so it has to be free.
    if args.self_test:
        return self_test()

    mutants = [m for m in catalogue() if args.only in m["id"]]
    if args.list:
        for m in mutants:
            print(f"{m['id']:52s} {m['file']:24s} {m['note']}")
        print(f"\n{len(mutants)} mutants")
        return 0

    done = {} if args.rerun else already_done()
    todo = [m for m in mutants if done.get(m["id"]) not in VERDICTS]
    # The estimate is now actually read off this tool's own log — see `estimate_minutes`,
    # which used to be this line's two hardcoded constants under a comment claiming it
    # was not. Understating it is not cosmetic: "the ~70-minute full catalogue" reached
    # the daemon's resume prompt as something a session might start, and the C24b
    # campaign was announced as "20-55 minutes" and ran about four and a half hours.
    text, proceed = startup_line(len(mutants), len(todo), logged_seconds())
    print(text)
    # Nothing to mutate means nothing to run, INCLUDING the baseline. This used to fall
    # through to the rsync and a full suite — see `startup_line`.
    if not proceed:
        return 0

    # A copy of what is on disk right now. Not `git worktree add HEAD`: that
    # tests the last commit, which is not what anyone means by "does my suite
    # catch this".  testdocs is 1.2 GB and the suite builds its own fixtures.
    work = os.path.abspath(os.path.join(REPO, "..", "vision-ocr-mutants"))
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    r = subprocess.run(["rsync", "-a",
                        "--exclude", ".git", "--exclude", "build",
                        "--exclude", "testdocs", "--exclude", "Tools/mutation-out",
                        REPO + "/", work + "/"], capture_output=True, text=True)
    if r.returncode != 0:
        print("could not copy the tree:", r.stderr, file=sys.stderr)
        return 2

    def suite(where):
        proc = subprocess.run(["./run_tests.sh"], cwd=where, capture_output=True, text=True)
        out = proc.stdout + proc.stderr
        total = None
        for line in out.splitlines():
            t = line.strip()
            if t.endswith("passed") and "/" in t:
                try: total = int(t.split("/")[1].split()[0])
                except ValueError: pass
        return proc, out, total

    print("baseline:", end=" ", flush=True)
    _, base_out, baseline = suite(work)
    if baseline is None or "FAIL" in base_out:
        print("the suite is not green before mutating; fix that first", file=sys.stderr)
        shutil.rmtree(work, ignore_errors=True)
        return 2
    print(f"{baseline} checks, green")

    try:
        for i, m in enumerate(todo, 1):
            path = os.path.join(work, "Sources", m["file"])
            original = open(path).read()
            # Count first. `subn(..., count=1)` returns at most 1, so testing its
            # result only ever caught *zero* matches — a pattern hitting two
            # sites mutated the first and reported a normal verdict. That was
            # live: the R23 pattern matched readOutline's bound AND copyOutline's
            # identical one, so the log claimed coverage of a bound that had
            # never been perturbed (T7).
            hits = len(re.findall(m["pattern"], original))
            if hits != 1:
                why = "pattern matched nothing" if hits == 0 else f"pattern matched {hits} sites — ambiguous"
                print(f"[{i}/{len(todo)}] {m['id']:52s} NOT-APPLIED   {why}")
                record(m["id"], "NOT-APPLIED", 0, why)
                continue
            mutated, _ = re.subn(m["pattern"], m["replacement"], original, count=1)

            open(path, "w").write(mutated)
            started = time.time()
            proc, out, total = suite(work)
            took = time.time() - started
            open(path, "w").write(original)
            # Kept for triage: a verdict without the output behind it is the
            # same kind of unfalsifiable claim this tool exists to find.
            os.makedirs(os.path.join(REPO, "Tools", "mutation-out"), exist_ok=True)
            safe = m["id"].replace("/", "_")
            with open(os.path.join(REPO, "Tools", "mutation-out", safe + ".log"), "w") as fh:
                fh.write(f"exit={proc.returncode}\n\n{out}")
            # A *compile* error, specifically. Matching bare "error:" mislabelled
            # a mutant that trapped at runtime — the trap prints "Fatal error:
            # Double value cannot be converted to Int" — as INVALID, i.e. scored
            # a genuine kill as "the mutation was malformed". Wrong in the
            # direction that flatters the suite.
            if re.search(r"\.swift:\d+:\d+: error:", out):
                verdict, detail = "INVALID", "did not compile"
            elif proc.returncode == 0 and total != baseline:
                # The mutant compiled and the suite passed, but a different
                # number of checks ran — so this is not the suite we calibrated
                # against and the verdict means nothing.
                verdict, detail = "MISMATCH", f"{total} checks, baseline was {baseline}"
            elif proc.returncode == 0:
                verdict = "SURVIVED"
                detail = next((l.strip() for l in out.splitlines()
                               if l.strip().endswith("passed")), "suite green")
            else:
                verdict = "killed"
                fails = [l.strip()[5:].strip().split(" — ")[0]
                         for l in out.splitlines() if l.strip().startswith("FAIL")]
                if fails:
                    detail = f"{len(fails)} check(s): " + "; ".join(fails[:3])
                else:
                    # Nonzero exit with no FAIL line is a crash or a hang, which
                    # counts as killed but for a different reason worth seeing.
                    tail = [l.strip() for l in out.splitlines() if l.strip()][-1:]
                    detail = f"exit {proc.returncode}, no FAIL line: " + (tail[0][:60] if tail else "no output")
            mark = "  <-- SURVIVED" if verdict == "SURVIVED" else ""
            print(f"[{i}/{len(todo)}] {m['id']:52s} {verdict:9s} {took:5.0f}s  {detail[:70]}{mark}",
                  flush=True)
            record(m["id"], verdict, took, detail)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    final = already_done()
    survivors = [k for k, v in final.items() if v == "SURVIVED"]
    unevaluated = [k for k, v in final.items() if v not in VERDICTS]
    print(f"\n{len(survivors)} survivor(s)")
    for k in survivors:
        print(f"   {k}")
    if unevaluated:
        # Loud, because a mutant that never ran is not evidence of anything and
        # must not be read as one.
        print(f"\n{len(unevaluated)} mutant(s) NOT EVALUATED — no verdict, not a clean result:")
        for k in unevaluated:
            print(f"   {k}: {final[k]}")

    # A12.7. **The summary read only the log**, so a catalogue entry that had never
    # been applied was invisible: a `--only` campaign printed a clean bill over four
    # mutants nobody had ever run. `const/maximumMRCPageMegapixels` was one of them,
    # which is why A3.1's "killed by a check whose input is wrong" was a prediction
    # rather than an observation. A tool whose job is finding false negatives cannot
    # have one of its own.
    knownIDs = {m["id"] for m in catalogue()}
    never = sorted(knownIDs - set(final))
    if never:
        print(f"\n{len(never)} mutant(s) in the catalogue with NO ROW AT ALL — "
              "never applied, so nothing is known about them:")
        for k in never:
            print(f"   {k}")
    # And the other direction: a row for a mutant the catalogue no longer has is a
    # verdict about code that may not exist. Reported rather than deleted, because
    # deleting somebody's evidence is not this tool's decision.
    stale = sorted(set(final) - knownIDs)
    if stale:
        print(f"\n{len(stale)} logged mutant(s) NOT IN THE CATALOGUE — the entry was "
              "renamed or removed, so the verdict describes code that may be gone:")
        for k in stale:
            print(f"   {k}: {final[k]}")

    print(f"\ncoverage: {len(knownIDs & set(final))} of {len(knownIDs)} "
          "catalogue entries have a verdict.")
    return 0


if __name__ == "__main__":
    sys.exit(run())
