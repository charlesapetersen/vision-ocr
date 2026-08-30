# How changes get made here

This project has repeatedly shipped regressions *inside fixes for other bugs* —
three in a single session (C13 and C14 from C10 and C9, R17 from R2). The process
below exists because of that, not as ceremony. Follow it even when the change
looks trivial; the trivial-looking ones are exactly what produced C13.

## The short version

```
git switch -c fix/<thing>     # never work on main
… change, with a test that fails without it …
./run_tests.sh                # must pass, in full
… adversarial review of your own diff …
git commit                    # BUGS.md updated in the same commit
git switch main && git merge --ff-only fix/<thing>
git push
```

## 1. Never work on `main`

Start every change on a branch:

```sh
git switch -c fix/uncancellable-read
```

`main` should only ever move forward by fast-forward merge of a branch whose
tests passed. Two reasons, both learned here: a half-finished geometry change on
`main` is indistinguishable from a working one until the corpus runs, and having
the previous commit intact is what makes `git worktree` bisection cheap when a
number moves unexpectedly.

For anything touching `SearchableWriter`, `Flattener` or `JBIG2`, build the
comparison binary before you start:

```sh
git worktree add -q --detach /tmp/before HEAD
```

You will want it. Every geometry change in this project's history has needed a
before/after measurement, and reconstructing "before" afterwards is
disproportionately annoying.

## 2. Write the failing test first, and prove it fails

Not a suggestion. **Three tests in this repo passed against a deliberately
reintroduced bug** before being made to bite:

- the invariant-5 fixture passed twice — first because the rotated page's
  *displayed* box coincided with page 1's, then because an absolute tolerance
  loose enough for a correct build also accepted a broken one;
- the crop-box test asserted the published page size, which on the JBIG2 route
  comes from `JBIG2.assemble` and is unaffected by the bug it was written for.

So: reintroduce the defect, watch the test fail, put the fix back. If you cannot
make it fail, you have not tested the thing you think you have.

## 3. Suspect the instrument

The single most repeated lesson here. In one session four separate "defects"
turned out to be the measurement:

| what looked wrong | what it was |
|---|---|
| `qpdf` dropping `/Outlines` | qpdf sorts dictionary keys; the regex was anchored at `/Type` |
| an outline surviving | grep found *orphaned* objects; reachability was never checked |
| a broken outline tree | `PDFDocument(url:)?.outlineRoot` without holding the document |
| a crash in `wrapImage` | `String(format:)` with `%@` and a Swift `String`, prints lost to buffering |

Before believing a surprising number, check the thing that produced it. And
before believing a *percentage*, check the absolute counts — the DPI floor took
one document's score from 100% to 94% while increasing the text it recovered from
3 lines to 139.

## 4. Adversarially review your own diff before committing

Read `git diff` as though you are trying to reject it. Minimum questions:

- **Invariant 1.** Can this path drop a page, a line or a text layer without
  saying so? Page count is not sufficient verification.
- **What did I just break?** Which other property depends on what I changed?
  `SearchableWriter` has **four** that fight each other; re-measure all four
  (CLAUDE.md invariant 3). This said "three" for a long time, and the fourth — a run
  keeping a gap from the next fragment *on its own line* — is the one with the worst
  history: it had been holding by accident, and when it broke, words welded
  (`valuablestudy`). Sending a maintainer to check three is sending them past it.
- **Is my new code the risky kind?** Hand-written PDF, process handling, and
  anything with a `static var` have each produced defects here.
- **Does the register still tell the truth?** Four BUGS.md entries turned out to
  be wrong as written. If your work proves an entry wrong, fix the entry.

For a substantial change, run a real adversarial pass rather than doing it in
your head — several agents with different lenses, each finding verified by a
second agent trying to refute it. Every such pass on this codebase has found real
defects, including in code written minutes earlier.

## 4a. Let the machine put the defect back

Section 2 says to reintroduce the defect and watch the test fail. Nine checks in
`BUGS.md` could not fail, and every one was found by doing that by hand — which
is the part a person forgets. So:

