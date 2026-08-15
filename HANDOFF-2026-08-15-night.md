# Hand-off, 2026-08-15 (night session)

The fourth session of 2026-08-15. The earlier three are
[HANDOFF-2026-08-15.md](HANDOFF-2026-08-15.md) (overnight),
[HANDOFF-2026-08-15-day.md](HANDOFF-2026-08-15-day.md) and
[HANDOFF-2026-08-15-evening.md](HANDOFF-2026-08-15-evening.md).

Read this, then `BUGS.md`'s header, then `REVIEW-2026-08-14.md` for anything still open.

## Where the tree is

**Ask git, not this file.** That sentence has been in four consecutive hand-offs because
the prose went stale behind the work three times in three days.

One commit, `0a928f2`, merged fast-forward to `main` and pushed. 23 files, +1760/−166.
Suite **1058/1058, no checks skipped** — twelve new checks. No worktrees, no branches,
nothing staged, nothing stranded in `/private/tmp`.

**Nothing in `Sources/` changed behaviour.** `Flattener` gained `sampleIndices` and a
`hasDigitalText(in:)` overload; the URL form is a two-line wrapper over it, and the suite
checks index-for-index that its four sampled pages are unchanged for every document length.
No release decision moves.

## What landed

| register | what it was |
|---|---|
| **T17** | the corpus gate *linked* `Flattener.pageIsAnImage` and then computed its own answer, and admitted the two documents the app calls born-digital |
| **R54** | `FIXED` — and the pooled median stood on 16 files, not 181, and the real defect was in eight *real* item types |
| **T18** | five copies of the shipped page stride, two of which measured one page twice; the third instance of T14's field-count defect; and nothing ran a Python tool's own checks |

**Group 2 is closed.** `Tools/` has nothing outstanding except `R55`, which needs its own
measurement campaign before `classify-source`'s illumination threshold moves. `BUGS.md` is
**five open**: C23, C24, R55, R56, R57.

## The corpus is 230 scans, not 233

`CORPUS-2026-08-15.md` is the whole-corpus run, with its 233 rows committed beside it as
`CORPUS-2026-08-15.tsv` — recompute from that file rather than re-rendering 1.2 GB. It
reproduces byte-identical from line 2 (a header row was prepended by hand).

The two the app itself calls born-digital are `bookSection/Canby_1929` and
`magazineArticle/Davis_2005`, **9 pages of 16,987**, so no median moves; D1 is about
composition. `testdocs/README.md` carries the correction at the top and **leaves the wrong
sentence standing underneath it**, because a corrected figure with no trace of the error
teaches nobody.

**Nothing was removed from `testdocs/`.** Re-cutting the corpus moves every published figure
at once and is the owner's call; this record exists so it can be made with the numbers.

## Two things to distrust, both this session's own

**A12.4's mechanism was wrong and its count was right.** It says the two cross-page
aggregates "pass a test no single page passes". Structurally true, and it did not happen:
the minimum `imagePages` over 233 documents is **1**. The real mechanism is duller — a `max`
over five pages is an *any-page* rule being read as a statement about the document. Fourth
of that review document's findings to need correcting.

**The 230 is 230 at the app's sample size.** `bookSection/full chapter.pdf` is one
sample-size step from `hasDigitalText` calling it born-digital: `wanted: 4` is the only
value above 2 that answers "no", and the document is a genuine ~100 DPI scan whose page
rasters are 810–987 px across the 900 px bar. **The fragile term is the bar, not the
sample** — 23 of its 32 pages count as "digital text" because a 100 DPI page raster is
under 900 px. Recorded as `REVIEW-2026-08-14.md` **A3.5** with `Schwaller`, the corpus's
only 2/4 tie, which fails in the opposite direction: 167 of its 300 pages are born-digital
and the app does not warn. Same shape as R56/R57 — a signal with no term for the zone the
document sits in — and it wants the same treatment, measured over known material rather
than tuned on two documents. **Not filed as a defect and not fixed.**

## The review of this diff found fifteen defects in it

