# Hand-off, 2026-08-15 (daytime session)

The second session of 2026-08-15. The overnight one is
[HANDOFF-2026-08-15.md](HANDOFF-2026-08-15.md) and it is still worth reading for the
twenty-three fixes it landed and for its three-group statement of what was left. **This
file supersedes its "what is left" section**, because group 1 is now done and group 2 is
half done.

Read this, then `BUGS.md`'s header, then `REVIEW-2026-08-14.md` for anything still open.

## Where the tree is

`main` at `ce0c303`, clean, pushed, **1042/1042 checks green, no checks skipped**. Two
commits. No worktrees, no branches, nothing staged, nothing stranded in `/private/tmp`.

**Ask git, not this file.** That sentence is in the previous two hand-offs because the
prose went stale behind the work three times in three days.

## What landed

| register | what it was |
|---|---|
| **T14** | every instrument CLAUDE.md invariant 3 names was wrong, and two of the commands would not run at all |
| **C25** | `Tools/score-text-route.swift` has never compiled in any commit |
| **C24** | **opened, not fixed** — `largestImage` answers a document-wide question, so one page's plate sets another page's rebuild resolution |

**Group 1 is done, and it was the gate on the text layer.** The invariant-3 procedure is
executable for the first time since recognition moved into the helper: `CLAUDE.md` now
prints it as five commands, and `Tools/make-observations.swift` is the producer the two
probes had been asking for. Anything in group 3 can now be measured.

## What is left, in the order it should be done

**Group 2 — the rest of `Tools/`.** Two of four done (A12.2 as C24/C25, and A12.5/A12.7
were T12 overnight). Remaining:

1. **`A12.3`** — `score-mrc` never applies R50's all-text shrink, so its tone layers are
   **14.18–16.95x** the shipped size, a 41.7–245.7 KB per page overstatement of its `mrcKB`
   column. Three further divergences: no colour route at all (3 of 11 sampled picture pages
   are colour, so *both* sides are the wrong artefact there), a 60 MP gate where the app's is
   100, and no empty-stencil refusal. Affects `FEATURES.md`'s "40,010 KB today, 8,069 KB as
   MRC — 4.96x", in the entry that names this tool as the way to re-measure it. **Start by
   asking whether it can call `Flattener.mrcLayers` instead of mirroring it** — C25 is what
   mirroring costs.
2. **`A12.4`** — the corpus gate re-implements `pageIsAnImage` as three bare literals in
   `classify-source.swift`, with a *different* predicate: `maxImage` is a max over five
   sampled pages while `medianDPI` is a median over those pages, so one page's raster
   combined with another page's DPI passes a test no single page passes. 7 of 233 documents
   disagree with `Flattener.pageIsAnImage`, and the **2** documents `Flattener.hasDigitalText`
   calls born-digital are both among the 7 — the gate whose whole purpose is D1 admitted the
   two documents the app itself puts a modal in front of. Affects D1 and both `CORPUS-*.md`.
   Note this now has a live cross-reference: C24 established that `Batzell`, `Kelly_2014`,
   `AI 2027`, `Schwaller` and `Lyons` have pages that **draw no images at all**, which is
   born-digital material sitting in a corpus whose stated property is "every one of them a
   scan". A12.4 and C24 are looking at the same documents from two directions.
3. **`R54`** (`sweep-zotero.py` pools 181 parentless attachments) and the remainder of
   **`A12.8`**. R54 is a `LEFT JOIN` fix. A12.8's items are small and listed in the review.
   **`R55`** needs its own measurement campaign against known hand-held material before
   `classify-source` moves — do not change that threshold on one document.

**Group 3 — the text layer and the crop box.** Not started, and now unblocked.
`A1.2`, then `A1.1`, then `C23`, in that order, because A1.1's only viable fix triples the
sliver population A1.2 is about. Also open and small: `A1.3`, `A1.4`, `A2.4`, `A3.1` in its
narrower form, `A13.4`, the residue of `A10.6`, and `A11.8`.

**`C23` is still the release blocker** and still the only open finding with harm a user sees
today: every rebuild route publishes with no `/CropBox`, so the copy displays what the
original hid — 14 of 233 documents, 577 of 16,987 pages, worst case 34.7% of the sheet.
Its entry has the fix and the reason the obvious test does not work.

**`R56`/`R57`** remain blocked on the one unbuilt shape signal. `FEATURES.md` specifies it:
a connected-component pass over the routing thumbnail giving component count, median
bounding-box size and row alignment. Both entries now have two independent reasons for it and
four measured rounds proving the cheap alternatives do not work.

## What this session corrected in the record