```sh
python3 Tools/mutate.py --only <substring>   # after changing a constant or a guard: ~290 s a mutant plus a
                                             # baseline suite (479 s end to end for one, measured
                                             # 2026-08-24; 705 s for two, 2026-08-25; 875 s for two,
                                             # 2026-08-26; 582 s for one, 2026-08-28 — that rise was the
                                             # suite growing 1,247 -> 1,355; budget from
                                             # $STATE/suite-timings.tsv)
                                             # ⛔ "not contention" stood here as a general claim and is
                                             # refuted 2026-08-29: one mutant took 800 s end to end and
                                             # 382 s for its own suite against 292 s at the same suite
                                             # size — both 1,355 checks as of 2026-08-29 — 31 hours
                                             # earlier: 1.31x, which 0.8% of suite
                                             # growth cannot buy. ⛔ QUOTE 1.36x, NOT 1.31x: that pair
                                             # is TWO DIFFERENT MUTANTS, and the SAME mutant
                                             # (logic/R25-depth-aware-prune) has since been measured at
                                             # 280 s and 382 s — same base d88a426, and as of
                                             # 2026-08-29 both at 1,355 checks,
                                             # 30 h 35 m apart — which puts suite growth at exactly 0%
                                             # and holds mutant identity fixed as well. Adopted
                                             # 2026-08-29 from a stranded worktree.
                                             # ⛔ READ 1.36x AS AN UPPER BOUND: the daemon TERMed that
                                             # session's 6-process tree 15 s into the 280 s suite, which
                                             # survived it; freed siblings can only push that figure
                                             # DOWN. BUGS.md T5 "#### The same mutant twice".
                                             # ⚠️ WHAT the term is remains an
                                             # inference: a Time Machine backup was live, and this
                                             # repo's own ledger (ops/autonomous/README.md) measured
                                             # that the loadavg column does not order these durations.
                                             # Recorded loadavgs are 5.00 against 4.36 — and the
                                             # 2026-08-28 R25 run has NO suite-timings row at all, so
                                             # its own load is unrecorded. n = 2. What IS bounded is
                                             # mutant identity: 292 s vs 280 s, two mutants ~46 min
                                             # apart that day, both at 1,355 checks as of 2026-08-29,
                                             # is 1.043x.
                                             # ⚠️ The suite is 1,361 checks as of 2026-08-30
                                             # (r25-depth-fixture): 0.44% growth, which on this
                                             # block's own arithmetic is far too small to matter,
                                             # so the rows above stay comparable. Recorded only so
                                             # a later reader can see which size each was taken at.
                                             # ⛔ n = 8 on the estimator as of 2026-08-30 and SIX
                                             # of the eight are inside the printed range — FIVE of
                                             # them from that day's SIX runs, the sixth being
                                             # 2026-08-28's 8-10/582 s. That day's four printing
                                             # 9-13 were — 593 s (clocked,
                                             # `mutant-r25c`), ~617 s (derived +/-60 s, whose
                                             # row is labelled `mutant-r25b-derived` for that
                                             # reason), and 598 s twice off the never-run census
                                             # (the second is `mutant-c26-inkbar-override`; the
                                             # first has no row, that session's omission) — and
                                             # the fifth printing 10-13, ~618 s derived +/-30 s,
                                             # row `mutant-c26-inkbar-nil`.
                                             # ⛔ The SIXTH is the one outside, and its printed range
                                             # is a SINGLE VALUE: A11.1-publishVerified-gate printed
                                             # 10-10 and measured 595 s exactly — inside the
                                             # unrounded [582, 596] s span that produced it but 5 s
                                             # (0.8%) under the printed 600 s floor. The window has
                                             # homogenised to a 2.4% spread, so `:.0f` can no longer
                                             # express the interval: a degenerate range means the
                                             # rows agree, NOT that the estimate is exact.
                                             # Budgeted 13 min is 1.26x-1.32x the measured on THOSE
                                             # FIVE. Not every reading: 2026-08-29's 800 s was 33.3%
                                             # OVER budget. And 1.26x is not the fifth run's news —
                                             # 780/617 was already 1.264; the earlier 1.30x had
                                             # excluded the derived row from its minimum.
                                             # ⛔ This read n = 4 / THREE under today's own date
                                             # until 2026-08-30 — a present-tense figure that
                                             # dates itself, which `check-staleness.sh` has no
                                             # arm for. Re-derive it; do not read it here.
python3 Tools/mutate.py                      # the whole catalogue — ~8 h at that rate, and it said
                                             # ~65 HOURS until 2026-08-24, when `1dbaafd` took a 16.2x
                                             # clamp off the suite. Read the tool's header — but NOT its
                                             # startup estimate, which has read 14.5x, 14.8x and 11.7x
                                             # high. It heals by ROWS, not runs: two more mutant rows
                                             # clear the window, and a two-mutant run ages two at once.
                                             # ✅ The window cleared 2026-08-26; its first RECORDED reading
                                             # came 2026-08-28: `8-10` printed, 582 s measured, high end
                                             # 3.1% high. Not the first such reading — the 2026-08-26
                                             # Saturation run's window was clear too and nobody wrote its
                                             # startup line down. n=1 — budget from suite-timings.tsv.
```

