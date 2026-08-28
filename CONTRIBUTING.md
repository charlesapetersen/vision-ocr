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
                                             # 2026-08-26; 582 s for one, 2026-08-28 — the rise is the
                                             # suite growing 1,247 -> 1,355, not contention; budget from
                                             # $STATE/suite-timings.tsv)
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
tell those apart. ⛔ **There is ONE survivor as of 2026-08-28, not two, and the
list ages silently**: `already_done()` is last-row-wins, so a verdict sits until
somebody spends a `--rerun` on it. Both `SURVIVED` rows were the first campaign's
— the only two in the log reading `478/478` — and re-asking one of them
(`const/maximumPageMegapixels`) against today's 1,355 checks came back `killed`,
by a check written for something else. `logic/R25-depth-aware-prune` is the
remaining one and has not been re-run. T5 `#### The survivor list re-asked`.

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