Three of these were wrong in `REVIEW-2026-08-14.md`, and one was wrong in `BUGS.md`. The
review is a good document; it is not a trustworthy one line by line.

- **A6.1 says `probe-text-offset`'s median is sound and only its range is artifact. It is
  not.** Changing the scan order and nothing else moves the median −0.10 → 0.00 on dense
  newsprint. Every `off=` figure recorded before `7798ba0` belongs to the old instrument.
- **A6.1's proposed fix for that probe was measured and dropped.** It blames a non-unique
  anchor; refusing those lines changes the median, the p5..p95 and the range by nothing over
  four pages and 161 lines, while discarding up to two thirds of the sample.
- **A12.8 files the `pages[0]` defect as small. It is a false *failure*, not only a false
  pass** — `probe-line-edges` reported `line starts: 0/32` on a page holding five good lines.
- **A12.2's mechanism is the wrong way round.** Extraction destroys nothing; production reads
  a shared `/Resources` and reports the largest image *anywhere* in the file for a page that
  may draw nothing at all. And **`qpdf --pages` gives the identical wrong answer**, so the
  standing "use qpdf when geometry is the question" does not apply to this one.
- **`BUGS.md` T2's closing line** — "`score-routing` was never affected, it calls the real
  `flatten`" — is true of the DPI *policy* and false of the DPI *value*. Corrected in place.

## Things this session got wrong, so you can calibrate

The register carries these because four of its entries have been wrong as written.

- **I opened C24 with a wrong cause and had to retract it in the same commit.** I claimed a
  second defect — that the `walkedAt` memo in `largestImage` makes the walk miss images
  depending on traversal order. The review of my own diff reimplemented `largestImage` with
  no memo at all and diffed it over all 16,987 pages: **0 differences**. The larger answers I
  saw were my prototype's, not the shipped walk's. The observation is recorded without a
  cause rather than with a wrong one.
- **C24's coverage table dropped every page that draws nothing**, so it summed to 16,706
  against a corpus of 16,987 — while the entry's own prose said `Batzell` alone has 51 such
  pages. The instrument was my sweep, and it filtered out the population the table was about.
- **My first repair for C24 sent a text page to 70.6 DPI**, and my second rejected 113 of 114
  pages of a real scan. The second is the more instructive: the unit-square rule is an
  **image** rule, and applying it to a Form XObject reads a full-page form at the identity CTM
  as 1.0 pt wide.
- **A SKIP row emitted 10 fields under a 9-column header** — a reporting defect introduced
  inside a fix for a reporting defect, in the same commit that removed the tenth column.

Every one of these was caught by the adversarial review of the diff, not by care while
writing it. CONTRIBUTING §4 is not ceremony.

## A process note, from the owner

> ⛔ **WITHDRAWN 2026-08-16.** The owner has reversed this: subagents are wanted, and an adversarial
> review agent over a finished diff before committing is expected rather than optional. The paragraph
> below is kept because the *incident* is real and still worth knowing — a barrier makes a part-way
> fan-out unsalvageable, and ten agents each re-reading `BUGS.md` is waste — but its **instruction no
> longer applies**. What is wanted now is in `ops/autonomous/resume-prompt.txt`, §EFFICIENCY + SUBAGENT
> SIZING. This is the only edit to this dated hand-off; the record below is unchanged.

**Work serially. Do not fan out to subagents.** This session opened with a ten-agent recon
workflow over the open findings plus a ten-agent challenge phase behind a barrier. The owner
stopped it: it consumed most of a usage window and one of the ten designs had landed when it
was killed — the other nine were lost, because a barrier makes a part-way run unsalvageable.
Each agent had re-read the same large status files (`BUGS.md` is 6,177 lines) and recompiled
the whole of `Sources/` before measuring anything.

**A single review agent over a finished diff, before committing, is worth it** and is what
CONTRIBUTING §4 asks for. It found four real defects in this session's two commits, listed
above. One agent, one diff, after the work is done.

## Environment, unchanged but still true

- **Never run two suites at once, in any two worktrees** — `build/tests` has no bundle id, so
  every worktree shares `~/Library/Preferences/tests.plist`. Check `pgrep -x tests` first.
- **zsh does not word-split unquoted `$(...)`.** `SRC=$(ls Sources/*.swift); swiftc $SRC` passes
  one enormous filename and fails with `error opening input file`. Build an array.
- Tool build line: copy the tool to `<scratch>/main.swift`, then `swiftc -O -o out -target
  "$(uname -m)-apple-macos13.0" <every Sources/*.swift except App.swift> <scratch>/main.swift`.
- `testdocs/` filenames contain spaces. Glob, quote, never retype.