Add a mutant when you add a constant or a guard worth protecting. A survivor is
either a gap in the checks or a value nothing depends on, and T5 records how to
tell those apart. ⛔ **There are ZERO survivors as of 2026-08-30, and the list ages
silently either way**: `already_done()` is last-row-wins, so a verdict sits until
somebody spends a `--rerun` on it — an empty list means nobody has re-asked, not that
nothing can survive. (It read ONE as of 2026-08-28 and TWO before that.)
Both of those `SURVIVED` rows were the first campaign's
— the only two in the log reading `478/478` — and re-asking one of them
(`const/maximumPageMegapixels`) against a suite that stood at 1,355 checks as of
2026-08-28 came back `killed`, by a check written for something else. T5
`#### The survivor list re-asked`.
⛔ **The other one, `logic/R25-depth-aware-prune`, was re-asked on 2026-08-29 and
`SURVIVED` — and it is measured to be a GAP in the checks rather than a value
nothing depends on** (⚠️ *"the first such survivor"* would be a superlative over a
population of two, the other killed the day before). The fixture written to discriminate
it varies the two keys' NAMES, and CoreGraphics's yield order reads their POSITION,
so its "both orderings" pair covers one order twice; swapping the two object numbers
splits the two prune rules (depth-aware 777, identity-only nil).
✅ **THE GAP IS CLOSED 2026-08-30 AND THERE ARE NO SURVIVORS: that fixture is in the
suite and the mutant is `killed`.** Baseline **`1361 checks, green`**, mutant **296 s**,
**`1359/1361 passed`**, `killed` by **exactly the two new checks**. ⛔ **The attribution
is the objecting-check LIST and not the old pair's green** — two failures out of 1,361
with both named makes that green entailed, and it is inert by construction besides.
`mutate.py` prints **`0 survivor(s)`** — ⚠️ **not for the first time ever** (the log's
first commit held two rows, both killed) but for the first time over a catalogue of 104;
`coverage` stays **79 of 104**,
so ⚠️ **an empty survivor list is not coverage — 25 catalogue entries still have no row
at all** (the queue's `mutants-never-run`). ⛔ **That pair reads `83 of 104` and 21 later
the SAME DAY**, when `const/textPageInkOutsideThreshold`, then
`logic/C26-inkbar-override-ignored`, then `logic/C26-inkbar-nil-refuses-the-page` and then
`logic/A11.1-publishVerified-gate`
became the first four census entries worked off — `killed` by six checks, by four, by
eleven and by three, survivor list still 0 all four times — which is the
separation this sentence asserts, measured rather than argued (T5
`#### The first never-run mutant`, `#### The seam's other end`,
`#### The seam's second and last` and `#### Invariant 2's own gate`). ⚠️ It moves by one a
session; re-derive it rather than reading it here.
R25 `#### The fixture, IN THE SUITE`, T5
`#### The last survivor re-asked`. **The lesson to carry: a fixture built "both ways
round" is only two ways round if it varies what the thing under test actually reads.**

## 4b. Sweep the siblings before you call it fixed

The register's most repeated shape is a fix that closed one *instance* of a
defect and left its twin. R24 bounded `flatten`'s buffer and missed
`saturation`, which sized one from the same page box — R29. R19 bounded
`readOutline` and missed `copyOutline`, its own mirror — R23. C20 was two
functions holding different definitions of one idea.

Every one would have been caught by a single grep. So before closing anything,
ask *who else does this* and write the answer in the commit:

```sh
rg -n 'fullBox|box\.width \*'      Sources/    # who else sizes from a page box
rg -n 'Int\(.*\.rounded\(\)\)'  Sources/    # who else converts a Double
rg -n 'func .*depth: Int'            Sources/    # who else recurses with a bound
```

If a sibling exists, either fix it in the same commit or say in `BUGS.md` why it
is not affected. "I only looked at the reported line" is how R23, R29 and C20
each became a second entry.

## 4c. Make the failure path actually fail

R31, R32 and H2 were all careful code in branches that only run when something
else goes wrong — and nothing ever made it go wrong, so none had ever executed.
The reviewers found R31 by putting a no-op `install_name_tool` on `PATH`.

```sh
./Tools/fault-inject.sh          # every case
./Tools/fault-inject.sh relocate # one
```

Add a case whenever you add an error branch, and **watch it fail first**. The
`detach_fails` case is the warning: its first version broke only half of what it
needed to, so the branch never ran and it passed while testing nothing.

## 4d. Enumerate states against doors, do not reason about pairs

The fourth way this project produces defects is two changes that are each
correct alone. U19 gated the batch on a new flag; U20 added an async import that
checked it; U21 was the moment neither had thought about. Reasoning about which
features might interact does not scale — there is no list of pairs.

Enumerating does. When a property must hold across a lifecycle, write the table:
every state on one axis, every way of violating it on the other, and assert the
cross product. See "every door into a committed batch is shut" in
`Tests/main.swift`. It is finite, it does not care which two features collide,
and it forces you to *name* every state — which is what would have caught U21,
whose "deciding" state existed in behaviour and in no flag.

Add the inverse row too: the doors must still work when the property does not
apply, or an app that does nothing satisfies the table.

## 5. Verification gates, in order of cost

| when | what |
|---|---|
| every commit | `./run_tests.sh` in full — enforced by the pre-commit hook |
| a new constant or guard | a mutant in `Tools/mutate.py`, and watch it get killed |
| a new error branch | a case in `Tools/fault-inject.sh`, and watch it fail first |
| any fix | the sibling sweep in 4b, with the answer in the commit |
| a property spanning a lifecycle | the states-by-doors table in 4d |
| any UI change | `./build.sh` (the suite compiles the views but does not run them) |
| a change to a tool, **or to a struct a tool constructs** | `Tools/check-tools-compile.sh` — enforced by the hook for staged tools. Three tools have shipped unable to compile: C25's had never built, and T16's two were broken by a field added to `Prefs.Snapshot` 40 commits before anyone noticed. ⛔ **"staged tools" meant `.swift` and `.py` only until 2026-08-27**: T16 added the `bash -n` arm to the script and left this selector behind it, so a staged, broken `Tools/*.sh` was dropped in silence for twelve days while the commit still paid the full suite (T20). It reads `swift\|py\|sh` now. ✅ **And the two gaps T20 left are CLOSED 2026-08-27 (T21): every staged shell script anywhere in the tree is `bash -n`'d from its STAGED BLOB before the docs-only exit** — so `.githooks/pre-commit`, `run_tests.sh`, `build.sh` and `ops/autonomous/*.sh` are all gated at commit time, and the sweep's own shell arm now takes every tracked `*.sh` (4 → 22). ⛔ **Not by widening this selector**: it delegates to a script that exits 1 with no `swiftc`, so moving it above that exit would refuse a docs-plus-hook commit for an environment reason. Watched by `Tools/fault-inject.sh hook_parses`, seven rows, `5 passed, 2 failed` against the pre-fix hook |
| a change to a Python tool | `python3 Tools/<tool>.py --self-test` — enforced by the hook for any staged `Tools/*.py` carrying `add_argument("--self-test"`. Add one when you add a tool. `py_compile` was the entire gate for Python here, and it cannot see a parser that accepts a malformed row: that is how `len(f) >= 9` in two consumers survived two separate field-count defects (T14, A12.3, then T18) |
| a tool that prints a TSV | one `row(...)` printer over one `columns` array, with the width asserted. Counting tab escapes by eye has now put the wrong number of fields under a header **three times** — T14's SKIP row, A12.3's `score-mrc`, T18's two — and one of them sat beside a comment reasoning the dash count out and getting it wrong |
| `SearchableWriter` / `Flattener` / `JBIG2` | the invariant-3 procedure, before and after — CLAUDE.md has the commands. **Three shells on one probe rect, and two instruments beside them**: this row said "all four probes" while CLAUDE.md named four *properties* and no fourth probe existed (T14). `score-run-width` is the one added since, for R81, and it is the only one that can see a run drawn at 5% of its box — the rect the other three share is answered by the line above |
| anything geometry- or routing-related | `Tools/score-corpus.swift` over `testdocs/` |

Install the hook once per clone:

```sh
git config core.hooksPath .githooks
```

It refuses a commit whose tests do not pass, and warns when `Sources/` changed
without `BUGS.md` or `Tests/`.

## 6. Record the evidence, not the intent

A commit message here says what was measured, not what was attempted. Numbers,
before and after, and the document they came from. `BUGS.md` gets the same
treatment in the same commit — an entry without evidence is a rumour, and this
register has already carried four false ones.

If you decide *not* to fix something, say why, with the measurement that made you
decide. `C5`, `R9` and `R13` are all `WONTFIX` and all defensible because the
reasoning is written down.
