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
  `SearchableWriter` has three that fight each other; re-measure all three
  (CLAUDE.md invariant 3).
- **Is my new code the risky kind?** Hand-written PDF, process handling, and
  anything with a `static var` have each produced defects here.
- **Does the register still tell the truth?** Four BUGS.md entries turned out to
  be wrong as written. If your work proves an entry wrong, fix the entry.

For a substantial change, run a real adversarial pass rather than doing it in
your head — several agents with different lenses, each finding verified by a
second agent trying to refute it. Every such pass on this codebase has found real
defects, including in code written minutes earlier.

## 5. Verification gates, in order of cost

| when | what |
|---|---|
| every commit | `./run_tests.sh` in full — enforced by the pre-commit hook |
| any UI change | `./build.sh` (the suite compiles the views but does not run them) |
| `SearchableWriter` / `Flattener` / `JBIG2` | the three invariant-3 probes, before and after |
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