All fixed in the same commit. Eleven were in prose. The ones worth carrying forward:

- **A `.githooks/*` glob that would have refused a commit over a README.** The named-argument
  branch of `check-tools-compile.sh` sniffs shebangs precisely so a non-bash file is skipped
  rather than failed; the whole-tree branch added *every* file in `.githooks/` to the
  `bash -n` set. Reproduced in a scratch tree: a `.githooks/README.md` → exit 1, every tool
  green. **That is T16's own recorded failure mode, reintroduced by the fix for T16's gap.**
- **A summary line reporting 45 files where 5 were listed.** `small` is built from the
  per-type scan lists, so a type with *zero* scans — every file in it born-digital, the
  common case in a real library — never appeared in it while all its rows still carried
  `basis=library`. Counted from the rows now, and a self-test covers the zero-scan type.
- **"98% of the library's scans" sums to 96.8% from the table beside it.** 98.0% is right;
  the eighth qualifying type, `report` at 108 scans, is not in the table because the table
  lists the types with 250+. The number was fine and the *presentation* invited the error —
  which is the same defect as a wrong number, since a reader checking it concludes the
  wrong thing.
- **An inverted claim about which expression samples page 1.** Both skip it on a document
  over four pages; the note asserted the opposite, from reading a 0-based expression as
  1-based.
- A malformed classifier row counted twice, a quote-sensitive `grep` that skipped a
  self-test *silently*, "two new verdicts" where `no-page-image` predates this work, and
  citation errors in three files.

One review agent over a finished diff, after the work was done. It keeps paying.

## The hand-off audit, and what it found

Every figure in this file and in the commit before it was recomputed from
`CORPUS-2026-08-15.tsv` and from `git`, because the last three sessions each put a wrong
number into a commit and nothing in this repository checks one. All of them reproduce:
233 documents / 16,987 pages, 230/2/1 at 98.7/0.9/0.4%, `digitalText=yes` on exactly 2,
minimum `imagePages` 1, majority rule 7, all-pages rule 21, 9 pages of 16,987 (0.053%),
47 documents of 1–3 pages and 27 of 5–11, five `OPEN` entries, one commit of 23 files
+1760/−166, corpus 1.2 GB with 233 manifest rows against 233 PDFs on disk. Every markdown
link in the files this session touched resolves, and every register ID they cite has a
heading.

**Then the audit found two more claims this commit had falsified elsewhere**, which is the
part worth reading:

- **`HANDOFF.md` still said "233 documents, every one of them a scan."** Corrected in place
  to 230, with the wrong sentence named rather than quietly replaced.
- **`CHANGELOG.md`'s 1.10.0 entry claimed the gate used "the same `Flattener.pageIsAnImage`
  the app uses — one rule, not two that drift."** That is the exact sentence T17 falsifies,
  in a released changelog, and it had been true-sounding for a week. Bracketed correction
  added; the entry's counts are left as the dated figures they are.

**What is deliberately left stale, labelled rather than rewritten:** `CORPUS-2026-08-08.md`,
`CORPUS-2026-08-09.md`, `CHANGELOG.md`'s corpus counts and `TODO.md` §2's survey table all
carry old-predicate verdicts and now carry a dated note saying so. They are records of runs,
not claims about the present, and re-cutting their numbers would mean re-running the library
sweep (~50 minutes) and re-drawing a corpus.

**No tool wrote a preferences plist.** Checked by name for every binary this session built
and ran — `score-text-route.plist` exists and is dated **2026-08-13**, part of the
long-standing debris the evening hand-off documents, not new. `Prefs.register(migrate: false)`
is holding.

**Nothing stranded.** One worktree, one branch, nothing staged, no suite running, and the
2.3 GB `zotero.sqlite` copy this session made for R54's measurement has been deleted along
with every scratch binary.

## What is left

