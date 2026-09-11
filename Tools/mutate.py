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
one command this header advertised as free cost ~45 minutes (clamped-era; see below) in a tool that does not
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

    ⛔ **AND IT IS WRONG IN THE OTHER DIRECTION AS OF 2026-08-24, WHICH IS WHY "BUDGET
    THE HIGH END" IS NOT ENOUGH ON ITS OWN.** `1dbaafd` removed a 16.2x clamp from the
    suite (`ProcessType=Background` in the daemon's plist, inherited by every child,
    plus `run_tests.sh` passing no `-O`). The next scoped run — `const/lineMinimumMembers`
    — took **246 s for the mutant and 479 s end to end**, against a startup line reading
    "roughly 100-116 minutes": **14.5x HIGH**, off the same five-row window that was
    4.22x low in 2026-08-17. Nothing here can tell the two eras apart, because the log
    records no build flags and no scheduling band. It self-heals as post-clamp rows push
    the clamped five out of the window — counted in ROWS, not runs, so the two-mutant
    `cap-reaches-further` run on 2026-08-25 aged two at once and left
    `[3407, 3415, 246, 227, 244]`, two rows from clear — and until then the startup line
    is the worst number available rather than the best. That run read **14.8x** high
    (`12-174` printed, **705 s** measured for a baseline and two mutants), so the failure
    is twice in the same direction and not one bad row. ✅ **The window CLEARED on
    2026-08-26, when a `--rerun` of the same pair added two rows: it is now
    `[246, 227, 244, 292, 289]`, and a 1-mutant run prints `8-10` — whose high is
    9.73 min, single digits, shown as 10 by this module's own `:.0f`. So the forecast
    that went with it holds in substance and was 1.5 min low, because it was arithmetic
    off the surviving rows' max of 246 and the two incoming rows are dearer than every
    row they joined.** ⛔ That day's own `11-171` line is the **fourth and last
    clamped-era reading**, 11.7x high over an 875 s run — NOT a reading of the cleared
    window, because the startup line prints before the run and its span says
    `227-3415 s each`. Re-estimating that same job from the cleared window gives
    `11-15` against 14.6 measured. ✅ **The first RECORDED reading from the cleared
    window was taken 2026-08-28 and it HELD**: `8-10` printed over a baseline plus
    `const/maximumPageMegapixels`, **582 s** measured, inside the range with the high
    end **3.1% high** — against 14.5x, 14.8x and 11.7x high off the clamped-era window.
    ⛔ *"No live reading exists yet"* was already two days stale when it was written
    here: the C27 (c) Saturation run's rows sit BELOW `bare-form-reach`'s in the log,
    so its startup line came off an all-post-clamp window too and simply went
    unrecorded. Reading a row's ERA off its position is the only way to tell, because
    the log has no date column — which is this header's own standing warning.
    ⚠️ n = 1, and the run was a quiet machine (loadavg 4.36); this is the estimator no
    longer being known-broken, not the estimator being proven.
    ⛔ **AND THAT CAVEAT IS THE ONE THAT PAID OFF. n = 2 as of 2026-08-29 and the SECOND
    recorded reading from the cleared window was 1.33x LOW**: `9-10` printed off a window
    of `[292, 289, 275, 277, 292]` for a baseline plus `logic/R25-depth-aware-prune`,
    **800 s = 13.3 min** measured (`$STATE/suite-timings.tsv`, `mutant-r25 800 0 5.00`),
    i.e. **800 s is 33.3% OVER the budgeted 600** — ⛔ not "600 was 33.3% under", which is
    25%; a draft mixed two denominators into one comparison. The `1.33x` ratio form is
    this header's own convention and is the one to quote.
    ⛔ **n = 8 as of 2026-08-30 and SIX of the eight are INSIDE the printed range**, so
    the run of bad readings is over rather than continuing: 2026-08-28 inside, 2026-08-29
    outside (1.33x low), 2026-08-30's two runs of `logic/R25-depth-aware-prune` both
    inside — `9-13` printed, **593 s** clocked (`$STATE/suite-timings.tsv`,
    `mutant-r25c 593 0 4.47`) and ~617 s derived (±60 s, row `mutant-r25b-derived`, which
    carries that label so nobody budgets off it as a clocked figure) — and 2026-08-30's
    FOUR never-run-census runs: `9-13` printed and **598 s each** for the first two, the
    second of which is row `mutant-c26-inkbar-override` (the first has no row; that
    session's omission), then `10-13` printed and **~618 s** derived (±30 s, row
    `mutant-c26-inkbar-nil`), then `logic/A11.1-publishVerified-gate`, the eighth reading
    and the SECOND one outside (2026-08-29's 800 s is the first).
    Budgeted 13 min is **1.26x-1.32x** the measured **on those five** — over-budgeted, the safe
    direction. ⛔ **Not on all eight**: 2026-08-29's 800 s was 33.3% OVER its budget. ⛔ **And the
    1.26x low end is not the newest run's**: 780/617 was already 1.264, so the earlier `1.30x`
    had taken its minimum over the clocked rows only.
    ⛔ **THE EIGHTH READING IS THE ONE THAT NEEDS THE ARITHMETIC WRITTEN OUT, because its
    printed range is a SINGLE VALUE and reading it as a bullseye would be wrong in the
    flattering direction.** `logic/A11.1-publishVerified-gate` printed `10-10` off a window
    of `291-298 s each` and measured **595 s = 9.92 min** (07:20:21 → 07:30:16; its own
    mutant suite was 295 s exact; row `mutant-a11.1-publishverified 595 0 3.64`). The two
    ends are `2 x 291 = 582 s` and `2 x 298 = 596 s`, i.e. 9.7 and 9.93 min, which `:.0f`
    prints as the same 10 — so the measurement is **inside the unrounded span [582, 596] s**
    and **5 s (0.8%) BELOW the printed 600 s floor**, which is why it counts as outside.
    The range collapsed because the window has homogenised: five post-clamp rows at
    1,355-1,361 checks whose DURATIONS span 291-298 s, a 2.4% spread — ⛔ a draft hung that
    2.4% off the check counts, whose own spread is 0.44%, and the check-count half is
    inferred from dates besides, four of the five rows being `killed` with no total
    recorded. **So a degenerate range means the window agrees with
    itself, not that the estimate is exact** — and at this spread `:.0f` can no longer
    express the interval it computed.
    ⛔ **This paragraph read `n = 4` / THREE with today's date on it until 2026-08-30, so
    it was stale by two the moment those two runs landed** — a present-tense figure that
    dates itself, and `check-staleness.sh` has no mutation-figure arm to catch it.
    ⚠️ Still one machine; budget from `suite-timings.tsv`, not from this paragraph.
    ✅ **What is measured is that the SUITE cannot be the term**: that mutant's own suite
    took **382 s** against the one window row measured at the same **1,355** checks
    (292 s), i.e. **1.31x**, and 0.8% of growth does not buy that. ⛔ **"1.31x-1.39x at
    the SAME 1,355 checks" was in a draft and is FALSE — the window spans three suite
    sizes** (`[292, 289]` at 1,344, `[275, 277]` at 1,346, `[292]` at 1,355), and the
    1.39x end came off a suite 11 checks smaller.
    ⛔ **BUT "only ONE row is comparable" IS SUPERSEDED AS OF 2026-08-29, AND THE 1.31x
    IS CROSS-MUTANT: `logic/R25-depth-aware-prune` HAS A SAME-MUTANT PAIR AND IT IS
    280 s AGAINST 382 s — 1.36x.** The 280 s row was adopted from stranded worktree
    `vo-20260828-060044-25839`, on the SAME base (`d88a426`, `cab9901`'s parent), its
    run completing **2026-08-28 06:12:48** — ⚠️ that is the `mutation-log.tsv` MTIME,
    the only witness there is, since neither the log nor the row carries a timestamp.
    **30 h 35 m** before the 382 s run, not the 31 h that labels the 292-vs-382 pair.
    1.31x compared TWO DIFFERENT MUTANTS and therefore conflated machine state with the
    two mutants' own costs; 1.36x holds the mutant fixed and puts suite growth at
    **exactly 0%** — both rows `1355/1355`. ⚠️ **Quote 1.36x for the
    spread and 1.31x only as the cross-mutant figure it is** — and read 1.36x as an
    UPPER BOUND, per the first limit below.
    ✅ **What the verdict certifies, stated exactly**: `run()` writes `SURVIVED` only on
    `proc.returncode == 0 AND total == baseline`, so each row is certified to have
    matched **its own run's baseline** — anything else is `MISMATCH`. The **1,355**
    itself is the suite's printed total, and the two coincide because the output holds
    exactly one `…/… passed` line, verified in the 2026-08-28 log and NOT verifiable
    for 2026-08-29, whose `mutation-out/` log is gitignored and overwritten per run.
    ⚠️ **Held fixed is PROVEN on one side and INFERRED on the other.** For 280 s:
    the rescue `.base` reads `d88a426`, the strand's `status --porcelain` holds only
    the TSV, and its `Tools/mutate.py` mtime is the worktree's creation, so the R25
    catalogue entry was `d88a426`'s. For 382 s the worktree is gone and `mutate.py`
    rsyncs what is on disk, not `HEAD`; the tree identity is inferred from
    `cab9901^ == d88a426` plus `cab9901`'s `Sources/`/`Tests/` changes being
    comment-only. Sound, but an inference.
    ⛔ **FOUR limits, and the first is the one that bounds the number.** (1) The daemon
    went down at **06:08:23** (`$STATE/daemon.log`, SIGTERM, KILL backstop 8 s later)
    and TERMed the session's 6-process tree — **15 s into this very suite**, which ran
    06:08:08 → 06:12:48. The run survived it (`exit=0`, 1,355 `ok`, 0 `FAIL`), being
    outside the killed tree, which is also why it wrote no timings row and never
    committed. Killing siblings can only FREE resources, so if it moved the 280 s at
    all it moved it DOWN — the direction that inflates 1.36x. Unmeasured, hence "upper
    bound". (2) The column times `suite(work)`, which BUILDS the mutated tree as well
    as running it; true of both rows, so the pairing holds, but it is not a pure suite
    figure and the build is the more contention-sensitive half. (3) That missing
    `$STATE/suite-timings.tsv` row means the 2026-08-28 loadavg is unrecorded and
    cannot be set against the 382 s run's 5.00. (4) n = 2.
    ✅ **A CLEANER BOUND ON THE MUTANT-IDENTITY TERM comes free from the same day**:
    `const/maximumPageMegapixels` **292 s** and `logic/R25-depth-aware-prune` **280 s**
    are two DIFFERENT mutants ~46 minutes apart, both at 1,355 checks — **1.043x**. So
    mutant identity buys ~4% within one machine-state window, which is what says the
    cross-mutant 1.31x was mostly not the mutants. ⚠️ The 292 s run's tree was
    `d88a426`'s content UNCOMMITTED (it ran 05:26, the commit is 05:51:34), so that
    pair is same-suite-size and same-day but not same-tree.
    ⚠️ **WHICH term it is stays an INFERENCE and the stronger form was refuted by the
    review of that diff.** A Time Machine backup was three hours into a run at ~39% of a
    core alongside CrashPlan and OneDrive, and the two runs' recorded loadavgs are 5.00
    and 4.36 — but `ops/autonomous/README.md` measured that the loadavg column does NOT
    order these durations, that those two processes barely move a 1-minute average, and
    that the later predictor was the scheduling band; it files this same story as an
    inference and nobody has run the controlled experiment. So the estimator is not merely
    unproven: it cannot be corrected from this log, which records neither load nor a date.
    **The rule that
    survives all three failures is the one this header already gives**: a rate read off
    history is wrong in whichever direction history has just moved, so date every figure
    and prefer `$STATE/suite-timings.tsv` rows dated after 2026-08-24 — and do not reach
    for the loadavg column as the correction, which the ledger says it is not.
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

⚠️ `--rerun` appends a SECOND row for a name that already has one, and the LATER
row is the current verdict — `already_done()` is last-row-wins. ⛔ **DERIVE the
duplicate count, never read one from this line** (`cut -f1 … | sort | uniq -d`): it
said SEVEN "as of 2026-08-26", correct at `bee2db1` and stale by 2026-08-29 — a count
in prose goes stale on every `--rerun` of a recorded name, which is why this file
declines to quote a total row count either. The log has no date column, so two rows for one name
are distinguishable only by file position: quote the last, and if the two differ
in their `N check(s)` field, the earlier one is describing an older suite.
⚠️ **`logic/R25-depth-aware-prune` carries THREE rows, in run order ON PURPOSE**: its
280 s row ran 30 h 35 m BEFORE its 382 s one and was inserted above it on adoption
(2026-08-29), because this file is otherwise append-ordered and appending would have
misstated the order. ⛔ **Nothing the TOOL reads depends on that choice** — all three
verdicts are `SURVIVED` so last-row-wins is unmoved, and either placement leaves the
estimator the same five-row multiset (both measured). **What does depend on it is the
human rule two lines up**: under an append, "quote the last" would have pointed at the
OLDER run.
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
    # C27 (c), 2026-08-26. The colour decision's own bar, split out of the route's
    # on that day at the same value — so at shipped values NO CHECK CAN TELL THE
    # TWO APART, and this pair of mutants is the only thing that can. The claim
    # they measure is that each side has its own reader. RUN BOTH, or neither says
    # anything: `python3 Tools/mutate.py --rerun --only Saturation`, and the
    # `--rerun` is not optional, because `pictureSaturationThreshold` already has
    # a row and a default run skips anything already logged.
    # ⛔ **DISJOINT EXCEPT ONE, and the exception is by construction.** Measured
    # 2026-08-26: the colour mutant is `killed` by **11** checks and the route
    # mutant by **5**, intersecting in exactly one — *"…and the split is a no-op at
    # the shipped values"*, which reads BOTH constants and therefore reds under
    # either. A first draft of this comment claimed flat disjointness and the
    # review of that diff refuted it from the check's own expression. Both sides
    # have a killer that is NOT a mirror: the absolute `shouldKeepColour(0.07)`
    # pair on the colour side, *"flat-colour routes to the picture path"* on the
    # route side.
    # ⚠️ The find string is anchored on the symbol name (`run`'s pattern is
    # `(static (?:var|let) <name>[^=\n]*=\s*)<old>\b`), so the two 0.06 constants
    # cannot be confused for one another — one match each, and `hits != 1` would
    # refuse it if they could. Both were reported APPLIED in the run recorded in
    # `BUGS.md` C27 `#### The split, SHIPPED`.
    # ⚠️ The pre-split row for `pictureSaturationThreshold` says "1 check(s)" and
    # is not wrong — it is stale by ADDITION. Four of today's five killers were
    # written after it.
    ("Flattener.swift", "colourSaturationThreshold", "0.06", "0.9"),
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
    # C26's bar, put back where it stood before 2026-08-19 — 0.08 is not a
    # perturbation, it is the shipped value that erased three drawings on
    # `1954 - Why.pdf` and lines of prose on 7 other corpus pages. The suite has three
    # checks sized against it: two on `inkOutsideText` directly (0.0554 and 0.0551,
    # both inside the band the lost drawings measured) and one that layers the fixture
    # and reads the background width back. This state was run by hand on the way in —
    # the flipped checks were watched failing against 0.08 before the constant moved —
    # so what this entry buys is that the same experiment stays runnable. ⚠️ `--only C26`
    # does NOT select it: `--only` is a substring of the id, and the id is built from the
    # constant's own name. Use `--only textPageInk`. ⚠️ True of 105 of the 106 entries as of
    # 2026-09-11 — `const/lineGapFactor-raised` carries an explicit id, see `catalogue()`.
    ("Flattener.swift", "textPageInkOutsideThreshold", "0.045", "0.08"),
    # C28's wiring, 2026-08-22. Two of the shape rule's five numbers, chosen because
    # each is load-bearing in a *different* direction and the suite has a check sized
    # against each. 99 members means no line group forms on any fixture a suite can
    # build, so the third term stops refusing and the missed-word fixture goes back to
    # being stored at an eighth — which is the defect C28 is open for, planted.
    # ⚠️ NOT "no line group ever forms": `textLines` still emits a run of >= 99 members,
    # which is why the retraction below says the count is dropped on the fixtures rather
    # than in general. This sentence said "ever" until 2026-08-24, twenty-five lines above
    # the paragraph correcting it.
    #
    # ✅ RUN THROUGH THIS TOOL 2026-08-24 AND KILLED — 246 s, `1242/1247 passed`, by
    # **exactly five** checks — NOT the widest kill in this log (a first draft said so
    # and the sweep below refutes it: `logic/C24-unknown-is-not-no` announces six, and
    # three other rows announce five, so this is a four-way tie for second), but the only
    # one that reaches C28's term AND its wiring in the same run. Two are the term's own
    # counts going 1 -> 0 (the missed word; the four-stroke positive control) and three
    # are the wiring's, byte-identical in the row to the three that killed
    # `logic/C28-alltext-ignores-shape` — that mutant made the verdict ignore the
    # count, this one drops the count below what the wiring refuses on, and they arrive
    # at the same place from the two ends of `return groups == 0`. `BUGS.md` C28
    # `#### lineMinimumMembers RUN through mutate.py` is the durable copy of all five.
    #
    # ⛔ **NO informative green, said in advance and not retracted after.** Raising the
    # bar is strictly one-sided — `flush()` resets `run` whether or not it emits, so a
    # higher bar removes groups and never adds one — but that is only half an argument,
    # and the half the 2026-08-24 retraction says is insufficient. What carries it is
    # that every `groups == 0` assertion (boxed, scanner bar, C26's ink figure,
    # too-wide, too-tall, border-only) reads 0 at 4 AND at 99: identical input,
    # identical answer, cannot fail. The two layering positive controls cannot fail for
    # the same reason — their page reads 0 at both values. ⛔ NOT because the mutant
    # "forces" the all-text verdict, which a draft of this said and is false: terms 1
    # and 2 still run and still refuse a page over either bar, and a run of >= 99
    # members would still group. The test is "does the mutant change this check's input
    # at all", never "could this check move in principle".
    ("Flattener.swift", "lineMinimumMembers", "4", "99"),
    # ✅ …and this one WAS a known survivor and is not one any more, 2026-08-22. It was
    # added with a comment claiming the suite's scanner-rule fixture was "held out by this
    # number alone"; the adversarial review of that diff refuted it, because a solid fill
    # is ONE 8-connected component and one component can never reach `lineMinimumMembers`
    # = 4 — so `c28GroupsBar` read 0 at every value of `shapeRunHigh` and the fixture was
    # held out by the GROUPING. The entry then named the fixture it wanted: "FOUR OR MORE
    # non-type-shaped components in one horizontal band — four short solid dashes on a
    # baseline, say". `Tests/main.swift` builds it now, three ways, with a positive control
    # of four narrow strokes that IS a line group so the two refusals cannot be satisfied
    # by marks that simply failed to group.
    #
    # ✅ RUN THROUGH THIS TOOL 2026-08-23 AND KILLED — 3,475 s, `1246/1247 passed`, by
    # exactly ONE check: "…and the same four at 4x the stroke width and 4x the ink are NO
    # line group", reading `groups Optional(1)`. So the claim is a red check in
    # `Tests/main.swift` now, and not a probe binary's reading over its own copy of BOTH the
    # fixture builder and the surface construction — which is what the paragraph this
    # replaces said it was, and all such a binary can establish is that the term flips on
    # that geometry. ⛔ The kill rests on that ONE check, and it did not exist before
    # `6d0caa1`, committed 00:10:53 the SAME day: that is what "known survivor" meant here.
    # ⛔ Two things were published as MEASURED off that run's greens and are PART-RETRACTED
    # 2026-08-24 down to one, by the review of the sibling entry's run. A green is evidence
    # only if the mutant changes that check's INPUT: (a) the too-TALL fixture's green was
    # guaranteed — its bars are 5 px wide, medianRun 5, already under the shipped bar of 10,
    # and it stays refused by its HEIGHT at both values; (b) `c28GroupsBar`'s says nothing
    # about grouping — its rule is one component of medianRun 884, still refused by the SHAPE
    # rule at a bar of 495. ✅ Only `c28GroupsC26` carries it: medianRun 30 is accepted at
    # 495, so `lineMinimumMembers` = 4 is what refuses it. The kill, the one objecting check
    # and the attribution (which rests on the two REDS, one per run) are untouched.
    # ⛔ A THIRD was drafted and retracted: the four-dash calibration check's green is NOT
    # evidence about this constant, because `c28Calibration` reads `interiorWindow`,
    # `shapeComponents` and `shapeMinimumArea` and nothing else — `shapeRunHigh` reaches it
    # only through the detail string, so that green is guaranteed at every value. A check
    # that cannot fail, in the row claiming a measurement.
    # ⚠️ Still not automatic. `--self-test` covers the log reader and the estimate and never
    # touches `CONSTANTS`, so the next drift here reports itself only when someone runs the
    # mutant again — and the suite's standing contribution is unchanged: the fixtures' type
    # scale and all three `inkOut` values are asserted in bands, so a geometry that drifted
    # away from the probe's reports itself.
    ("Flattener.swift", "shapeRunHigh", "2.0", "99.0"),
    # …and its sibling, added with the same fixture on 2026-08-22 and attributable to it
    # alone: at 99.0 the four 5x120 strokes clear a height band that shipped ends at 75.0,
    # so the too-tall fixture reads 1 while the too-wide one does not move.
    # ✅ RUN 2026-08-24 and PROBE-ONLY NO LONGER: `killed`, 3,415 s, `1246/1247 passed`, by
    # EXACTLY ONE check — the too-tall fixture's — while the too-wide check stayed green, the
    # mirror image of `shapeRunHigh`'s run the day before. So the pair is attributable one
    # constant each from the SUITE's side in both directions, and `BUGS.md` C28
    # `#### shapeHeightHigh RUN through mutate.py` is the durable copy of the FAIL line.
    # ⛔ It has NO informative green, and the review of that run's diff retracted BOTH that
    # were claimed
    # in advance. A monotonicity argument bounds which WAY a check can move and says nothing
    # about whether the mutant changes its input at all. This constant has one call site (an
    # upper bound in `textShaped`) and is absent from the calibration filter, so the accepted
    # set is monotone in it — but raising the ceiling from 3*glyphHeight = 75 px to 2,475 px
    # can only admit a component TALLER than 75 px, and every component on the too-wide and
    # control pages is 30 px tall with the map holding nothing but those bars. Same input,
    # same count, cannot fail. So this mutant's reachable surface is the pages carrying a map
    # component taller than 3*glyphHeight, which in the whole suite is `c28TooTall` alone.
    #
    # ⛔ `shapeMinimumArea` WAS "deliberately still absent" AND IS NOT — it got its entry
    # 2026-09-11, at the END of this list, and the bare mutant `SURVIVED` before a fixture
    # existed. The rest of this paragraph is kept because its argument is still the right
    # one for the LOWERING direction, which remains unrun. **At its shipped value**, in
    # `textShaped`, it cannot be the deciding
    # term: an 8-connected component spanning `[minY, maxY]` owns a run in every one of
    # those rows, so area >= height, and the height test already demands
    # `h >= shapeHeightLow * glyphHeight` — so wherever the median glyph is >= 8 px the area
    # guard is satisfied before it is asked. That is conditional on the 8 px (72-DPI corpus
    # scans can fall under it), it says nothing about RAISING the constant (4 -> 99 refuses
    # tall thin marks, which is not the height bar under another name), and the constant is
    # separately live in `textLineGroupsOutsideText`'s calibration filter, which those
    # fixtures do run through — so whether they would kill such a mutant is unmeasured
    # rather than settled. ⛔ **`lineGapFactor` HAS A CATALOGUE ENTRY AS OF 2026-09-10 — it is
    # immediately below — and this sentence is kept as written because it is what that entry was
    # added against.** ⛔ **But it is STILL ONE-SIDED and a draft of this line said otherwise,
    # corrected on adoption 2026-09-11: "one-sided" here means PINNED ONE WAY ONLY, not "has no
    # entry", and the new mutant pins the LOWERING direction alone** — the raising direction has
    # no fixture in this suite at all (see the bracket at the end of that entry). So
    # `shapeHeightLow` AND `lineGapFactor` both remain one-sided, exactly as this sentence said;
    # what changed for the second is the REASON, which is now measured rather than assumed.
    # `BUGS.md` C28 `#### The grouping's other constant` says the same thing in two places, and
    # the draft this replaces contradicted both of them in the file the register sends readers to.
    # ⛔ **AND THE `lineGapFactor` HALF FELL THE NEXT DAY, 2026-09-11 — `c28-gap-fixture` BUILT the
    # fixture this line says the suite does not have.** It is pinned BOTH ways now
    # (`const/lineGapFactor` and `const/lineGapFactor-raised`, one catalogue entry each) and the
    # suite brackets it into [2.64, 6.24) where it held only a floor of 2.24. `shapeHeightLow` is
    # what this sentence still describes, and it is the last one-sided constant of the six.
    # `BUGS.md` C28 `#### The gap term's own fixture`.
    # ⛔ **AND THE `shapeHeightLow` HALF FELL THE DAY AFTER THAT, 2026-09-11 — see
    # `const/shapeHeightLow-lowered` at the end of this list. ⛔ **AND THE LAST HALF FELL THE
    # SAME DAY: `shapeMinimumArea` is catalogued too, so ALL SIX now have an entry and this
    # paragraph has no live claim left in it at all — it is kept as the record of an argument
    # that turned out to be about the lowering direction only.** ⚠️ That first sentence's argument is itself conditional on the constant
    # that entry moves: `area >= height >= shapeHeightLow * glyphHeight` is what makes the
    # area guard redundant, so at `shapeHeightLow` = 0.0 the area guard becomes the only
    # lower bound in `textShaped` and IS the deciding term — on the new fixture its four
    # marks clear it 10x (40 px against 4), which is why that mutant reads 1 and not 0.
    ("Flattener.swift", "shapeHeightHigh", "3.0", "99.0"),
    # The grouping's OTHER constant, and the third route into `return groups == 0`.
    # `textLines` flushes a run when the gap to the next member exceeds
    # `lineGapFactor * glyphHeight`, so at 0.0 EVERY positive gap flushes, every run is one
    # member long and `run.count >= lineMinimumMembers` is never satisfied: the term returns 0 and
    # C28's third refusal condition stops existing. ⚠️ Near-total, not total — the gap is
    # `comps[i].minX - comps[prev].maxX` against a STRICT `>`, so components that overlap in x have
    # `gap <= 0` and still share a run; no fixture here has that shape.
    # ⛔ Two corrections to that sentence, both made on adoption 2026-09-11. (1) The run is built
    # against `run.last` only, so the shape is a CHAIN of consecutive overlaps and not a MUTUALLY
    # overlapping set — strictly easier to meet than the draft claimed. (2) *"and no page of type
    # does, glyphs on a line being disjoint in x"* is an UNMEASURED universal and is dropped: these
    # components are map fragments rather than glyphs (this campaign's own three false positives are
    # the rim of a recognised `469.`, where a 1-px collar split one component into four), and italic
    # or kerned bounding boxes overlap while their glyphs do not. ⚠️ It does need real bbox overlap:
    # `maxX` is INCLUSIVE, so two merely touching components read `gap == 1` and do flush.
    # That is the same collapse
    # `const/lineMinimumMembers` (4 -> 99) plants from the other end — there the bar rises above
    # the run length, here the run length is cut to one.
    #
    # ⛔ THE LOWERING DIRECTION AND NOT 3.0 -> 99.0, on the verdict/count split. What is monotone
    # downward is the VERDICT and not the count: every run at a lower factor is a SUB-CHAIN of a run
    # at a higher one, so `groups == 0` can never become non-zero, while a non-zero count can RISE
    # (one run of 8 split by a small gap into two runs of 4 reads 1 -> 2). ⛔ *"Adding flushes can
    # only take `groups` non-zero -> 0"* stood here and is false in that second case, corrected on
    # adoption 2026-09-11; the sub-chain form is both true and what the no-green claim below needs.
    # So a low value can only make `pageIsAllText()` more permissive — the direction that puts the
    # 8x background shrink back on a page carrying unrecognised prose, i.e. the direction that
    # loses content. Raising it is the direction C28 argues cannot lose content (its worst case is
    # bytes), and — reasoned, not measured, so recorded as a prediction — a raising mutant would
    # change no check's INPUT in this suite: every fixture reading 0 groups does so because its
    # components are refused UPSTREAM by the component test (`c28Bar`, `c26Small`, `c28TooWide`,
    # `c28TooTall`) or because it has none (`c28GroupsBoxed`), and no fixture has two qualifying
    # runs in one band to merge. That is the "unchanged input" green this file has retracted three
    # times, so it was not the mutant to add.
    #
    # ✅ RUN 2026-09-10 and `killed` — **289 s, `1359/1364 passed`, by EXACTLY FIVE checks, and the
    # prediction written down before the run held on every element including the detail strings**:
    # the five `FAIL` lines are **byte-identical to `const/lineMinimumMembers`'s logged five**, same
    # checks in the same order, `identical detail strings: True` compared field to field out of this
    # file's log. ⛔ **THE FINDING: TWO DIFFERENT CONSTANTS THAT COLLAPSE ONE ANSWER SHARE ONE KILL
    # SET** — the opposite of the three mutants that reach `Flattener.swift:3479`, whose sets are
    # pairwise disjoint, and the reason is that those collapse different configurations while these
    # two produce the *same* wrong answer (`textLineGroupsOutsideText` returning 0) by different
    # arithmetic. ⛔ Two framings corrected on adoption 2026-09-11: that trio is NOT *"the C26
    # override seam's three mutants"* — the seam is a PAIR and the third is a `CONSTANTS` entry that
    # never touches the override, which `CLAUDE.md` already ⛔-flags — and these two are NOT *"over
    # one expression"*: they are read at `:2183` and `:2199`, SIXTEEN LINES APART, so the contrast
    # implied by "one line" against "one expression" runs the wrong way round. So the
    # five checks are attributable to the grouping and NOT to either constant: neither mutant's red
    # set can tell you which constant moved, and only the 56-against-75 bracket below separates them.
    # `BUGS.md` C28 `#### The grouping's other constant` is the durable copy of the FAIL lines.
    # ⛔ It has NO informative green, said in advance rather than retracted after — and the reason is
    # the SUB-CHAIN argument above, not the mutant's one-sidedness, which is the weak form this file
    # has retracted three times (it answers whether the check could move in principle, not whether
    # the mutant changes its input). Because every run at 0.0 is a sub-chain of a run at 3.0, a
    # fixture reading 0 groups at the shipped value reads 0 at 0.0 as well, so every `groups == 0`
    # assertion in the block is unable to fail: `c28GroupsBoxed`, `c28GroupsBar`, `c28GroupsC26`,
    # `c28WideGroups`, `c28TallGroups`, the border check, AND `Tests/main.swift:3427`'s
    # `.groups(0)` — ⛔ the seventh was missing from this list until the adoption caught it, because
    # the draft reused `lineMinimumMembers`'s six-name list from 2026-08-24 and it and the `shapeTermAnswer` transport check beside it were
    # added 2026-09-02. ⛔ **AND AN EIGHTH JOINED IT 2026-09-11 and this list was short AGAIN, twice
    # running, which is what says a list like this must be re-derived and never appended to from
    # memory**: `c28SplitGroups == 0`, the gap fixture's own check, measured green under this mutant
    # in the run that added it. ⚠️ It is the only one of the eight that is NOT unable to fail in
    # general — it reds under `const/lineGapFactor-raised` and would red at
    # `lineMinimumMembers` = 2 — so it is *this mutant's* unchanged input and not a dead check.
    # And the two that look like yield are emptier still: the `shapeTermAnswer`
    # transport check compares against `c28GroupsMissed`, so BOTH sides go 1 -> 0 and the equality
    # holds, and the `inkOutsideText` assertion reads a field assigned before term 1's guard.
    # ⚠️ **The `runLimit` pair cannot fail either, but calling it "unchanged input" was wrong**:
    # `:3248` reads `c28GroupsMissed`, which goes `Optional(1)` -> `Optional(0)`, so its input DOES
    # change and `!= nil` simply survives it. Corrected on adoption; the conflation of "cannot fail"
    # with "unchanged input" is the one this file ⛔-flags three times.
    # ⚠️ What the suite BRACKETS is one-sided too, and it is worth knowing before anyone moves this
    # number: `c28Dashes` puts the four 5x30 strokes at x = 200 + 60i against a `glyphHeight` the
    # suite asserts at 25.0 and a shipped bar of 75 px. ⛔ **The gap the code computes is 56 px, not
    # the 55 a draft of this carried in five places** — `ShapeComponent.maxX` is INCLUSIVE
    # (`maxX = max(maxX, r.x1 - 1)`, `width = maxX - minX + 1`), so a mark on columns 200...204
    # gives `260 - 204 = 56`; 55 is the count of EMPTY columns between them, which is not what
    # `:2199` reads. So the control reds for any value below 56/25 = **2.24**, and ⛔ *"blind to
    # every value above 2.2"* is FALSE — `[2.2, 2.24)` reds it too. Corrected on adoption 2026-09-11
    # in a block whose own fixture comment exists to warn about exactly this ("Every range in this
    # paragraph is INCLUSIVE ... Two numbers, one boundary", `Tests/main.swift:3095`).
    # ⚠️ And no check asserts these marks' x extents, so 56 is DERIVED from the rect and the
    # component rule rather than measured; antialiased bleed would move it. What holds regardless is
    # that 0.0 is inside the reachable band rather than an arbitrary extreme, and that a RAISE is
    # inert on THIS fixture (bar 75 -> 2475, one run either way) — ⚠️ the wider claim that a raise is
    # invisible to the whole suite is argued from the upstream refusals above, not from this bracket.
    # ⛔ **THAT WIDER CLAIM IS MEASURED FALSE FROM 2026-09-11 and the entry below is why**: a raise
    # is still inert on `c28Dashes`, but `c28GapSplit` reds under it, so the suite's bracket on this
    # constant is two-sided — [2.64, 6.24) — and no longer a floor. Kept as written because it is
    # what the entry below was added against.
    ("Flattener.swift", "lineGapFactor", "3.0", "0.0"),
    # ✅ AND THE OTHER DIRECTION, AS OF 2026-09-11 — the prediction three paragraphs up
    # ("a raising mutant would change no check's INPUT in this suite") was correct about
    # the suite AS IT STOOD and is now refuted on purpose: `c28-gap-fixture` built the band
    # that paragraph says no fixture had. `c28GapSplit` puts four accepted 5x30 marks at
    # x = 200 / 260 / 420 / 480, gaps of 56, **156** and 56 px against a bar of
    # `lineGapFactor * glyphHeight` = 3.0 x 25.0 = 75, so the band breaks into two runs of
    # two, neither reaches `lineMinimumMembers` = 4 and the term reads 0. At 99.0 the bar
    # is 2475, the 156 stops flushing, and one run of four reads 1.
    # ⛔ **THIS IS THE ONLY `CONSTANTS` ENTRY WHOSE ID IS NOT ITS CONSTANT'S NAME**, and
    # `catalogue()` explains why in full: two entries for one constant would otherwise
    # share `const/lineGapFactor`, and `already_done()` is keyed on the id. ⚠️ *"the only
    # entry in the CATALOGUE"* would be false and the adversarial review of this diff
    # caught it — `catalogue()` returns OPERATORS too, and `mrc-stencil-polarity` is a
    # `static let` moved under a `logic/` id, which is the rejected alternative named two
    # sentences down.
    # ⛔ **AND IT IS THE POINT OF THE PAIR RATHER THAN A SECOND HELPING**: the LOWERING
    # mutant above and `const/lineMinimumMembers` are killed by the same checks byte for
    # byte, so neither red set says which constant moved. This one's kill set is reached by
    # NEITHER of them — two runs of two are no group at 4 and no group at 99 — so it is the
    # first attribution the shape term's gap constant has had. ⛔ **What it is NOT is
    # unreachable by any move of `lineMinimumMembers`, and a draft said that**: at
    # `lineMinimumMembers` = 2 each run of two IS a group, the split page reads 2, and the
    # same single check reds. The attribution is over the CATALOGUE, whose only
    # `lineMinimumMembers` entry raises it. ✅ That also makes the split fixture the first
    # one able to see `lineMinimumMembers` LOWERED — C28's own two-sided trade, still
    # asked by no entry. `BUGS.md` C28 `#### The gap term's own fixture`.
    ("Flattener.swift", "lineGapFactor", "3.0", "99.0", "lineGapFactor-raised"),
    # THE HEIGHT FLOOR, and the fifth of the shape term's six constants to get an entry —
    # `shapeMinimumArea` is the last, and it got its own entry hours later on the same day;
    # see the bottom of this block.
    #
    # ⛔ THE LOWERING DIRECTION, AND THE CHOICE IS THE WHOLE POINT OF THE ENTRY. Raising
    # `shapeHeightLow` to 3.0 collapses the band to [75, 75] and refuses `c28Stroke`'s four
    # 30 px marks — but so does lowering `shapeHeightHigh` to 0.5, which gives [12.5, 12.5]
    # and refuses the same four. Two constants, one wrong answer, and the kill sets would
    # come back shared byte for byte exactly as `const/lineGapFactor`'s and
    # `const/lineMinimumMembers`'s do. That is the mistake `c28-gap-fixture` measured, and
    # this entry is written to avoid repeating it rather than to discover it again. ✅ The
    # LOWERING direction cannot be imitated by any value of any other constant OF THE TERM'S SIX
    # (⛔ *"any other constant here"* stood here and is over-broad: lowering `maximumShapeRuns`
    # makes `shapeComponents` return nil, so the term returns nil, so the new check reds — the
    # path `Tests/main.swift`'s runLimit pair already drives. It is deliberately uncatalogued):
    # `shapeHeightHigh` occurs in `textShaped` only as an upper bound
    # (`hh <= shapeHeightHigh * glyphHeight`), so no value of it admits a component the floor
    # refuses — a ceiling cannot lift a floor — and `shapeRunHigh`, `shapeMinimumArea`,
    # `lineMinimumMembers` and `lineGapFactor` are *additional* refusals reached at or after the
    # height band, so loosening any of them cannot admit a component `textShaped` has dropped.
    # ⛔ `shapeMinimumArea` IS THE EXCEPTION and a draft of this list put it in the safe group in
    # four files; the review of that diff refuted it from `Sources/`. It is `textShaped`'s FIRST
    # guard, before the height band, AND the `sized` filter that computes `glyphHeight` — so
    # lowering it lowers the floor itself, which is exactly the imitation being ruled out.
    # ✅ The conclusion survives on two inequalities that do not meet: admitting these marks needs
    # `0.5 * gh <= 8` (gh <= 16) and keeping their 56 px gaps un-flushed needs `3.0 * gh >= 56`
    # (gh >= 18.67), so any calibration low enough to admit them is too low to group them, and a
    # speck-widened median breaks `medianRun 5 <= 2 * glyphRun` besides. ⚠️ Reasoned from the two
    # comparisons, and about the LOWERING direction, which is still unrun. ⛔ A
    # `shapeMinimumArea` mutant HAS been run since (4 -> 99, 2026-09-11) and it leaves this
    # check green — those marks are refused by area where they were refused by height — so
    # the raising direction is measured and only the lowering one is reasoned.
    #
    # ⚠️ SO THE DIRECTION THIS ENTRY PINS IS THE CHEAP ONE, AND THAT IS WORTH STATING RATHER
    # THAN LEAVING A READER TO ASSUME OTHERWISE. Lowering the floor admits components, which
    # can only make the term return MORE groups, which makes `pageIsAllText()` refuse MORE
    # pages and keep MORE resolution: its worst case is bytes. RAISING it is the direction
    # that puts the 8x shrink back on a page carrying unrecognised prose, i.e. the direction
    # that loses content — and that one was already pinned, by `c28Stroke`'s positive
    # control. What this entry buys is not the dangerous direction but REACHABILITY: it is
    # the only one of the two a fixture can tell apart from `shapeHeightHigh`, and a mutant
    # whose reds cannot be attributed is what `CONTRIBUTING.md` §4a now warns about.
    #
    # ✅ WITH IT THE PAIR BRACKETS THIS CONSTANT TWO-SIDEDLY where it held a ceiling alone:
    # the accept rule is `hh >= shapeHeightLow * glyphHeight`, so `c28Stroke`'s 30 px marks
    # are refused once `f * 25 > 30` (f > 1.2) and `c28TooShort`'s 8 px marks are admitted
    # once `f * 25 <= 8` (f <= 0.32) — **those two checks** are green together exactly on
    # (0.32, 1.2], with the shipped 0.5 inside. ⛔ **That is NOT the same as the SUITE's green
    # interval and must not be written as one**: `c28GroupsMissed` asserts 1 over the word
    # `value.`, whose x-height components are a little under the 25 px median, so a floor
    # raised past them leaves the ascender alone and it reads 0 — which reds somewhere well
    # below 1.2. The suite's own interval is therefore at most (0.32, 1.2] and probably
    # narrower; ⚠️ reasoned from the typeface, not measured, because no check asserts that
    # word's component heights. ⚠️ Both endpoints of the PAIR's interval are DERIVED from the
    # drawn rects and the accept rule too, not measured — antialiased bleed would move either
    # — the same caveat the 56 px gap above carries. What the ink guards in `Tests/main.swift`
    # do assert is that the two pages carry four marks each in the 8/30 ratio.
    #
    # THE FIXTURE, `c28TooShort`: `c28Dashes(5, 8)`, i.e. `c28Stroke`'s four marks at the
    # same four x positions and the same 5 px stroke width, 8 px tall instead of 30 — so the
    # pair differs in HEIGHT alone and the inverse row is that existing positive control
    # rather than a third page. At the asserted `glyphHeight` 25.0 the band is [12.5, 75.0],
    # 8 < 12.5, all four are refused by the floor and the term reads 0; at 0.0 the band is
    # [0, 75.0], each mark clears `shapeMinimumArea` (40 >= 4) and the run bar (5 <= 10), the
    # four share one band with 56 px gaps under a 75 px bar, and it reads 1.
    ("Flattener.swift", "shapeHeightLow", "0.5", "0.0", "shapeHeightLow-lowered"),
    # THE AREA FLOOR, and the LAST of the shape term's six constants to get an entry. The
    # other five are `shapeRunHigh`, `shapeHeightHigh`, `shapeHeightLow`, `lineGapFactor`
    # (two directions) and `lineMinimumMembers`.
    #
    # ⛔ THIS ONE IS DIFFERENT FROM THE OTHER FIVE AND THE DIFFERENCE IS WHY IT WAS ASKED
    # BEFORE IT WAS FIXTURED: it is live in TWO places. `textShaped`'s first guard
    # (`Flattener.swift:2135`) and the calibration's `sized` filter (`:2267`), which is
    # upstream of `glyphHeight` and `glyphRun` and therefore upstream of every bar the other
    # five are multiplied into. So in principle a move of it can imitate a move of any of
    # them, by moving what they are a ratio of — the imitation problem `c28-gap-fixture`
    # measured, one level up.
    #
    # ✅ MEASURED 2026-09-11, AND IT DOES NOT — which took a run of its own, because the
    # bare mutant against the suite as it stood came back **`SURVIVED`, 293 s,
    # `1371/1371 passed`**, nothing objecting. All four calibration readings held at
    # 25.0 / 5.0 with the `sized` filter at 99, and that is a measurement rather than an
    # argument: `c28Calibration` reads this constant itself, so the mirror filtered at 99
    # too and the literal it is compared against is the third party.
    # ⚠️ THE MECHANISM BELOW IS REASONED AND THE MEDIANS ARE WHAT WAS MEASURED — the two
    # must not be quoted as one thing. At a 44 px Helvetica em the only stencil components
    # carrying under 99 px of ink should be the i-dots (~20-25 px each, 3 a line, 42 over
    # `c28Dense`'s 14 lines), every letter clearing it on the thinnest reading — an `l` at
    # ~4 x 34 = 136, an `i` stem at ~4.5 x 25 = 112 — so the height median stays inside the
    # x-height block and the dropped dots' `medianRun` is the median itself. No component
    # census was taken; what the run establishes is that `glyphHeight` 25.0 and `glyphRun`
    # 5.0 both HOLD, which is what `c28Cal`, the `c28SplitCal`/`c28JoinedCal` pair and
    # `c28ShortCal` assert.
    #
    # ⛔ A DRAFT SAID THE MUTANT IS "MONOTONE IN THE REFUSING DIRECTION, so every check
    # asserting ZERO groups is unfalsifiable under it". REFUTED by the review of that diff
    # from this repo's own standard: `textLines` bands greedily off each band's LAST member
    # and flushes on a gap, so removing a component can split one run into two groups — the
    # count is not monotone in the accepted set, and the test is *"does the mutant change
    # this check's INPUT"* rather than *"could the count move in principle"*.
    # ⚠️ AND THE ZERO-ASSERTING SET IS **EIGHT**, NOT SEVEN — `c28BorderGroups` was missing
    # from the draft's list in four files: `c28TooWide`, `c28TooTall`, `c28TooShort`,
    # `c28GapSplit`, `c28GroupsBoxed`, `c28GroupsBar`, `c28GroupsC26`, `c28BorderGroups`.
    # `c28TooShort` is worth naming: its four 5x8 marks are refused by the height floor at
    # the shipped value and by the AREA floor at 99 (40 < 99), so the answer holds while its
    # reason changes silently underneath. ⛔ And the kill SURFACE was never three checks —
    # the `const/lineMinimumMembers` row below shows six, the three group checks plus the
    # three `c28Missed` WIRING rows, which assert a width and a flag rather than a count.
    #
    # THE FIXTURE, `c28TooSmall`: `c28Dashes(4, 16)`, i.e. `c28Stroke`'s four marks at the
    # same four x positions, 4 px wide and 16 px tall. At the asserted `glyphHeight` 25.0
    # every OTHER term accepts them — 16 >= 12.5, 16 <= 75.0, `medianRun` 4 <= 10, and the
    # `260 - 203` = 57 px gaps are under the 75 px bar — so the area guard is the only term
    # that can refuse: 64 >= 4 accepts and reads 1, 64 < 99 refuses and reads 0. The inverse
    # row is `c28Stroke`'s existing positive control (150 px of ink, accepted at both
    # values), so the pair differs in AREA alone and costs no third page.
    # ⛔ ITS CHECK IS **NOT** DISJOINT FROM THE GROUPING MUTANTS' AND MUST NOT BE WRITTEN AS
    # IF IT WERE — predicted before the run rather than found after it. It asserts 1, so it
    # also reds under `const/lineMinimumMembers` (4 -> 99) and `const/lineGapFactor`
    # (3.0 -> 0.0), exactly as `c28-gap-fixture` measured of its own inverse row. What the
    # attribution rests on is that this mutant's set is a SINGLETON where theirs are seven:
    # no other catalogued mutant reds this check ALONE.
    ("Flattener.swift", "shapeMinimumArea", "4", "99"),
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
    # ✅ THE LAST SURVIVOR, `killed` 2026-08-30 — so the survivor list is EMPTY. ⛔ Not
    # "for the first time ever": at `328d393`, this log's first commit, it held two rows
    # and both read `killed`. What is new is an empty list over a catalogue of 104.
    # It was a GAP IN THE CHECKS and not a value nothing depends on: the two fixtures
    # written to discriminate it varied the two /XObject keys' NAMES, and
    # `CGPDFDictionaryApplyBlock` yields entries in reverse FILE ORDER, so both of them
    # walked the short route first and the mutation was inert on both. Two fixtures that
    # write the SHORT key first — long route second, hence yielded first — split the two
    # rules, and they are in the suite now: baseline `1361 checks, green`, mutant 296 s,
    # `1359/1361 passed`, killed by exactly those two. ⛔ The attribution is that
    # objecting-check LIST, not the older pair's green, which two failures out of 1,361
    # already entail and which is inert by construction anyway. ⚠️ Do NOT read an empty
    # survivor list as coverage: 25 catalogue entries had no row at all when this was
    # written and 21 do as of 2026-08-30 — re-derive it with
    # `len(knownIDs & set(already_done()))`, never from this comment.
    # BUGS.md R25 `#### The fixture, IN THE SUITE`.
    ("Flattener.swift", "if let seen = walkedAt[identity], seen <= depth { return }",
     "if walkedAt[identity] != nil { return }", "R25-depth-aware-prune"),
    # C28's wiring as a MECHANISM rather than as a constant, 2026-08-22, and it is the
    # sibling of `R56-alltext-sees-drawings` below: the third term still runs, still
    # pays for both component passes, and its answer is thrown away. A constant mutant
    # cannot reach this — `lineMinimumMembers` at 99 changes what the term FINDS, and
    # this changes whether the verdict listens. The by-hand equivalent was executed on
    # the way in: two binaries one term apart put the missed-word fixture's background
    # at 153 px against a ceiling of 154 without it and 612 px with it.
    #
    # ⚠️ Its twin is NOT here and that is deliberate rather than an omission. The other
    # wrong reading — `groups ?? 0 == 0`, i.e. a page too dense to label being waved
    # through as all text instead of refused — is a mutant **no fixture can kill**,
    # because nothing a suite can build reaches `maximumShapeRuns` (8,000,000 runs).
    # Planting it would add a known survivor to the catalogue and T5's job is telling a
    # gap in the checks from a value nothing depends on; this one is neither. What
    # covers that reading instead is the `runLimit` parameter and the two checks that
    # execute the branch through it. C24's seam is the precedent for planting BOTH
    # readings of a `nil`, and the reason it does not apply here is that its `nil` was
    # reachable from a fixture and this one is not.
    ("Flattener.swift",
     "            return groups == 0\n",
     "            return true\n",
     "C28-alltext-ignores-shape"),
    # R56's second half, and the one a constant mutant cannot reach. Closing R56 in
    # `isPicture` alone would have moved the harm rather than removed it: the page
    # reaches the picture path and `mrcLayers` then stores it at an eighth of its
    # resolution, because the all-text rule's signal is ink and the drawing is not
    # ink. This plants that back — the sibling defect, not the reported one
    # (CONTRIBUTING 4b).
    ("Flattener.swift",
     "dpi: dpi).extent <= paleDrawingThreshold",
     "dpi: dpi).extent <= 99.0", "R56-alltext-sees-drawings"),
    # C26's measurement seam, in the pair C24's seam taught this register to write. The
    # first says the override is read at all; the second says its `nil` means what its
    # doc comment says — "the shipped bar", not "refuse the page". C24 shipped with only
    # the first reading pinned and the *nearer* wrong one then survived nine checks, so
    # both go in together this time rather than one of them after a review.
    ("Flattener.swift",
     "            let bar = textPageInkOutsideThresholdOverride ?? textPageInkOutsideThreshold\n",
     "            let bar = textPageInkOutsideThreshold\n",
     "C26-inkbar-override-ignored"),
    ("Flattener.swift",
     "            let bar = textPageInkOutsideThresholdOverride ?? textPageInkOutsideThreshold\n",
     "            let bar = textPageInkOutsideThresholdOverride ?? 0\n",
     "C26-inkbar-nil-refuses-the-page"),
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
    # The same guard at the OTHER boundary, and the two below are a matched set. The two
    # walks' caps are `< 3` here and `< 4` in `largestImage`: different numbers for the same
    # reach *on a chain whose forms each carry their own `/Resources`*, because one counts
    # forms entered and the other counts resource dictionaries from the page's own at 0.
    # Loosening either by one makes that walk see an image inside a FOURTH nested form while
    # the other still cannot — the divergence a reader who "reconciles" the numbers believes
    # they are removing, and the reason the 2026-08-17 decision to set this to `< 4` was
    # retracted. ⚠️ On a chain of BARE forms the reaches are not equal to begin with (this
    # walk spends a level on a bare form and that one does not), which is page 14 of
    # `shared-resources.pdf` and the queue's `bare-form-reach`; it does not change what
    # either mutant does.
    #
    # Corpus reachability is asymmetric and the two halves are not the same kind of claim:
    # moving THIS cap between `< 4` and `< 3` was measured byte-identical over all 16,987
    # pages (`c17b3f3`), while `largestImage`'s `< 4` has never been moved over the corpus at
    # all — and that walk reads `/Resources` whether or not the form is drawn, so the first
    # measurement does not carry over to it. Either way pages 11-14 of `shared-resources.pdf`
    # are what can kill these; both mutants were added 2026-08-23 with those pages.
    # ✅ Both `find` strings were checked UNIQUE in `Sources/Flattener.swift` by hand, so
    # neither will be reported NOT-APPLIED (T7's lesson, recorded at `run`'s `hits != 1`) —
    # `--self-test` never touches OPERATORS, so nothing automated asserts that.
    # ✅ BOTH RUN through this tool 2026-08-25 and both `killed` — 227 s by SIX objecting
    # checks (the drawn one) and 244 s by THREE (the dictionary one). The asymmetry is a
    # product fact rather than fixture bias: the three rows only the drawn mutant reddens are
    # the three that reach `rebuildDPI(of:)`, which routes `.noImage` to
    # `rebuildDPI(from: nil)` and never consults `largestImage` — so a loosened DICTIONARY cap
    # is invisible at the seam on every page whose drawn walk goes blind.
    # ⚠️ Two of that block's nine rows are red under NEITHER, said in advance: the premise row
    # reads `drawsAnyXObject`, which has no depth guard at all, and page 12's control has
    # nothing below `/FD` for a fourth level to admit. A NARROWING mutant would redden both,
    # and none is catalogued. See `BUGS.md` C24's `#### Both caps RUN through mutate.py` for
    # the tallies and `#### The two caps, and the chain they are equal on` for which rows the
    # earlier one-token sabotage BINARY had watched and which it only reasoned about.
    ("Flattener.swift", "guard s.depth < 3, let table = s.table else { return }",
     "guard s.depth < 4, let table = s.table else { return }",
     "C24-drawn-cap-reaches-further"),
    ("Flattener.swift", "guard depth < 4 else { return }",
     "guard depth < 5 else { return }",
     "C24-dictionary-cap-reaches-further"),
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
    # this wiring: on the other thirteen this mutant answers identically — it read "the other
    # nine" until 2026-08-23, when pages 11-14 were added; the verdict does not move, because
    # pages 11 and 12 answer 1200 px and 2400 px, both over `minimumScanPixelWidth`, and
    # pages 13 and 14 never reach the `.largest` branch at all. Run by hand before it
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
    for entry in CONSTANTS:
        f, name, old, new = entry[:4]
        # ⛔ A FIFTH ELEMENT OVERRIDES THE ID, and it exists because the id was derived
        # from the constant's NAME alone while `already_done()` is keyed on the id and is
        # last-row-wins. So a second entry for a constant that already has one — the two
        # DIRECTIONS of `lineGapFactor`, which is the case that found this — would have
        # produced the catalogue's first duplicate id, and the consequence is silent in
        # the direction that loses work: the new mutant reads as already recorded, is
        # skipped without `--rerun`, and shares one log row and one coverage slot with a
        # mutant it has nothing to do with. `--only` would select both under either name.
        # The alternative was an OPERATORS entry, which buys a unique id by calling a
        # constant move `logic/` and giving up the anchored declaration pattern below;
        # rejected for that. `self_test` asserts uniqueness, so the next entry that
        # collides says so instead of being absorbed.
        ident = entry[4] if len(entry) > 4 else name
        out.append({
            "id": f"const/{ident}", "file": f, "kind": "constant",
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
    re-run of a mutant, ~45 minutes on the pre-2026-08-24 clamp — and one thing it DOES report falsely, which is
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

def objecting_checks(out):
    """The FAIL lines a mutant's suite printed, whole, in the order printed.

    ⛔ **It does not split the name off the detail, and that is the point.**
    `check()` in Tests/main.swift prints `FAIL <name>` or `FAIL <name> — <detail>`,
    and the same `" — "` occurs *inside* 38 of the suite's check names. So
    `FAIL a — b` is genuinely AMBIGUOUS — it is "name `a`, detail `b`" and "name
    `a — b`, no detail", and nothing in the line distinguishes them. **No split is
    correct**, which is why this keeps the line.

    `run` split at the FIRST separator for the whole of this tool's history, which
    truncated every name containing one. Measured on the rows it damaged: **at least
    7 of the log's 83**, and the honest count is a floor because a truncation that
    leaves a readable sentence is invisible to inspection — `logic/C24-page-draws-
    nothing` records the bare tag `C24`, five rows record
    `…and a page carrying a pale drawing does not` where the check ends
    `— R56's other half`, and this run recorded `C28`. Five of those NAMES are
    recoverable from `Tests/main.swift`, because the truncated head matches exactly
    one description; the `C24` one is not, because a bare `C24` matches **nine**.
    None of the six is recoverable in the format below, which keeps the whole line:
    their details went with `mutation-out/`, gitignored and rewritten per run.

    ⚠️ Splitting at the LAST separator instead — the obvious fix, and the one this
    function shipped as a draft — is **not** a fix: it truncates a name whose
    separator is its own and which was called with no detail (`C24 — the rebuild-DPI
    override is nil until something sets it`, Tests/main.swift, is exactly that
    shape), and it corrupts the 22 call sites whose *detail* holds a separator,
    where the first-separator split was right. Keeping the line is wrong in no case.
    """
    lines = []
    for line in out.splitlines():
        line = line.strip()
        # A prefix, not a substring: `"FAIL" in line` would collect a check whose
        # own text says FAIL, and the count below is what a row's `N check(s)` is.
        if line != "FAIL" and not line.startswith("FAIL "):
            continue
        # The log this feeds is TSV and `record` does not sanitise. A tab inside a
        # check's own text would add a field and put every later column under the
        # wrong header — the defect class T14, A12.3 and T18 each paid for once.
        lines.append(" ".join(line[5:].split()))
    return lines


def killed_detail(fails):
    """The `detail` field of a `killed` row: the count, then EVERY objecting check.

    ⛔ **It keeps them all, and that is the fix.** `run()` wrote
    `"; ".join(fails[:3])` for the whole of this tool's history, and the loss lands in
    the field that is the only DURABLE copy: `Tools/mutation-out/` is gitignored and
    rewritten per run, so once the next mutant runs, a name not in this row exists
    nowhere a later session can read. That is the **second** truncation defect in this
    one field — the first was `objecting_checks`' split at the first separator, fixed
    2026-08-23 — which is why the sibling was worth looking for at all.

    ⛔ **It was already live, and reading the log refutes the first draft of this
    docstring.** That draft said nothing had ever hit the cap and
    `const/lineMinimumMembers` (killed by five, three named) was the first — a claim
    about the log made without reading it. Swept over all 84 rows for `N check(s)`
    with `N > 3`: **five earlier rows were truncated and 10 names went with them** —
    `logic/A4.2-update-url-scheme` (5 announced, 3 named),
    `logic/R82-reserve-taller-scale` (5/3), `logic/R23-copyOutline-bound` (4/3),
    `logic/C24-unknown-is-not-no` (6/3) and `logic/C24-override-ignored` (5/3). The
    COUNT is right in all five, so every row states its own incompleteness and no
    number in the log is wrong; what is gone is which checks. ⚠️ None of the 10 is
    recoverable from the tree, for the same reason the split defect's six are not.
    They are recoverable by re-running those five mutants, which after the 2026-08-24
    ProcessType/`-O` fixes is minutes each rather than the ~45 it was when they ran —
    not done here, and not a claim that it is free.

    ⚠️ Do not read the two defects' row counts as disjoint: 7 damaged by the split and
    5 by the cap, in the same field, unswept for overlap.

    ⚠️ A MARKED cap (`…; and 2 more`) was the other option and is rejected: it costs
    the same edit, makes the row honest about the loss and still leaves the names
    unrecoverable, which is the thing a later session needs. Completeness costs a
    reader nothing here, because the console line is truncated separately
    (`detail[:70]` in `run`) — the console was never the durable copy and the two
    truncations were never the same decision.

    ⚠️ Unbounded on purpose. A `logic` mutant broad enough to redden fifty checks
    would write a long row; a long row is legible and a short one that dropped
    forty-seven names is not. So length is a reader's problem and silence is a
    correctness one.

    ⛔ **One consumer DOES machine-read this field, and a draft of this docstring said
    none did.** `logged_seconds` tests it with `ABORTED_DETAIL.match(f[3])` — an
    anchored `^exit \\d+, no FAIL line` — to drop crashed runs from the estimate. It is
    safe because every string this function returns starts with `"{n} check(s): "`,
    which that pattern can never match however long the row gets. ⚠️ Note what that
    means: the `N check(s): ` prefix is not cosmetic, it is what keeps a `killed` row
    out of the aborted bucket — and it is pinned by the second of the two self-test
    checks below, which was written for the count and turns out to guard this too.
    Nothing else parses the field (swept 2026-08-24 over `Tools/`, `ops/`, `.githooks/`
    and the documents).

    ⚠️ `killed_detail([])` returns `"0 check(s): "` with a trailing space and is
    unpinned. Unreachable from `run`, which guards on `if fails:` and takes the
    crash branch otherwise, so it is latent rather than live.
    """
    return f"{len(fails)} check(s): " + "; ".join(fails)


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
    2026-08-17 by applying each one to a copy of this file and running the flag.
    ⚠️ That denominator predates `killed_detail` and its two checks (36 -> 38,
    2026-08-24): three mutations of that function are killed by them by inspection
    (`len(fails)` -> `len(fails[:n])`, dropping the count prefix, `"; "` -> `", "`), but
    nobody re-ran the campaign, so 26 is stale in the direction that flatters it and is
    left alone rather than argued upward — which is what this paragraph says to do. Every
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
    free nor informative: no numbers, one suite run per mutant (~45 min before the
    2026-08-24 ProcessType/-O fixes, far less after), and `mutate.py` does not take
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

    # LAST-ROW-WINS, the rule this file's own docstring states and nothing asserted.
    # It is what decides the CURRENT verdict of every re-run name in the log. Derive
    # the exposure rather than trusting this comment (`cut -f1 … | uniq -d`, then
    # compare each name's first row with its last): on 2026-08-29 ten names carried
    # duplicates and TWO of them disagreed first-against-last, both SURVIVED -> killed,
    # so a first-row-wins reading would have reported two dead mutants as live
    # survivors off rows that are all well-formed. The converse — a survivor read as
    # killed — is equally possible and is simply not instantiated today.
    # The four checks above pin which rows are ADMITTED, by FIELD COUNT, and are silent
    # both about which of two admitted rows is believed and about the verdict's value.
    #
    # Two-sided on purpose: the same pair in both orders. One direction alone is
    # satisfied by any implementation that happens to return "killed" — including a
    # constant — and this project has a long history of checks that could not fail.
    check("two rows for one name: the LATER row is the verdict, in both orders",
          already_done(log_with([("c", "SURVIVED", 283, "d"),
                                 ("c", "killed", 284, "d")])).get("c") == "killed"
          and already_done(log_with([("c", "killed", 284, "d"),
                                     ("c", "SURVIVED", 283, "d")])).get("c") == "SURVIVED")

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

    # `objecting_checks`, the parse that puts a check's name into
    # `mutation-log.tsv`. It had no coverage here at all while being the only route
    # from a red check to the durable record, and it truncated at the first
    # separator — so a `killed` row recorded `C28` where the check is a sentence.
    # ⚠️ **Cases (1)-(3) are mutually redundant AS DETECTORS and are kept anyway.**
    # Measured over eight implementations: any parse that splits at all goes red on
    # all three, so their columns are identical and (2) and (3) catch no mutant (1)
    # misses. They stay because they are the three real shapes that make splitting
    # unfixable, and the next reader's instinct is to "fix" this by splitting at the
    # last separator instead — (2) is that patch's counter-example, in the tree.
    # **(4), (5) and (6) are each load-bearing**: exactly one wrong implementation
    # in that sweep is caught by each and by nothing else here.
    #
    # (1) The line this run actually produced, verbatim from `mutation-out/`. Both
    # the first-separator split and the last-separator one truncate it.
    real_c28 = ("  FAIL C28 — a page with one unrecognised word of type is not "
                "shrunk as all text — 153 wide of 1224, ceiling 154")
    check("a FAIL line is kept whole, separators and detail and all",
          objecting_checks(real_c28)
          == ["C28 — a page with one unrecognised word of type is not shrunk as all "
              "text — 153 wide of 1224, ceiling 154"])
    # (2) The case that kills the last-separator split, which is the fix a reader
    # will propose. A real check name, called with NO detail: its own separator is
    # the last one on the line, so `rsplit` records the bare tag `C24`.
    check("…including a name whose own separator is the last thing on the line",
          objecting_checks(
              "  FAIL C24 — the rebuild-DPI override is nil until something sets it")
          == ["C24 — the rebuild-DPI override is nil until something sets it"])
    # (3) Two separators in one name — the `tonal-plate` check builds exactly this
    # by concatenation, and a split-at-the-second implementation passes (1) and (2).
    check("…and a name carrying TWO separators is not cut at either",
          objecting_checks("FAIL tonal-plate routes to the picture path — R57 — "
                           "1-bit makes it a solid black blob")
          == ["tonal-plate routes to the picture path — R57 — 1-bit makes it a "
              "solid black blob"])
    # (4) The log is TSV and `record` does not sanitise, so a tab in a check's own
    # text would add a field. Nothing else here would notice.
    check("a tab inside a check's text cannot add a TSV field",
          objecting_checks("  FAIL a name\twith a tab — and\ta detail")
          == ["a name with a tab — and a detail"])
    # (5) A prefix and not a substring: `"FAIL" in line` collects prose about
    # failing, and the length of this list is a row's `N check(s)` count.
    check("a line that merely mentions FAIL is not a failing check",
          objecting_checks("  ok   the writer reports FAILURE loudly\n"
                           "FAILURES: 0\n  FAIL the real one — d") == ["the real one — d"])
    # (6) Order and the `ok` rejection — catches a set/dedup, a first-only return,
    # and a parse that collects the passing lines too.
    check("every FAIL is collected in order, once each, and no `ok` line is",
          objecting_checks("  ok   first is fine\n  FAIL b — d\n  ok   c\n"
                           "  FAIL a — d\n  FAIL b — d\n")
          == ["b — d", "a — d", "b — d"])

    # `killed_detail`, the OTHER half of the same field, and the half that had no
    # coverage at all. (7) is the case that found it: the row for
    # `const/lineMinimumMembers` announced `5 check(s)` and named three, because
    # `run()` joined `fails[:3]` — and the sweep that followed found the cap had
    # already truncated five EARLIER rows and taken 10 names with them, so this was a
    # live defect and not a latent one. Written so that a cap at ANY value goes red,
    # not just at three: a "fix" raising it to four passes a test written against five
    # alone, and (8) is what catches that (watched failing at `[:6]`, which (7) passes).
    seven = [f"check number {i}" for i in range(1, 6)]
    check("a killed row lists EVERY objecting check, not the first three",
          killed_detail(seven)
          == "5 check(s): check number 1; check number 2; check number 3; "
             "check number 4; check number 5")
    # (8) The count and the names cannot disagree, at any width. This is the property
    # a later session reads the row FOR — `mutation-out/` is gitignored, so a name
    # missing here is a name gone. Checked over 1..8 rather than at one width so no
    # cap survives, and by substring per name rather than by re-splitting on `"; "`,
    # which a check description could itself contain.
    widths_ok = True
    for n in range(1, 9):
        names = [f"objecting check {j} — with a separator" for j in range(n)]
        d = killed_detail(names)
        if not d.startswith(f"{n} check(s): "):
            widths_ok = False
        for nm in names:
            if nm not in d:
                widths_ok = False
    check("…and its `N check(s)` count is the number of names it actually carries",
          widths_ok)

    # (9) The catalogue's ids are unique. ⛔ Not hygiene: `already_done()` is keyed on the
    # id and is last-row-wins, so a duplicate makes the SECOND entry read as already
    # recorded — it is skipped without `--rerun`, both share one log row and one coverage
    # slot, and `--only` cannot tell them apart. Every one of those failures is silent and
    # in the direction of doing less work than the log claims. This was reachable from
    # 2026-09-11, when `lineGapFactor` became the first constant with two entries; the
    # fifth-element override in `catalogue()` is the escape and this is what says it was
    # used. ⚠️ Over the real catalogue and not a fixture, because the property wanted is
    # of the shipped table — a fixture would only test `collections.Counter`.
    ids = [m["id"] for m in catalogue()]
    dupes = sorted({i for i in ids if ids.count(i) > 1})
    check(f"every catalogue id is unique ({len(ids)} entries)" + (f" — {dupes}" if dupes else ""),
          not dupes)

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
                fails = objecting_checks(out)
                if fails:
                    detail = killed_detail(fails)
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