**Group 3 — the text layer and the crop box.** Not started. `A1.2`, then `A1.1`, then
`C23`, in that order, because A1.1's only viable fix triples the sliver population A1.2 is
about. Also open and small: `A1.3` (including the two dead locals in `rightLimit`, left
deliberately — touching `SearchableWriter` opens the invariant-3 procedure), `A1.4`, `A2.4`,
`A3.1` in its narrower form, the new `A3.5`, `A13.4`, the residue of `A10.6`, `A11.8`.

**`C23` is still the release blocker** and still the only open finding with harm a user
sees today. **`C24`** is open with its measurements and three refused repairs. **`R56`/`R57`**
still wait on the one unbuilt shape signal — and A3.5 now converges on it from a third
direction.

**`R55`** is the only `Tools/` entry left, and it needs the campaign its entry specifies:
known hand-held material (Random Photograph, 186 files) against known mechanical material,
before the illumination threshold moves.

**The library sweep's step 1 wants re-running before step 2 acts on it.** Both of its inputs
changed: the classifier asks different questions, and the per-type median floor moved from 5
to 100. About 50 minutes. `TODO.md` §2 carries the superseded-figures note.

## Things worth knowing before touching this area

- **A tool that *links* a shipped function has not necessarily *called* it.**
  `sample-zotero.py` explained at length why the classifier must be compiled against
  `Sources/`, and that was necessary and not sufficient for a week. The docstring now says
  so where the false claim was.
- **Count the fields; do not reason about the dashes.** Three field-count defects in three
  entries. The remedy that works is one `row(...)` printer over a `columns` array with the
  width asserted — `classify-source`, `score-text-route` and `score-annotations` all have
  one now. Beside the row that was *correct* sat a comment reasoning the dash count out and
  getting it wrong ("eight dashes, not nine"; there are seven).
- **`py_compile` cannot see a parser that accepts a malformed row.** That was the entire gate
  for `Tools/*.py`, and it is how `len(f) >= 9` survived two field-count defects in two
  consumers. Both Python tools carry `--self-test` now and the hook runs it for any staged
  one that advertises the flag. **Add one when you add a Python tool.**
- **Seven page samplers survive in `Tools/` and were left alone on purpose.** All checked
  for repeats over n=1…3000. Converting them would retire the figures recorded against
  them — `score-corpus`'s sample is the one behind every text-layer figure in the register.
  The `score-reading-order`/`score-skew` twins are byte-identical and are the one pair worth
  converting when either tool is next opened.
- **`score-text-route` measured *nothing* on 47 of 233 documents** before this commit —
  `filter { $0 > 0 }` empties the sample for n ≤ 3. Verified by building the tool at
  `6fdd000` and running it on a real 2-page corpus document: a bare header, `no
  picture-route pages measured`, **exit 0**, indistinguishable from a document with no
  picture pages. The same document through the fixed tool finds one picture page worth
  238,176 bytes between the two routes. The 8.2 KB/page figure the tool is cited for is
  still unverified (C25); `Blacks in the City` is not in the current corpus, so re-deriving
  it needs that file back.
- **`Flattener` reads no preferences at all**, and eleven tools that never call
  `Prefs.register` read none either — checked, so T15's fifth divergence has no other
  instance.

## Environment, unchanged and still true

- **Never run two suites at once, in any two worktrees** — `build/tests` has no bundle id,
  so every worktree shares `~/Library/Preferences/tests.plist`. Check `pgrep -x tests`
  first. **This includes a suite started by a review agent you launched** — tell it not to.
- **macOS bash is 3.2.57**: `"${ARRAY[@]}"` under `set -u` on an *empty* array is fatal, and
  `wait -n` does not exist.
- **zsh does not word-split unquoted `$(...)`.** Build an array.
- Tool build line: copy the tool to `<scratch>/main.swift`, then `swiftc -O -o out -target
  "$(uname -m)-apple-macos13.0" <every Sources/*.swift except App.swift> <scratch>/main.swift`.
  Or `Tools/check-tools-compile.sh <name>`, which now also covers `.githooks/pre-commit`.
- **Do not name a build output the same as the directory holding its `main.swift`.**
- `testdocs/` filenames contain spaces. Glob, quote, never retype.
