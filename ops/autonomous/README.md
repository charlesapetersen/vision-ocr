# Unattended runs — the autonomous daemon

A way to run Vision OCR maintenance overnight that survives usage cutoffs, context compaction and a closed
laptop lid. It fires a fresh headless `claude -p` every cycle to advance the queue by **one bounded item**,
then that session commits, pushes and stops.

Scaled down from the Archive Suite daemon (`~/Claude/Archive Suite/ops/autonomous/`). §*What this
deliberately does not have* records what was cut and why, because the reasons are the useful part.

**What "scaled down" actually means here — measured, not asserted:**

| | Archive Suite | this | |
|---|---|---|---|
| helper + daemon scripts | 16 | **11** | fewer moving parts |
| proof harnesses | 15 | **5** | it guards far less machinery |
| core shell lines | 4,295 | **4,614** | *no longer fewer at all* |
| harness lines | 2,866 | 2,179 | |

⚠️ **Two of those numbers were wrong and are corrected here, re-counted 2026-08-17 with `wc -l`.** The
harness row read **2** while three harnesses were committed — it was written when two existed and was never
re-counted as `prove-status.sh` landed, which is the ordinary way a measured figure rots into an asserted one.
It is **4** now that `prove-stop.sh` exists (README §Defects D5: `daemon.sh` had no coverage, and it was the
file that failed). The core-shell row read **3,668**; the real count is **4,381**, so the "only ~15% fewer"
claim below has become "slightly more" — the honest reading of the paragraph that follows is now stronger, not
weaker, and the row is left in place rather than quietly dropped.

⚠️ **And they rotted again inside a day — re-counted 2026-08-18 with `wc -l`: 4,479 and 1,702.** The
**4,381 / 1,515** pair above was already wrong before this commit touched anything: at `dddcbf6` the true
counts were **4,451 / 1,642**, so `prove-stop.sh`'s own repair and the four commits after it moved both rows
within twenty-five minutes of the recount that was supposed to fix them. That is the third time these two
numbers have gone stale, which is the argument for the row's `wc -l` recipe being written down here rather
than for anyone's diligence: `wc -l ops/autonomous/*.sh` and `wc -l ops/autonomous/tests/*.sh`, whose totals
are the two figures. Re-run those two commands when you add a section; do not carry the number forward.

⚠️ **And again on 2026-08-19 — 4,614 and 2,179, re-counted with the recipe above rather than adjusted.** The
harness row also goes **4 → 5**: `tests/mutate-test-lock.sh` is the new one, a shell mutant catalogue for
`test-lock.sh` (there was none — `Tools/mutate.py` covers `Sources/` only). That is the fourth time these two
numbers have moved, which is why the recipe is here and the numbers are not to be trusted between commits.

⚠️ Note the third row, because the honest reading is not the flattering one: **the line count is barely
down.** This repo's house style is heavy "why this exists" commenting that records the incident behind each
guard, and that style was kept deliberately — it is most of the value in the original and the first thing a
smaller port would be tempted to drop. What genuinely shrank is the number of **mechanisms** and the surface
they have to be proven over: no second tracker to police, no per-file byte budgets, no doc-fix attempt
counter, no paced-review cadence, no VM lane to build. Counting lines would make this look like a modest
edit; counting mechanisms is the right measure, and by that measure it is roughly half the system.

## Start / stop / check in

```bash
mkdir -p ~/.local/state/visionocr-autonomous
cp ops/autonomous/RUN.md.template ~/.local/state/visionocr-autonomous/RUN.md   # once, then edit ## FOCUS
git config core.hooksPath .githooks                                            # once per clone

./ops/autonomous/daemon.sh start        # install + check prereqs + launch under launchd KeepAlive
./ops/autonomous/daemon.sh status       # the check-in surface (read-only)
./ops/autonomous/daemon.sh status --details
./ops/autonomous/daemon.sh stop
./ops/autonomous/daemon.sh --dry-run    # preview the resolved launch mode, install/launch nothing
```

`start` checks every prerequisite with a fix hint, installs the committed copies to `~/.local/bin`, refuses
to double-launch, warns if the pre-commit hook is not configured, and confirms the first cycle started.
Default mode is a launchd LaunchAgent with `KeepAlive=true`, so a crash or OOM restarts it; the only thing
that stops it is a `bootout`, which every intentional stop performs. It survives a daemon crash, **not** a
logout or reboot — reboot survival is deliberately out of scope.

```bash
tail -f ~/.local/state/visionocr-autonomous/daemon.log          # cadence + each session's rc
tail -f ~/.local/state/visionocr-autonomous/last-session.log    # the current session's transcript
cat     ~/.local/state/visionocr-autonomous/STATUS.md           # same digest as `daemon.sh status`
```

## The three layers

- **L0 — durable state is THE REPO.** `BUGS.md` (the register), `TODO.md`, `ops/autonomous/QUEUE.md` (the
  order) and `git log` are all committed and pushed, so any fresh session recovers full state from them.
  Only the run's own bookkeeping — `RUN STATUS`, the owner's `## FOCUS`, the session log — lives outside, in
  `~/.local/state/visionocr-autonomous/RUN.md`.
  **This is the main structural difference from the daemon this was ported from**, whose queue lived in a
  gitignored 130 KB plan file that duplicated the committed tracker. That duplication cost three separate
  scripts to police, and its own README's verdict is blunt: *keep one list and all three evaporate.*
- **L1 — the daemon** (`vision-ocr-autonomous.sh`). A loop that fires one fresh `claude -p` per cycle, with
  idle backoff, an auto-park, a health gate, watchdogs and housekeeping. Never bypasses permissions:
  `--permission-mode default` plus a scoped `--allowedTools` and a destructive `--disallowedTools` denylist.
- **L2 — the resume prompt** (`resume-prompt.txt`). The exact instructions each fresh session follows:
  recover state → pick the first actionable item → own worktree → failing test first → verify → commit with
  the documents → push → record → stop. Committed with a `__REPO__` placeholder, rendered at install time.

## ⚠️ The one thing this daemon needs that the original did not: a suite lock

`test-lock.sh` is the first file of this system rather than an afterthought, and it is the piece to
understand before changing anything.

CLAUDE.md's first environment trap: **never run two suites at once, in any two worktrees.** `build/tests` has
no bundle identifier, so `UserDefaults.standard` lands in `~/Library/Preferences/tests.plist` keyed by the
process *name*, and every worktree shares that one file. A second suite's `resetPrefs()` wipes the first
one's settings mid-run — measured 882/883 → 877/879, with two failures in the run-report block that had
nothing to do with the change under test.

A human hits that rarely, by forgetting. **An unattended daemon hits it structurally**, in three ways at once:
every code commit runs the suite via `.githooks/pre-commit`; the health gate runs the suite on a cadence in
the daemon loop; and the owner keeps working interactively in the primary checkout meanwhile. So:

- the health gate runs `./run_tests.sh` through `test-lock.sh`;
- the resume prompt tells every session to do the same, including for any subagent it launches;
- **`.githooks/pre-commit` takes the lock too.** That is the one edit this work makes to existing committed
  infrastructure, and it protects the owner's own interactive commits — the collision needs only one
  careless party, and now neither party can be one. It degrades exactly to the old behaviour when
  `ops/autonomous/test-lock.sh` is absent, so an older checkout is unaffected.

The lock is a `mkdir`-atomic directory recording the **caller's** pid, so a holder killed mid-run (a closed
lid, a watchdog TERM) is reclaimable the instant its pid is gone rather than after a timeout. It also
consults `pgrep -x tests`, which catches a suite started by something that never heard of the lock — and it
is `-x`, never `-f build/tests`, because the `-f` form matches every waiter including its own shell, which is
how four loops once sat waiting on each other while nothing ran.

## How long things actually take — and why one number was never going to do

Every timing constant in this daemon was originally derived from a suite believed to take **3-6 minutes**.
That figure was never measured by anyone: the commit that last touched it says so in its own message —
*"DURATIONS ARE NOT MEASURED … I did not time the run, so that figure is inherited, not established."*

✅ **RESOLVED 2026-08-24, AND THE ANSWER WAS NOT "LOAD" — IT WAS THE SCHEDULING BAND PLUS A MISSING `-O`.**
This section stood for eight days concluding that the suite "has no single duration on this machine" and that
one should "plan against the load, not a number". The variance was real; the diagnosis was wrong. Two
defects, measured end to end at `8d00504` with 1,247 checks on a machine still holding 4.0 GB of swap:

| defect | ratio | |
|---|---|---|
| `ProcessType=Background` in this daemon's launchd plist | **5.14x** | 3,643 s → 709 s |
| `run_tests.sh` passed no `-O` (test phase 618 → 103 s) | **3.15x** | 709 s → 225 s |
| together | **16.2x** | **3,643 s → 225 s** |

`Background` is darwin-bg — lowest QoS, I/O throttled, threads on the E-cores — and `man taskpolicy` says
all children inherit it, so the clamp reached launchd → daemon loop → claude session → `git commit` →
pre-commit hook → `run_tests.sh` → `build/tests`, and it survived the parent's death. **So the "what else
was running" column below is really a "who launched it" column**: the fast rows are the owner's hand-started
runs, the slow ones are the daemon's. Loadavg explains **7%** of the variance with its extremes INVERTED
(474 s at load 3.47 beside 3,569 s at load 3.59); durations went **UP** across the 2026-08-21 reboot, so the
wired-memory leak cost ~3%, not 500%; and memory pressure is excluded, because the 709 s run happened while
the machine was swapping. Full account, including why it cannot be fixed in `test-lock.sh`: the `ProcessType`
comment in `com.visionocr.autonomous.plist`.

⚠️ **The table below is KEPT AS THE RECORD AND IS NOT REWRITTEN — every row really did take that long.** But
no row in it is comparable to a run dated after 2026-08-24, and neither is any pre-2026-08-24 row of
`$STATE/suite-timings.tsv`. What it was originally timed for, on 2026-08-16:

| when | duration | what else was running |
|---|---|---|
| 09:47, via `Tools/mutate.py` | **416–632 s** per run | quiet machine |
| 17:54, health gate (tools-compile + suite + `build.sh` + doc checks) | **44m 53s** | daemon loop only |
| 20:29, timed directly under the lock | **39m 30s** | a daemon session + an interactive session |
| 21:42, a real `pre-commit` run | **~37 min** | same |
| 22:34, a `pre-commit` run | **474 s (7m 54s)** | daemon STOPPED, load 3.47 — the ledger's first row |
| 22:47–03:14 (2026-08-17), the C24b mutant campaign, 6 runs | **2621–2719 s** per run | daemon + an interactive session; ledger row records loadavg **2.39** at completion |
| 03:22–04:04 (2026-08-17), a real `pre-commit` run | **2,552 s (42m 32s)** | daemon + this session, loadavg **4.20** |

The first row read **80–632 s** until 2026-08-17. Its floor was not a fast suite: `logic/R24-safeInt-finite`
at 80 s and `logic/R30-monotonic-underflow` at 89 s are `exit 133` — crashes 80 and 89 seconds in, correctly
scored as kills and not durations at all (BUGS.md C24b). `Tools/mutate.py` now excludes them from its own
estimate; every doc that quoted 80 s as this suite's floor was quoting a suite that died.

Between 09:59 and 21:42 no commit added a test — the suite did not get four times slower, **the laptop got
four times busier** (load average ~5 by the evening). That much still holds.

⚠️ **What does NOT hold is the sentence this paragraph used to end with**, and the retraction is the point of
the ledger existing: it read *"with the daemon stopped, the same suite on the same tree took 474 s against
2370 s, a 5x swing from load alone."* The swing is real — 474 s against ~2,669 s per campaign run is
**5.6x** — but "from load alone" does not survive the ledger's own three rows. Sorted by duration they are
474 s, 2,552 s, ~2,669 s; sorted by the loadavg column, 2.39, 3.47, 4.20. **The column does not order the
durations**: the fastest run happened at the middle load average and the slowest at the lowest. One pair
points the way load would predict and the other points the opposite way, over the same suite on the same
laptop within thirty hours.

What might explain it, filed as an inference and not a finding: the campaign's session saw OneDrive at ~50%
of a core and CrashPlanService at ~24% while the suite sat single-core bound at ~96%, so contention for that
one core is the plausible term, and neither of those processes moves a 1-minute load average much. Nobody
has run the controlled experiment. So a constant derived from any one of these rows is a reading of the load,
**and a covariate derived from the loadavg column is not enough to correct for it** — which is a stronger
reason to keep the ledger than the one this section was written with.

⚠️ **The suite is corpus-free**, which is worth knowing before reasoning about its cost: `testdocs/` appears
in `Tests/main.swift` only in three comments, and nowhere in `Sources/`, `Helper/` or `run_tests.sh`. It
synthesises its own PDFs and OCRs those. Corpus work is done by `Tools/score-*` on purpose, by a session
that decided to; writing the corpus is an owner-only `[hold]`. Nothing runs the corpus on a commit.

### The ledger, and how to re-derive a timeout

Rather than pick a number, `test-lock.sh run` now records **every** suite that passes through it — the gate,
`.githooks/pre-commit`, and every session — to `$STATE/suite-timings.tsv`:

```
when                 label            seconds  rc  loadavg1
2026-08-16 22:19:31  pre-commit 34226 2201     0   4.42
```

The load average is there because without it two rows are not comparable. To size a timeout, take the
**worst** row you are willing to survive and add headroom; do not take the mean, and do not take one run.
That is the whole method — the file is the authority, and this README is not.

Two constants were wrong by enough to cause real failures:

- **`GATE_MAXRUN` was 2700** and the gate measured **2693**. Seven seconds of margin, on a cap whose
  overrun counts as a TIMEOUT, two of which **park the run**. Raised to 9000, and to 14400 on
  2026-08-19 — see the third bullet.
- **`test-lock.sh`'s wait was 1800** — shorter than a single loaded-machine suite. Anything queued behind a
  healthy run gave up early, and `pre-commit` then announced the lock "never freed". Now 3600.
- **Both wall-clock caps were 9000, and neither was sized against the ledger's worst row.** `MAXRUN` and
  `GATE_MAXRUN` were derived against a 39m30s suite. `suite-timings.tsv`'s 14 pre-commit rows span
  **474-5554 s** (8-93 min), and loadavg does not predict where a run lands — 864 s was measured at 12.64,
  3569 s at 3.59 — so there is no quiet-machine discount to size against. ✅ **That last sentence was true
  and its cause is now known (2026-08-24): the predictor was never load, it was the scheduling band — see
  the top of this section.** A gate is one suite plus up to a 3600 s lock wait, so both caps sat under
  worst-case runtime. Now 14400. ⛔ **DO NOT RESCALE THEM BY THE 16.2x, OR BY ANY RATIO.** The rule this
  file states two bullets down still holds — worst row you are willing to survive, plus headroom, never a
  mean and never one run — two overruns PARK the run, `GATE_MAXRUN` has already been under-sized twice, and
  `GATE_MAXRUN` carries a 3600 s lock-wait term the fix does not shrink. Oversized is the safe direction.
  ⚠️ **And "a CODE commit needs TWO of those runs" was measured FALSE on 2026-08-24**: pairing every ledger
  row against every commit gives a 1:1 hook-to-commit match, and only 3 of 38 code commits have a recorded
  control run — sessions correctly follow `resume-prompt.txt`'s "letting the HOOK be your suite run is the
  cheaper order". The control run is the discipline for a NEW CHECK, not a per-commit cost. What 9000 cost on 2026-08-19: four
  consecutive sessions committed work but completed no item, and the fifth was 27 min into its own hook, on
  course to miss a 20:13 backstop, when the owner stopped the daemon and landed C26 by hand.

And one that was proposed, checked, and **left alone**:

- **`STALE` stays at 1800.** The tempting argument is that a 95-minute session's engine lock looks stale
  after 30 minutes — but the lock is HEARTBEATED (`touch "$LOCK"` every 60 s while the daemon lives), so its
  age measures how long the heartbeat has been dead, never how long the session has run. Raising it would
  only have made crash recovery take 2 h 40 m instead of 30 minutes. The real improvement is recording the
  session pid in the lock and testing `kill -0`; it is a 0-byte file today. Left as a follow-up.

`VISIONOCR_PRECOMMIT_LOCK_WAIT` (default 3600) overrides how long `.githooks/pre-commit` waits for the
lock, independently of `VISIONOCR_TEST_LOCK_WAIT`; it is spelled out in the hook so the number sits beside
the refusal message that quotes it. `VISIONOCR_SUITE_TIMINGS` overrides where the ledger is written.

## The queue, and why there is a second list at all

`ops/autonomous/QUEUE.md` is committed and holds only the **order**, one line per item, each citing the
register entry that owns the content. `next-item.sh` resolves it deterministically — the session is handed
the answer rather than asked to grep for it, for the same reason progress is derived from a hash rather than
self-reported: a model asked to check its own preconditions can conclude it has.

Neither prose tracker is machine-readable as a queue: `TODO.md` encodes status in `## <heading> — done
<date>` suffixes and holds ten checkbox lines in 45 KB, and `BUGS.md` is 163 entries in ~480 KB. But a
daemon needs a deterministic answer to *is there work, is it blocked, or is it drained*, because those are
three different owner actions. So the duplication is bounded to one line per item and policed by
`check-queue-coherence.sh`, which cross-checks each `(origin: …)` cite against the register's status. That
check is the licence for having the second list.

`next-item.sh` exit codes are four different owner actions and must not be collapsed:

| exit | meaning | what you do |
|---|---|---|
| 0 | at least one actionable item | nothing |
| 3 | no open items — genuinely drained | add work, or set `RUN STATUS: COMPLETE` |
| 4 | items exist, ALL blocked or held | unblock something; do **not** add work |
| 2 | malformed queue | fix the file — surfaced, never silently "empty" |

Items support `(blocked-on: TAG[, TAG…])`, resolved against both the queue's own checkboxes and `BUGS.md`
status. A **missing** prerequisite tag counts as unmet, so a typo blocks loudly instead of running work out
of order. `[hold]` / `needs: owner` items are printed but never offered.

## Reading BUGS.md without spending the session on it

`BUGS.md` is ~480 KB ≈ 120,000 tokens. A session that reads it whole has nothing left to work with, so
`bugs-entry.sh <TAG>` extracts one entry, and the resume prompt's **first rule** is to read narrowly.

An entry is **OPEN by exclusion**: closed iff its status suffix begins `FIXED`, `WONTFIX` or `NO DEFECT`.
That is deliberately not a whitelist of "open" spellings — the register's header declares the vocabulary
`OPEN · FIXED · WONTFIX`, but C24 carried `HALF FIXED` for the two days it was half done, so a whitelist would report
zero open entries the day someone coins a new marker. Erring toward OPEN costs a look; erring toward CLOSED
hides work. `next-item.sh` and `bugs-entry.sh` share this rule and must stay consistent — if the resolver and
the extractor disagreed about a status, the queue would offer work whose entry cannot be found.

## Idle backoff, and the auto-park

A cycle that **advances nothing** doubles the gap (`INTERVAL` 90 s → `MAXBACKOFF` 30 min); any progress
resets it instantly; `IDLE_STOP` (72 h) of unbroken no-progress **parks** the run — a clean stop with a loud
signal (log + a Desktop note + a notification + a remote alert). Park leaves `RUN STATUS: IN_PROGRESS`, so a
plain restart resumes with no edit.

**Progress is DERIVED, never self-reported.** A cycle counts as progress iff a fingerprint moved:
`sha256(git HEAD + the RUN STATUS line + QUEUE.md's checkbox lines)`. The model cannot forget to set a flag,
and a session that believes it worked cannot lie past an unchanged hash. Exit code deliberately does not gate
it: a session that ships a commit and is *then* killed still advanced the run, while a usage-limit fast-fail
cannot move the hash and falls through to no-progress on its own. The session log is excluded on purpose — a
no-op session still appends its reasoning there, and hashing that churn would reset the backoff every cycle
and silently restore the spin the mechanism exists to stop.

`IDLE_STOP` is 72 h and not 6 h because a long usage-cap outage is *waiting*, not idling: a weekly cap can
exceed the ~5 h rolling window, and a short clock would park a healthy run that is merely waiting for the
window to reopen.

**The fingerprint is an accelerator, not a gate.** It is tempting to skip the session entirely while it is
unchanged. That was rejected on evidence in the sibling project: a session concluded "nothing actionable" at
09:34, and at 10:40 — identical HEAD and queue — a session found real work and shipped a real fix. These
sessions are nondeterministic, so "same inputs ⇒ same conclusion" is false. An unchanged fingerprint means
only "keep backing off"; a changed one means "retry now", via an interruptible sleep that wakes the instant
the owner edits the queue or `## FOCUS`.

**Attempt cap** — the one waste backoff cannot catch. Backoff keys off the fingerprint *moving*, and a
mis-sized item that commits a checkpoint every session keeps it moving forever. So a second guard counts
consecutive sessions that committed work but completed **no** item, and parks at
`VISIONOCR_MAX_NOCOMPLETE` (5). "An item completed" means a ticked `QUEUE.md` box **or** a newly closed
`BUGS.md` entry — counting only the queue would read a constant through any session whose whole output was
closing a register entry, and would then false-park a healthy run.

Both counters are cleared at every daemon startup, so on-disk state shares the daemon's lifetime. Otherwise a
stale stamp from a prior run makes the first cycle park immediately, turning the owner's restart — an
explicit "try again" — into a single retry.

## The health gate

Every `VISIONOCR_GATE_EVERY` (10) commits the daemon runs `health-gate.sh` itself — deterministic build and
test, so no session and no LLM. A reproducible RED **parks** the run; a timeout is a third, *inconclusive*
state that skips rather than parks, escalating to a park only after two consecutive hangs.

**Why this gate's job is different here.** In the sibling project nothing gated a commit but the session's own
discipline, so its gate was the only regression backstop and ran every 30 commits. Here `.githooks/pre-commit`
already runs the **full suite** on every commit touching
`Sources/|Helper/|Tests/|Tools/|build.sh|run_tests.sh`. So per-commit regression cover is not this gate's job.
Its job is the four things the hook does not do:

1. **`./build.sh`** — the hook builds the app only when a view file is staged, yet `run_tests.sh` excludes
   `App.swift` from the suite entirely, so nothing else proves the app still links.
2. **`Tools/check-tools-compile.sh` over every tool**, not only the staged ones. `score-text-route` had never
   compiled in any commit, and an annotation change silently broke `score-skew` and `score-reading-order`
   eleven days later.
3. **Document coherence** — `check-staleness.sh` and `check-queue-coherence.sh`, both **warn-only**: a
   docs-hygiene nit must never park an overnight run whose builds and tests are green.
4. **A commit that reached `main` with the hook bypassed or unconfigured** (`core.hooksPath` is per-clone,
   which is why `hooks-configured` is a hard gate step and why `daemon.sh start` warns about it).

A RED is **retried once** before parking: a real compounding regression is deterministic and fails again,
while a flake or a suite collision passes. And the park note names the **failing step**, because in the
sibling project a park whose only failing step was a document size check reached the owner as "a reproducible
build/test regression" on "a broken tree" and cost him a morning hunting a bug that did not exist.

`skip ≠ pass`: `step_skippable` exits 3 for SKIPPED and the GREEN summary line then carries
`— NOT VERIFIED: <step>`. A gate that claims coverage it does not have is worse than no gate.

Off by default, both needing extra setup: `VISIONOCR_GATE_GUI=1` adds `Tools/vm-gui-check.sh` (the Tart VM
lane — nine interface checks off-screen), `VISIONOCR_GATE_FAULT=1` adds `Tools/fault-inject.sh`.

## Status — the check-in surface

`status-digest.sh` is the **one** renderer; `daemon.sh status` forwards to it and adds no formatting of its
own, because the original printed six sections and then pasted the digest underneath, so the run state
appeared twice in two wordings and a reader had to know which copy was current. It answers five questions:
*is it running? what has it done? how much is left? is the code healthy? does it need me?*

The run-state line is the point of the whole thing, because each state implies a **different** owner action
and several are historically reported as each other:

*Working now* · *Paused — it hit the usage cap* (wait; it retries itself) · *Waiting for the suite* (it goes
by itself) · *Running, but not finding anything it can do* (unblock it) · *Stopped itself* = parked (decide
something) · *Set to run, but not running right now* (crash-looping) · *Not running*.

Deciding between those lives in `run-state-lib.sh`, sourced by both renderers so the wording cannot diverge.
It exists because that project's status once said "sessions finding no actionable work" for an hour while
every session was being refused by a 429 and the resolver was offering twenty actionable items. **This port
adds a third branch**: a healthy, unthrottled daemon with a full queue can still be sitting still because the
owner is running a suite — reporting that as an empty queue would send them hunting a problem that does not
exist, so it says so instead.

Two honesty guards worth not undoing: the health line reads the last gate's **verdict**, not just the
last-green sha, because a green-only marker is structurally incapable of reporting a gate that has since gone
RED; and every field degrades to `?` rather than erroring, because this is the command you run when something
is already broken.

## Alerting, and where the credential must live

Every park also POSTs to an endpoint you configure, because a Desktop file and a local notification are
useless to an owner who is away — exactly when an unattended run needs them.

```bash
# ~/.local/state/visionocr-autonomous/alert.env
ALERT_URL="https://ntfy.sh/<your-long-random-topic>"
# ALERT_AUTH="Bearer <token>"     # optional, sent as an Authorization header
```

> **`alert.env`, NOT `$STATE/env`** — load-bearing, not style. `$STATE/env` is the **child's** environment
> (the daemon re-sources it under `set -a` to hand variables to `claude -p`), so anything there is inherited
> by every session — and a session is an LLM agent with `Bash` and `WebFetch` whose `curl`/`wget` denylist
> exists precisely so it *cannot* phone out. `alert.env` is sourced once without `set -a`, so the credential
> stays a non-exported daemon-only shell variable. A misplaced `ALERT_*` in `$STATE/env` is additionally
> stripped of its export attribute before the child spawns, as defence in depth.

Unconfigured is a silent no-op, a failed alert is logged but never fatal, and `--max-time` bounds it so a dead
network cannot hang the loop.

## Watchdogs

Each session runs with `--output-format stream-json --include-partial-messages`, so `last-session.log` grows
in real time with an event per message, per tool call, and per token-delta during generation. That last part
is why a long high-effort generation is not mistaken for a hang.

- **Wall-clock backstop** (`MAXRUN`, 4 h) — polls the child's liveness rather than sleeping blindly, so it
  self-exits when the session ends and never fires against a stale or reused pid.
- **Health watchdog** (the primary killer) — two combined signals so no single false positive kills a healthy
  session. When the log's non-`rate_limit_event` bytes stop growing for `HB_STALL` (10 min) the session is
  "quiet"; a quiet session is spared if an active `claude` **descendant** exists (a subagent, whose work does
  not stream into the parent log and may sit at 0% CPU blocked on the API) **or** the tree is CPU-busy. An
  idle tree with no subagent for three polls is wedged; a CPU-busy tree with no subagent and no events for
  `HB_HARD` is a runaway.

`HB_HARD` is **60 min** here (raised from 50 on 2026-08-16), and no longer for the reason it used to give.
The old text justified it by "the full mutation catalogue is ~70 minutes", which was arithmetic on a
2-4 minute suite; the real figure is hours (see the timings table), and no watchdog value makes that
survivable — the resume prompt forbids the full catalogue outright instead. What this must not kill is the
ORDINARY case: a session sitting inside its own `git commit`, CPU-busy and silent for the hook's ~40
minutes. 50 min left ten minutes of headroom over that.

The **idle** branch of the same watchdog needed the companion fix — see the timings section above. It killed
a session merely waiting on the suite lock after 660 s, because waiting is silent and uses no CPU.

Every kill routes through `_terminate_tree`, which snapshots the descendant set up front, TERMs the whole
tree, and schedules a detached KILL backstop — so a runaway build child is never orphaned when the session
dies.

## Housekeeping

Each session mints an `auto/<stamp>` worktree and branch; `housekeeping()` GCs the spent ones between
sessions. Safety is structural: **no `--force`, ever**, so git itself refuses any worktree with uncommitted or
untracked content, which means housekeeping *cannot* destroy in-progress work; and **merged-only**, so a ref
is touched only when it is an ancestor of `origin/main` and therefore provably pushed.

⚠️ **That property still holds for `housekeeping()`, and since D17 it holds for the SYSTEM too.** Since
2026-08-22 the worktrees it declines to touch are snapshotted and handed to a session, which may take one
out once it has proven it superseded — under four preconditions (content already on main, the rescue marked
COMPLETE, the branch not ahead of `origin/main`, and the trio filed first). ⛔ **This paragraph said that
session "may `--force`" it, and therefore that *"nothing can force-remove a dirty worktree" is false at the
level of the system*. Both halves are wrong as of D17**, which is the fourth place that error was published
and the one D17's own first draft missed — a session cannot force anything (the three forcing forms are in
the daemon's `DENY` array) and does not need to: it restores the tracked files, which are on main and in the
rescue patch, and stops on untracked content rather than destroying it. So no-`--force` is a property of the
whole system again. D15 and D17 below are the mechanism and the reasoning. It is purely local (no
`git fetch`), so it cannot hang the loop on a dead network.

⚠️ **Scope is deliberately narrow — `auto/*` only.** The owner works in `work/*` worktrees by hand. The
sibling project widened its GC to every session-created slug, which then made a fully-pushed, fully-clean
*interactive* worktree eligible for reclamation between sessions. That is zero data loss but a real surprise,
and it was only acceptable there because its sessions improvised branch names. Here the resume prompt mints
`auto/<stamp>` every time, so a narrow namespace loses nothing.

## Reading `daemon.log` when the run is down

Every **trappable** exit logs one line saying why, so an ordinary shutdown is distinguishable from a crash:

| what you see | what it means |
|---|---|
| `reason: SIGTERM — launchd bootout/stop, logout, shutdown, or the laptop lid closing` | An orderly system stop. **This is the normal case on a laptop.** Not a defect — just start it again. |
| `reason: fell out of the main loop (rc 9 …)` | The daemon's own decision: `RUN STATUS: COMPLETE`, or it parked. Look for `~/Desktop/VISION-OCR-RUN-PARKED.txt`. |
| `reason: SIGINT` / `SIGHUP` | Ctrl-C, or the controlling terminal went away. |
| a `daemon up` line with **no** matching `daemon down` | A **hard kill** — SIGKILL, OOM or power loss. These cannot be trapped, so the *absence* of a line is itself the signature. Almost always the lid closing or the battery dying. |

`session-in-flight=YES` means a session was running when the daemon went down, so `engine.lock` is probably
stale; the next daemon takes it over after `STALE` (30 min), or delete the lock to skip the wait.

## Tests

Every change to `ops/autonomous/*` is infrastructure that drives self-pushing work, so prove the mechanism
rather than assuming it:

```bash
ops/autonomous/tests/prove-daemon.sh      # the real daemon loop against a stub `claude`, fully sandboxed
ops/autonomous/tests/prove-test-lock.sh   # mutual exclusion, reentrancy, stale reclaim, release-on-kill,
                                          #   and that both caller shapes write the same ledger row
ops/autonomous/tests/prove-status.sh      # STATE 1: one branch per answer the run-state lib can give
ops/autonomous/tests/prove-stop.sh        # `daemon.sh stop`: tree teardown, the lock verdicts, engine.lock
ops/autonomous/tests/mutate-test-lock.sh  # puts each of test-lock.sh's guards back as a defect, on a copy,
                                          #   and proves prove-test-lock.sh objects. --only, --out TSV.
```

`mutate-test-lock.sh` is the newest, and it exists because **a green harness is not evidence that its checks
can fail.** `Tools/mutate.py` covers `Sources/` and nothing covered the shell. On 2026-08-19 an adversarial
review of the `lock-report` commit mutated `test-lock.sh` twelve ways and **seven survived** a harness whose
author had already run nine mutants of his own — one of the survivors turned `⚠️ 2 SUITES AT ONCE` into
`1 suite plus a probe child`, i.e. it silenced the alarm that the whole file exists to raise. Run it after any
change to `test-lock.sh`; it starts with a pristine control, because a campaign whose control is red is
measuring the harness rather than the mutants, and every run is `prove-test-lock.sh` against a copy — no suite,
no build, minutes rather than the per-mutant cost of `Tools/mutate.py` (~45 min measured under the
pre-2026-08-24 clamp; ✅ **"roughly a tenth of that now" was written here as a prediction and is MEASURED as
of 2026-08-24 — `const/lineMinimumMembers` took 246 s, and 479 s end to end with its baseline, so 1/11**.
⛔ And do NOT "ask the tool" for this one yet, which is what the rest of this sentence used to say:
`mutate.py` estimates off the five newest `mutation-log.tsv` rows, all five were clamped-era, and it
printed "roughly 100-116 minutes" over that 479 s run — **14.5x high**, self-healing over four more scoped
runs). A `SURVIVED` row is either a
check that cannot fail or a value nothing depends on (`BUGS.md` T5); a `NOT-APPLIED` row means the edit did not
match, so it tested nothing and must be re-expressed rather than counted — two entries needed that, and one of
the two then exposed a check that asserted nothing.

`prove-stop.sh` came before it and the reason it exists is worth keeping: `daemon.sh` had **no** harness, and
`stop` is the verb an owner reaches for when something has already gone wrong — so it was the one path
guaranteed to run on a bad day and the only one never driven except by a real incident. Its `pgrep` **and**
`pkill` stubs are safety measures rather than conveniences: `stop` resolves its victims across the whole
machine, so an un-stubbed harness would TERM the owner's live daemon and live session — it would *be* the
incident it exists to detect. Both stubs run the real pattern match and then keep only processes the harness
itself created, and §[0] refuses to continue unless it has proved that filter works.

`prove-daemon.sh` runs the **real** daemon in a temp `HOME`/`STATE`/repo with every host-touching command
(`osascript`, `launchctl`, `caffeinate`, `curl`, `df`) stubbed, so it cannot reach the Desktop, the real repo,
launchd or the network. No harness ever runs the real suite or build.

`prove-status.sh` exists because the status **renderer** is where a correct answer still gets thrown away,
and that happened twice on 2026-08-16 — both times printing *"Running, but not finding anything it can
do"*, once over a suite that was three minutes into a forty-minute run, and once over a session 59 minutes
into real edits. Its section [5] is structural: it fails if `run-state-lib.sh` grows a reason
`status-digest.sh` has no branch for, so the residual can never silently swallow a new answer again.

## Defects found 2026-08-17, in one evaluation of a live run

The owner stopped the daemon at **07:55:53** on 2026-08-17 and asked for it to be evaluated and fixed. Seven
defects came out of that one stop. They are recorded here rather than in `BUGS.md` because that register is
the **app's** — this file is where this system's incidents live, and the reasons are the useful part.

Every claim below is tagged **[M]** measured on this machine, or **[I]** inferred from a mechanism that was
measured elsewhere in the same incident. Nothing here is tagged from reasoning alone.

`D1`–`D5` are one incident seen from five angles: **a stop is not a stop.** `D6`–`D8` are the other half of
the same evaluation: **a session's work is not safe until it is pushed**, and this run had three ways of
losing it. `D9` is the one the *fixes* turned up — a latent hazard that only mattered once `D1` started
exercising it, which is the ordinary shape of a fix in this repo and the reason the review step is not
optional.

### D1 · A trappable exit orphaned the session's whole subtree — FIXED

**[M]** The daemon's `TERM`/`INT`/`HUP` traps were `exit 0`. The EXIT trap then logged
`session-in-flight=YES (engine.lock present — a resume session was in flight and may leave it stale)` — and
nothing acted on it. Forty minutes after the 07:55:53 stop, this was still alive at **ppid 1**:

```
bash ops/autonomous/test-lock.sh run --label mutants-C24-override -- python3 Tools/mutate.py --only C24-override
  └─ python3 Tools/mutate.py --only C24-override
       └─ /bin/bash ./run_tests.sh
            └─ ./build/tests          ← 97.9% of one core
```

It held the **suite lock**, pinned a core, and no `git` and no session were left to read its result. The
daemon already had `_terminate_tree` — snapshot the descendants, TERM them all, detached KILL backstop — and
already used it for the wall-clock backstop, the gate watchdog and the health watchdog. **The signal trap was
the one killer that did not.** An instrument that names a hazard in its own log line is not a fix for it,
which is the shape this project keeps paying for.

Fixed in the daemon's trap rather than only in `daemon.sh stop`, because **three of the four ways this run
ends never go through that script**: logout, shutdown and this laptop's lid closing all arrive here as a bare
SIGTERM from launchd. Unchanged hard limit: SIGKILL and an OOM kill cannot be trapped and still orphan the
tree — which is why `stop` also sweeps, and does not simply trust this.

### D2 · `stop`'s four `pkill -f` patterns killed parents, not trees — and a fifth orphan class had no pattern at all — FIXED

**[M]** Pattern (b) matched `claude -p` and killed it; every descendant reparented to init and ran on. That is
the tree above. **[I]** Pattern (c)'s own comment claimed that killing `health-gate.sh` meant *"its build +
suite go with it"* — false by the identical mechanism: the gate runs `test-lock.sh run --label health-gate --
./run_tests.sh` as a direct child, which a TERM to the parent alone does not touch.

And **no pattern matched a suite or campaign the *session* launched** — `test-lock.sh run …`, a bare
`./run_tests.sh`. That is the class that actually survived.

⚠️ The obvious repair is wrong: `pkill -f run_tests.sh` would kill **the owner's own interactive suite**, which
is the one thing the lock logic bends over backwards to protect. The tree has to be **snapshotted from the
session pid while the session is still alive**, because once it dies the ancestry link is gone — the same
lesson `_terminate_tree`'s comment already records, applied one process further out.

### D3 · `stop` reported a lock it had just orphaned as "not ours to break" — FIXED

**[M]** After the stop, its lock branch printed:

```
suite lock LEFT ALONE — pid 26389 holds it and is still ALIVE, so it is not ours to break.
  If that is your own `./run_tests.sh`, nothing to do.
```

The holder was the session's own child, orphaned four lines earlier by this same script. The branch is right
to refuse the *owner's* suite and its caution is not the defect — reporting somebody else's lock over one it
had just created is.

### D4 · Both paths left `engine.lock` behind, costing the next run up to 30 minutes — FIXED

**[M]** `engine.lock` survived the stop with mtime 07:55:53. `tick`'s guard is `age < $STALE` (1800 s), so a
restart at any point before **08:25:53** logs `engine busy (lock Ns old) — skip` and idles — over a session
that is already dead. The heartbeat subshell dies with the daemon, so nothing refreshes the file and nothing
clears it either. A stop *knows* it killed the session; it can say so.

### D5 · `daemon.sh` had no proof harness at all — FIXED

**[M]** The three harnesses cover `vision-ocr-autonomous.sh`, `status-digest.sh` and `test-lock.sh`.
`daemon.sh` — `start`, `stop`, the prerequisite checks — had none. **The one file in this system with no
coverage is the file that just failed**, and that is not a coincidence to shrug at: `stop` is the verb the
owner reaches for when something is already wrong, so it is the worst possible place for an untested path.
See `prove-stop.sh`.

### D6 · Three sessions in a row ended with a commit inside its ~43-minute hook — MITIGATED (budget raised)

**[M]** From `$STATE/suite-timings.tsv`, three consecutive `pre-commit` rows: **2,552 s · 2,575 s · 2,615 s**.
A commit is a ~43-minute fixed cost, and the session has to still be alive at the end of it.

| session | ended | how | what happened to its commit |
|---|---|---|---|
| 22:44→01:15 | rc=143 | watchdog | hook orphaned, landed **04:04** as `1935d05` — the next session found it 30 min into its suite and let it finish |
| 05:19→07:10 | rc=1 | `budget_exhausted`, $20.14 of $20 | landed **06:40** as `c8855f6`; the session's own log says *"THE COMMIT HAD NOT LANDED"* — it had. A second hook it started ~06:41 ran to **07:24:34 rc=0** with no `git` left to record it |
| 07:12→07:55 | SIGTERM | owner's stop | the D1 tree |

The rescuing session's verdict is the honest one: *"It survived by luck, not by design."* `nocomplete.count`
stands at **2**, and `MAX_NOCOMPLETE` is 5 — three more and the run parks itself for a reason that is not
really about the item.

**The owner's decision, 2026-08-17: raise `VISIONOCR_BUDGET` from $20 to $35.** The reasoning is in the
constant's own comment, and the one sentence worth repeating here is that the headroom is for **polling, not
for more work** — a session that has done its work must never be unable to *afford to land it*. Each poll turn
costs ~$0.35–0.40 at the context sizes these sessions reach, so ~43 minutes of polling is ~$4; $15 of headroom
is deliberately generous against that.

⚠️ **This is a mitigation, not a fix, and the distinction matters for what to try next.** It buys a session the
means to survive its own commit; it does not make a commit cheaper. If sessions still fail to complete items,
the next lever is **item size** — not another raise — and `GATE_EVERY` after that. The other half of the same
problem is what the sessions themselves asked for, and that *was* fixed: see D7.

### D7 · The detached-plus-poll rule was written for the commit alone — FIXED

**[M]** `resume-prompt.txt` §STEP 4 is emphatic and correct about the commit: the Bash tool caps at 10
minutes, so a ~43-minute hook has exactly one working shape, detached-plus-poll. But **every other expensive
gate in this repo has since crossed the same ceiling**, and the prompt said nothing about any of them, so
three separate sessions each lost time rediscovering it one gate at a time and wrote it into `NEEDS OWNER`
three separate times:

- `Tools/check-tools-compile.sh` over every tool — killed at 120 s with no output (~05:00), against a QUEUE
  estimate of ~26 s that was a quiet-machine figure;
- `python3 Tools/mutate.py --only …` — ~45 min per mutant under the pre-2026-08-24 clamp; **246 s measured
  2026-08-24**, 479 s end to end with its baseline. ⛔ Do NOT fall back on its own estimate for now: that
  spans five clamped-era log rows and printed "roughly 100-116 minutes" over the 479 s run. It does not take
  the suite lock itself;
- a plain `Sources/` + probe rebuild — ~80 s cold, **>8 min under contention**, which killed two runs of the
  same measurement arm mid-`swiftc` at the 10-minute ceiling.

### D8 · The only copy of a killed session's work lived in `/private/tmp` — FIXED

**[M]** The orphan detector was right to exist and its closing line was optimistic:

> `a later session can finish it, or rescue it by hand; nothing is lost until that worktree is removed.`

True of `git worktree remove`. **Not true of the directory those worktrees live in.** §STEP 3 sends every
session to `/private/tmp/vo-<stamp>`, and macOS clears `/private/tmp` on reboot and sweeps it for age while
running — so the daemon's own answer to *"is this work safe?"* rested on a volatile filesystem holding the
only copy, and the detector reported the risk without reducing it. Same shape as D1.

What was actually at stake when this was found, and it is not a hypothetical: `/private/tmp/vo-20260817-072554-25857`
held **114 uncommitted insertions across 7 files** — the session's discovery of an **eleventh check that could
not fail**, in the commit that had landed 45 minutes earlier (`c8855f6`), plus the new mutant
`logic/C24-override-nil-means-fallback` that catches it, plus a published figure corrected from a flat
*"1,961 characters at every resolution"* to 1,960–1,962. A reboot would have taken all of it, and the register
would have kept a check that cannot fail while believing it was pinned.

Now every newly-seen orphan gets a patch written to `$STATE/rescue/<worktree>.patch`, with the base sha
beside it. A patch rather than a copy: a few KB against a worktree's megabytes, diffed against a sha that is
already pushed, restorable anywhere with `git apply`. `$ORPHSEEN` bounds the *logging* to once per worktree
per daemon lifetime.

⛔ **Both paragraphs of this section were superseded on 2026-08-22 — see D13 and D14 below.** As written here
the snapshot was `git diff HEAD`, which **cannot see untracked files**, and this section went on to claim the
gap was covered by "a loud warning naming that case" — it was not: the warning fires only when the patch is
*entirely empty*, so a strand with five modified files and one new one was reported as a clean rescue. That
paragraph also defended `orphaned_work`'s `--untracked-files=no` on the grounds that "every worktree has an
untracked `build/`"; measured 2026-08-22, **none of the three live worktrees has a `build/` at all** and it
is gitignored regardless. Read D13/D14 for what it does now, and do not trust the two sentences above.

The three worktrees live on this machine were rescued by hand during the evaluation and the important one was
verified recoverable (`git apply --check` forward onto a clean `c8855f6`). The other two were verified
**redundant** rather than assumed to be: `vo-20260816-224600-82042`'s five `mutation-log.tsv` rows — 2,621–2,719 s
each, about 3.7 hours of measurement — are all present on `main`, and `vo-20260816-184311-95643`'s 660
insertions are superseded by `db9481f`, whose `Tools/score-drawn-images.swift` and `DRAWN-2026-08-16.tsv` are
both on `main`.

### D9 · The delayed SIGKILL signals a stale pid snapshot — FIXED

**[I]** — inferred from the code, not reproduced, and labelled that way deliberately because forcing a pid to
recycle on demand is not something this evaluation could stage. `_terminate_tree` ends:

```sh
kill -0 "$root" 2>/dev/null || return 0        # never fire on a stale/reused pid
victims="$(_descendants "$root")"
for p in $victims; do kill -TERM "$p" 2>/dev/null; done
( sleep 8; for p in $victims; do kill -KILL "$p" 2>/dev/null; done ) &
```

The **root** is guarded against pid reuse, in those words. The **victims are not**: eight seconds later the
detached subshell sends `SIGKILL` to a snapshot taken before the TERM, with no check that each pid is still
the process it was. A pid freed by the TERM and reissued inside that window is then killed — uninterruptibly,
and quite possibly the owner's.

What makes this a defect rather than a theoretical worry is that **this file already treats pid reuse as a
real hazard in the two analogous places** — the root check above, and the outer backstop watchdog, whose
comment says it polls liveness so it "never fires `_terminate_tree` against a stale/reused pid". The harness
does the same, reaping only pids whose command name still matches. One delayed loop was left out of a rule
the rest of the system follows.

**It is listed here because D1 is what makes it matter.** Before that fix `_terminate_tree` ran only on a
watchdog kill or a gate timeout — rare. D1 puts it on the path of *every* trappable stop, so a latent 8-second
window became one that opens on every bootout, logout and lid close. Fixing the first without the second would
have traded an orphan for a rarer but worse failure.

Now each victim's pid is snapshotted **with its start time** (`ps -o lstart=`), and the delayed loop kills only
pids whose start time still matches — gone-already and recycled are both skipped. Cost: one `ps` per victim.

Also still open, already in `NEEDS OWNER` and **deliberately not touched here** — `test-lock.sh status`
reports the suite's own `--probe-hostile-page` child as a second suite, which is the exact reading CLAUDE.md
tells a session to treat as corruption. It costs a session the time to rule that out *every time*. It is a
reporting defect, not a safety one (the belt still answers correctly), and it wants its own commit: that file
is the only thing standing between this run and two concurrent suites, and "a regression inside a fix for
another bug" is this project's most repeated shape.

> **FIXED 2026-08-19, in the separate commit that paragraph asked for — and the fix found a third defect of
> the same shape.** `status` now classifies the `pgrep -x tests` set by ancestry *within that set*: a pid with
> an ancestor in the set is one of the suite's own probes, anything else is a suite. Before:
> `suite RUNNING — pid(s) 90955 90956  (pgrep -x tests)`. After:
> `suite RUNNING — 1 suite (pid 90955), plus 1 probe child of it (pid 90956) (pgrep -x tests)`. Two
> *unrelated* `tests` processes now read `⚠️ 2 SUITES AT ONCE (pids …) — two suites corrupt BOTH runs`, which
> is the point: suppressing the probe children is only safe if the reading that matters gets LOUDER, and
> `prove-test-lock.sh` [12] asserts that as hard as it asserts the one-suite case. Every pid `pgrep` returned
> still appears in the line — relabelled, never dropped (invariant 1, inside an instrument), which is its own
> check and dies to a mutant that prints only the roots.
>
> Classification is by **ancestry, not `ps -o comm=`**: comm and `pgrep -x` disagree about a process renamed
> with `exec -a`, which is exactly how the harness makes a process genuinely named `tests`, and the answer has
> to be about the same set `pgrep` produced. A pid whose ancestry cannot be read — it exited between the
> `pgrep` and the `ps` — counts as a **suite**, because over-reporting one makes a caller wait while
> under-reporting one runs two. That is a check, not a comment.
>
> **The third defect, found by pinning the second one.** `NEEDS OWNER` item 2 (the reclaim notice naming an
> empty phantom holder, `'' holds the suite lock (pid )`) turned out to have been fixed already, in `df3ab6a`
> — and pinned by **nothing**. Writing the missing check exposed that the replacement message was itself
> wrong one branch further along: it said *"reclaimed from a dead holder"* after **either** reclaim, and the
> other one is a live holder broken past `MAXAGE`. Measured 2026-08-19 over a genuinely live helper:
> `holder 'wedged' (pid 91138) has held the lock 19885779s (>= 60s) — breaking it.` followed by
> `the lock was just reclaimed from a dead holder`. The notice now says only what is true of both reclaims and
> points at the line above, which is the one that knows which happened. Same phantom shape, introduced by its
> own fix, and it survived because the fix landed with no check.
>
> Gate: `ops/autonomous/tests/prove-test-lock.sh` **43 → 71 checks, 0 failed, 0 skipped**, ~35 s, no suite and
> no build; `prove-status.sh` 39/0 as the consumer regression check. **Nine mutant patterns watched failing
> against copies of `test-lock.sh`** — killed by 1, 1, 6, 2, 9, 2, 7, 1 and 3 checks — and **two of the nine
> exposed checks that could not fail**: a walk capped at one hop passed all 57 because the grandchild fixture's
> chain was contiguous, and the assertion written for the phantom holder grepped for the *empty* form while the
> branch now defaults to `${_lbl:-?}`, so restoring the defect printed `'?' holds the suite lock (pid ?)` and
> sailed past it. The recipe is repeatable: copy the script, apply one edit, and run
> `bash ops/autonomous/tests/prove-test-lock.sh /path/to/copy` — the harness takes the script under test as `$1`.
>
> `_suite_live()` is deliberately **unchanged**: as a boolean it was always right, because a probe child only
> ever exists under a suite. Sibling sweep, by grep — **three** other places call `pgrep -x tests`
> (`vision-ocr-autonomous.sh:999`, `status-digest.sh:289`, `run-state-lib.sh:75`'s `suite_blocking`), and every
> one uses it as a boolean, so the pid-reporting defect had exactly one site. ⚠️ **This paragraph said "five
> other places" and named `daemon.sh` first; `daemon.sh` contains no `pgrep -x tests` call at all** — its two
> mentions are prose, and every executable `pgrep` in it is `-f vision-ocr-autonomous.sh`. Corrected the same
> day by the adversarial review of this diff, which ran the grep the sentence was asserting. The two consumers
> of `status`'s *text* — `daemon.sh:494`, which prints it verbatim and branches on the exit code, and
> `status-digest.sh:284`, which matches `^lock` and `^suite  *RUNNING` — both survive the new format, and
> `prove-status.sh` was run (39/0) rather than reasoned about.
>
> One other place prints a raw `pgrep -x tests` pid list: `prove-test-lock.sh`'s own skip message when a real
> suite makes section [10]'s converse undecidable. Left as it is deliberately — it is naming what is on the
> machine, not counting suites, and the pids are the useful part of that sentence.
>
> **Residuals, named rather than fixed.** (a) Ancestry can only say *"forked by something in the set"*, so a
> genuine suite launched BY a suite would be silenced as a probe child. No such topology exists here —
> `mutate.py`, `.githooks/pre-commit` and the health gate all launch the suite from a non-`tests` parent — and
> `ps -o command=` (the ARGV, which would show `--probe-hostile-page` positively) is the stronger signal if one
> ever does. Reasoned, not measured. (b) A probe child orphaned by a killed suite reparents to launchd, so its
> ancestry leaves the set and it reads as a suite; that is the safe direction and consistent with the
> unresolvable-pid rule, but it means the two-pid false alarm is reduced rather than eliminated.

## Defects found 2026-08-18, from one overnight check-in

Found by reading the log of an unattended night, not by stopping the run — which is the cheaper way to find
this class and the reason the log lines are written to be read. Same tagging as the section above: **[M]**
measured on this machine, **[I]** inferred from a mechanism measured in the same incident.

### D10 · A session that pushed from its worktree was scored as having advanced nothing — FIXED

**[M]** — dated to the second from `git reflog`, and reproduced as a failing test before being fixed.

The 02:41 session committed `bd574ac`, pushed it, removed its worktree and stopped. At **04:14:21** the daemon
logged `session (rc=0) advanced nothing (queue + tip unchanged) — no progress`, slept **1800 s instead of
90 s**, and left the idle stopwatch reading **21142 s** — over a run that had just shipped a commit and a
441-page corpus sweep.

`work_fingerprint()` hashed `git rev-parse HEAD`: the **primary checkout's** HEAD. Sessions work in
`/private/tmp/vo-<stamp>` worktrees and push from there, and fast-forwarding the primary checkout afterwards is
something they do only sometimes. The two reflogs date both halves:

```
refs/remotes/origin/main@{04:13:07}   bd574ac   update by push     <- 74 s BEFORE the verdict
main@{04:44:51}                       bd574ac   pull --rebase      <- where the NEXT session dragged it
```

The fingerprint therefore could not have moved, and the run's own record of what it had accomplished lagged a
full cycle behind reality — once per session that landed work this way.

**[M] It does not only DELAY that signal, it MISATTRIBUTES it — measured live at 08:41:51 the same morning**,
while the daemon was still running its pre-fix installed copy. That session pushed `d56fd0e` and `36fe77a` and
left the primary checkout two commits behind, exactly as the 02:41 one had; the daemon logged progress anyway.
Not for those two commits. `fp_before` is captured when the cycle launches at 06:15:50, and the session's own
first act — `git pull --rebase origin main`, at **06:16:00** by the reflog — fast-forwarded main to the
PREVIOUS cycle's `dddcbf6` ten seconds later. So the fingerprint moved on work that had landed two hours
earlier, and every cycle was being credited with its predecessor's commits while its own stayed invisible.
A progress signal shifted one cycle to the left reads as healthy for exactly as long as the run keeps
producing, and starts lying at the moment a session produces nothing — which is the case the whole backoff
mechanism exists to detect.

**What makes it a defect rather than a preference is that the daemon already knew.** `housekeeping()` deletes
merged `auto/*` branches on the strength of this very ref, and says so: *"PURELY LOCAL: no `git fetch` — the
session's push already advanced the origin/main ref this checkout"*. Two halves of one script disagreed about
where "landed" is recorded, and the half that scored the run was the one that had it wrong.

Fixed by hashing `refs/remotes/origin/main` beside `HEAD`. No network and no fetch: `refs/remotes` is shared
with every linked worktree, and the push is what updates it. Covered by `tests/prove-daemon.sh` §[4b], written
against the unfixed daemon first — **88 passed / 3 failed**, the three being the false backoff, the false log
line and the un-reset stopwatch — and green at **92 / 0** after.

A push by someone else — the owner from another machine, an interactive session — now reads as progress too.
That is correct rather than tolerated: per the fingerprint's own accelerator note, a changed fingerprint means
only *"the decision surface moved, retry NOW"*, which a fresh push from any source warrants.

**[M]** One thing the fix caught in itself, worth knowing before copying the idiom: a bare
`git rev-parse <missing-ref>` **echoes the ref name back on stdout and also exits nonzero**, so a
`|| echo <fallback>` appends to that output instead of replacing it. Both lines are deterministic, so the
fingerprint stays stable either way — but a fallback string that can never appear on its own is one nobody can
reason about. The new line therefore uses `--verify --quiet`, which is the form `housekeeping()` already uses on
this same ref. **The `HEAD` line beside it has the identical latent shape** in a repo with no commits, and is
deliberately left: the daemon refuses to start without a repo, so nothing can reach it, and changing it is a
different change from this one.

### D11 · A completed item is credited one cycle late, from the same root cause — LEFT, with the reason

**[M]** on the mechanism, **[I]** on the consequence — and the consequence is bounded by a measured fact rather
than an assumed one.

`completed_items()` counts ticked `QUEUE.md` boxes and closed `BUGS.md` entries by reading **the primary
checkout's working tree** — the same tree `D10` found lagging. A session that ticks a box in its worktree and
pushes without fast-forwarding therefore has its completion counted as zero, and `note_committed` increments the
no-completion streak that parks the run at five.

**It cannot accumulate to a false park, which is why it is recorded rather than fixed.** The resume prompt's
step 1 is `git fetch origin && git pull --rebase origin main`, so the next cycle's session brings the primary
checkout current *before* that cycle's verdict is computed; the tick becomes visible and resets the streak. The
real effect is a one-cycle lag in crediting a completion, and a streak that can read one higher than the truth
in between.

Left deliberately: fixing it means `completed_items()` reading the queue and the register out of `origin/main`
instead of the working tree, which changes what two further mechanisms count and wants its own harness section.
`D10`'s fix is one line and one ref; this is a different change and belongs in its own commit — this repo's most
repeated lesson being regressions shipped inside fixes for other bugs.

⚠️ **`D10`'s fix is what exposes this**, and the trade is deliberate. Before it, a push-without-fast-forward
session took the no-progress branch and never reached `note_committed` at all. The exchange is a false
30-minute backoff on every such session, for a transient off-by-one in a counter that self-corrects on the next
cycle.

## Defects found 2026-08-20, at an owner check-in

One defect, and it had already cost a hand rescue by the time it was found. Both the fix and its
regression test are docs-and-ops only — nothing under `Sources/`, `Helper/`, `Tests/`, `Tools/`,
`build.sh` or `run_tests.sh` — so the commit carrying them ran no suite, which is the pre-commit hook's
own docs-only gate working as intended.

### D12 · The rescue snapshot was gated on the progress verdict, so any outside commit disabled it — FIXED

**What happened.** A session ran 14:29-16:36 and did the whole of `C28` sub-step 4 — the last 21 of the
73 pages rendered and read, question 1 closed. It then wrote a `SESSION LOG` entry saying *"pushed on
`auto/20260820-143108-63345`"*. It had not pushed, or committed: that branch was at the base sha and the
worktree held **481 uncommitted insertions across 9 files**, `Sources/Flattener.swift` and
`Tests/main.swift` among them. That half is the 2026-08-16 failure repeating — a backgrounded
full-suite commit, the turn ended, the hook killed, and the log written as though the work had landed.
`resume-prompt.txt` §STEP 4 already forbids it in capitals and tells a session to PROVE the sha moved.

**The defect is the other half: nothing caught it.** `$STATE/rescue` held no patch. The orphan naming
and the snapshot both lived inside `tick()`'s no-progress branch, and the run had taken the progress
branch — because **the owner landed a docs commit at 14:40, inside the session's window.**
`work_fingerprint()` reads HEAD, `origin/main` and the queue, and its own comment says an outside move
reading as progress is *"correct rather than tolerated"*: as a retry signal it means "the decision
surface moved, retry NOW", which is right. But the same value was also answering "did this session
strand its work", where an outside commit makes it answer wrongly. One value, two questions.

**Why the existing test could not have caught it.** `prove-daemon.sh` [17] — D8's regression test —
drives the daemon with `"0:no"`, a session that moves nothing, so it exercised the rescue from the only
branch that could reach it. It proved the rescue **works**; it never proved it **runs**.

**The fix.** The naming and the snapshot are now `report_and_rescue_orphans()`, called on BOTH paths with
a lead-in phrase so the log still reads as prose (*"no progress, and a worktree is holding…"* /
*"the tip moved, but a worktree is holding…"*). The retry signal is untouched.

**The gate.** [18] is the missing half of [17], and its sequence is the test: idle first so the backoff
rises (the progress line at `:422` is guarded by `[ "$BACKOFF" != "$INTERVAL" ]`, so a run that commits
on its first cycle logs nothing), THEN create the orphan, THEN commit — so a patch found can only have
been written by a cycle that read as progress. Watched failing against the old daemon, and its premise
assertion earned its keep: the **first** version of the fixture never reached the progress branch at
all, and the premise check reported "fixture broken" instead of letting a vacuous pass stand.
`prove-daemon.sh` is **96/0/0** with it, was 92/2 while the fixture was wrong and 93/1 once it was right.

⚠️ **What this does not fix.** The session still lied to its own log, and nothing here stops that — a
session claiming "pushed" when it has not is a prompt-discipline failure, not a daemon one. What changed
is that the daemon now leaves a durable patch and names the worktree when it happens, on every path.
The 16:38 session did recover this work, but only because it read the SESSION LOG claim and checked it
against the branch. That is diligence, not a mechanism.

## Defects found 2026-08-22, from the owner asking why so much needed him

Four defects on one path, found by triaging three stranded worktrees by hand. They compound: the
detector could not see one class of strand at all, the backup it took of the ones it *could* see was
incomplete while reporting success, the thing it did about them was a request no one was ever going to
grant, and the status surface pointed the reader at its own blank space. All four fixes are ops-only —
nothing under `Sources/`, `Helper/`, `Tests/`, `Tools/`, `build.sh` or `run_tests.sh` — so the commit
carrying them runs no suite.

The owner's framing is the requirement, and it is quoted here because it is the standard the design is
measured against: *"A lot of what ends up in 'needs me' seems like it could be resolved without me. I
don't really need to review stray worktrees and decide what to do with them, for instance. Find a way to
lower the threshold for 'needs me'. I'd rather the daemon just decide and execute much of this work."*

### D13 · The rescue patch was PARTIAL and reported itself complete — FIXED

**What happened.** `report_and_rescue_orphans` snapshotted a strand with `git diff HEAD`, which cannot
see an untracked file. Measured on `vo-20260822-014509-85956`: the saved patch held **5 tracked files at
90,263 B**, and `WIDEN-2026-08-22.tsv` — **10,465 B, the only copy of that measurement anywhere** — was
named in the `.status` written beside it and in no patch at all. The `else` branch that exists for this
tests whether the patch is **empty**, not whether it is **complete**, so it never ran and the log printed
a cheerful `rescued: … bytes` line. The two files this loop writes disagreed, and nothing compared them.

**The fix.** `GIT_INDEX_FILE=<scratch> git add -A` then `diff --cached --binary HEAD`. Pure git, and three
properties matter: the worktree's real index is untouched (verified — a `??` entry is still `??`
afterwards), `add -A` honours `.gitignore` so `build/` stays out and the patch stays a few KB, and
`--binary` means a dumped PNG survives the round trip. Measured on the same worktree: **6 files, 100,934
B**, against 5 files and 90,263. (This paragraph said **87,402 B** until review measured it: that is a
DIFFERENT worktree's patch, holding **7** files — so the sentence paired one strand's file count with
another's byte count. The arithmetic checks: the tsv's new-file hunk is 10,671 B, and 90,263 + 10,671 =
100,934 exactly. Fourth number this campaign has had to retract, and the only reason it was caught is that
somebody re-ran `wc -c`.) The loop also names what a FALLBACK patch could not hold, and
names any gap, because a named gap can be copied by hand and a silent one cannot.

⚠️ **Why the existing test could not catch it.** `prove-daemon.sh` §[17] had covered the rescue since
D8 — and its fixture *staged* its payload, with the comment *"tracked+staged, so `--untracked-files=no`
can see it"*. A fixture whose whole payload is tracked agrees with the broken implementation: the patch
came out complete because everything in it was tracked. The section now carries an untracked payload, a
gitignored one, and a **negative control** that runs the pre-fix `git diff HEAD` on the same worktree and
fails if it *also* captures the untracked file. Another check in this project's history that could not
fail, and the first one found in the harness rather than in the code.

### D14 · A strand of only-new-files was invisible to the detector — FIXED

**What happened.** `orphaned_work` tested `git status --porcelain --untracked-files=no`, so a worktree
holding **only new files** was not an orphan. That is exactly the shape a measurement sweep produces: one
fresh `.tsv` and nothing else. Such a strand got no rescue patch, no assignment and no mention beyond
`housekeeping`'s count — while `git worktree remove` still refused it, because untracked files make a
worktree dirty. So it sat in volatile `/private/tmp` with **no copy anywhere**, which is strictly worse
than D13 sitting next to it.

**The fix.** Count untracked content. Safe because every build product here is gitignored and plain
`--porcelain` excludes ignored paths: `.gitignore` covers `build/`, `testdocs/*`, `Tools/mutation-out/`,
`__pycache__/` and `output.[0-9]*`, and a real session worktree checked that day listed 5 modified files
and exactly one untracked `.tsv` — no build noise. It cannot start crying wolf over compiler output.

### D15 · "Left for manual review" was a request made 57 times and never granted — FIXED

**What happened.** `housekeeping` reaps an `auto/*` worktree only if its branch is an ancestor of
`origin/main` **and** `git worktree remove` accepts it, i.e. it is clean. A dirty one is therefore
**permanent**, and every cycle logged `left N merged-but-dirty/in-use worktree(s) for manual review`.
That line appears **57 times** in the log this was written from, against **zero** parks — by a wide
margin the most repeated thing this daemon has ever asked a human for. Three strands had accumulated by
2026-08-22; the oldest had been sitting unlooked-at for ten hours while three sessions ran past it.

**The fix, and the shape of it.** The daemon **assigns** instead of asking: `$STATE/triage/<wt>.md`
carrying the worktree path, base sha, rescue patch and a decision procedure, plus a new **STEP 1.5** in
`resume-prompt.txt` that outranks the queue. A session drains the inbox as its one item.

⛔ **The daemon deliberately does NOT judge, and that is the load-bearing decision.** Supersession here is
never visible in a filename: twice a strand was redone under a different one — `MRC_BG=` → `PHOTODETAIL=`
(`69ebf0e`), and `estimate-corpus-rate.py` + `SHRINKCOST-*.tsv` → `stratify-corpus.py` +
`SHAPETERM-BYTES-*.tsv` (`ef9786c`, byte-identical on all 41 data rows across 9 shared columns). Both
were established by reading two tool headers for the same purpose and diffing TSV columns, which is not a
shell rule. And the inverse is just as real: in the same sweep a third strand looked superseded by that
reasoning and was **not** — it held `Flattener.textRegionWideningOverride` plus 112 lines of tests that
`git grep` finds nowhere on `origin/main`, because the commit that appeared to replace it had landed only
the tool half. A session is an LLM and can do that reading; a bash rule would have deleted it.

⚠️ **The inbox is outside the repo on purpose.** The obvious channel is a `QUEUE.md` box, and it is wrong
twice: the daemon would dirty the **primary checkout**, and with `rebase.autoStash` unset (verified) the
next session's STEP 1 `git pull --rebase origin main` then fails outright; and an appended box walks into
the greedy-span trap `QUEUE.md`'s own header documents. A file under `$STATE` touches no tracked path.
Assignment is also skipped while a session is live — both call sites run after `wait` returns so that is a
no-op today, but D14 means a mid-run session's scratch `.tsv` now looks like a strand, and a third call
site added later would otherwise hand a session its own worktree to triage.

⛔ **This paragraph used to read "`--force` earns its exception here" and it was wrong twice — see D17.**
A session may take out a strand it has **proven** superseded, and only after filing the rescue trio, with
the commit and the evidence cited in its SESSION LOG; the proof requirement stands. But the *command* was
`git worktree remove --force`, which is in this daemon's own `DENY` array, and the removal turns out to
need no force at all. There is no carve-out from CLAUDE.md's never-force rule, because nothing here needs
one.

### D16 · The digest told the reader to look at its own blank space — FIXED

**What happened.** The WORKING branch appended `⚠ also: N worktree holding uncommitted work — see 'Needs
you'.` and **nothing ever put orphans into `needs`**. Measured 2026-08-22 with three dirty worktrees on
disk: the hint said *see 'Needs you'* directly above `Needs you  Nothing right now.` Either half is
defensible; together they are an instrument directing the reader to its own empty section. The same
absence showed up in two other states — a strand was invisible entirely while THROTTLED on the usage cap,
and while the daemon was stopped.

**The fix.** An **assigned** strand is queued work and raises no need; an **unassigned** one does, and
that is the only case the pointer now fires for. The `ORPHANED WORK` state is no longer unconditionally
RED either: RED is reserved for a strand nothing is assigned to, because painting the handled case red is
how a status surface trains its reader to ignore red. Precedence is unchanged — WORKING still outranks
this, which `prove-status.sh` §[8] pins.

### D17 · The triage procedure's last step was a command the daemon forbids, and it never said to remove the strand — FIXED

**What happened, and it is two defects with one cause.** D15 gave a session a decision procedure that ends
in removing the strand, and neither of its two ends worked.

*The adoption path did not end.* Step 3 — "it holds UNIQUE work: adopt it" — read *"rebase, run the suite,
commit, push"* and stopped there, saying nothing about the worktree the work came out of. Deleting the
assignment file is what marks a strand **resolved**, and therefore what makes it **eligible again**; and
`housekeeping()` reaps an `auto/*` worktree only if it is clean, so a dirty one is skipped every cycle
forever (D15's own founding measurement). Those two facts compose into a loop with no exit. Measured:
`f5bdbea` adopted `vo-20260822-073825-10384`'s 97 lines of `BUGS.md` at **14:05:36**, filed the rescue trio
as `LANDED-as-f5bdbea-*`, deleted the assignment — and left the worktree. The daemon re-assigned **the same
strand** at **14:09:59**, four minutes later, and the session that got it spent its one item re-proving
content that was already on main. Left alone this repeats every cycle, one session per cycle.

*And the removal itself was un-runnable.* Step 2's terminal command was `git worktree remove --force` plus
`git branch -D`. Both — and `git worktree remove -f` — are in **this daemon's own `DENY` array**, beside
`rm -rf` and `commit --no-verify`, and go to every session as `--disallowedTools`, where the header two
lines above the array says **DENY WINS OVER ALLOW**. So the procedure's last step was forbidden by the
launcher **in the same file** — at `3078fb0`, the denylist entry is line 245 and the instruction to run it
line 1286, **1,041 lines apart**. Measured: the call returned `Permission to use Bash …
has been denied`. **FOUR** places said a session "may" force — the assignment template, `resume-prompt.txt`
STEP 1.5, this README's D15, and this README's `housekeeping()` section ~550 lines above D17 — and the
denylist had said otherwise since before any of them. (This entry's own first draft counted three and
missed the fourth, in the file it was editing. A single `grep force` would have found it, which is
`CONTRIBUTING.md` §4b again.)

**The fix.** ⛔ **The force was never needed for the tracked files, and must never be used on the untracked
ones.** Once the preconditions hold, a strand's dirty *tracked* content is redundant twice over — on main,
and in the rescue patch — so restoring it discards nothing, the worktree becomes clean, and plain
`git worktree remove` accepts it. Measured 2026-08-22 on the real strand: `checkout HEAD -- .`, `remove`,
`branch -d` — no force, no refusal overridden. Step 3 now runs that same block, filing under
`LANDED-as-<sha>` rather than step 2's `SUPERSEDED-by-` (an adopting session landed that same work; it did
not replace it — and `f5bdbea` picked the right name with the template telling it nothing), and re-checks
(c) rather than inheriting it, because step 3 is the only step that *rebases* and so the branch it deletes
is not the object step 2 measured.

⛔ **Three things the adversarial review of this fix corrected, all verified by running git, and each was a
wrong claim rather than a rough edge.** (1) The command was `checkout -- <paths>`, which restores from the
**index**: on a *staged* change it is a no-op, so `worktree remove` still refuses — and a session that died
inside the pre-commit hook leaves exactly that shape. `checkout HEAD -- .` clears modified, staged and
deleted paths in one go (tested: ` M  f.txt` staged, unchanged by `checkout -- f.txt`, cleared by
`checkout HEAD -- .`). `.` rather than the assignment's `dirty paths:` list, because that list is raw
`status --porcelain` and a session copying ` M BUGS.md` out of it runs `checkout -- M BUGS.md`. (2) The
route did not cover **untracked** content at all, which is the commonest strand shape here — a measurement
sweep produces one new `.tsv` and nothing else (D14), and `prove-daemon.sh`'s own §[17] fixture is exactly
that. `checkout` cannot restore an untracked path, `worktree remove` refuses on a `??` alone (measured:
*"contains modified or untracked files, use --force to delete it"*), and `git clean`/`rm -r`/`rm -rf` are
all denied. The procedure now **stops** there and accounts for each file by name — `rm <file>` if it is on
main, leave the worktree if it is not, because the rescue net is known to list untracked files in `.status`
that its `.patch` does not hold. That is a guard, not a gap. (3) ⛔ **`branch -d` does NOT test against
`origin/main`.** `git help branch`: the branch must be merged *"in its upstream branch, or in HEAD if no
upstream was set"*. This entry claimed `-d` "enforces precondition (c) for you", which would have been the
best thing in the fix and is false — a strand with an upstream set passes `-d` trivially while ahead of
`origin/main`, which is the one irreversible mistake in the whole procedure. Latent rather than live today
(verified: no `.gitmodules`, `push.autoSetupRemote` unset, all live `auto/*` upstreams empty), and the fix
is to use the test `housekeeping()` already uses: `git merge-base --is-ancestor <branch> origin/main`.

⛔ **AND `branch -d` IS WRONG IN THE OTHER DIRECTION TOO — found by running this entry's own procedure, one
command from the end, on the commit that first published it.** The review's case was a false ACCEPT. The
one that actually fired is a false **REFUSAL**: a strand has no upstream by default, so `-d` falls back to
**HEAD**, and from the primary checkout HEAD is local `main` — which *nothing in this daemon
fast-forwards*, because `housekeeping()` only ever reads `origin/main`. Measured 2026-08-22 while removing
`ddedec6`'s own worktree: local `main` `3078fb0`, `origin/main` `ddedec6`, `merge-base --is-ancestor`
confirming the branch WAS an ancestor of `origin/main` — and `git branch -d` still answered *"the branch …
is not fully merged"* and hinted at the **denied** `-D`. A session following the block as first published
would have dead-ended exactly where the old one did, one command later. The block now sets the upstream
first:

```sh
git branch --set-upstream-to=origin/main <branch>   # aims -d at the ref precondition (c) is about
git branch -d <branch>                              # "merged to 'refs/remotes/origin/main', but not to HEAD"
```

✅ Which resolves the review's finding rather than dodging it: with the upstream pointed at `origin/main`,
`-d` *does* enforce (c) — but only because that line put the right ref in front of it, and never on its
own. An eighth assertion pins the line, and its negative control is `ddedec6` itself, the commit that
published the block without it. ⚠️ Note what this cost: the defect was in a fix that had already been
adversarially reviewed and had seven green assertions over it. What caught it was *executing the
procedure*, which is `CONTRIBUTING.md` §4c — a branch that only runs when something else goes wrong had
never run.

⚠️ **Why the existing test could not catch it, and why the FIRST FIX passed its own new test.** §[17]
asserted that an assignment *was written* and that it *named the worktree* — the two things a fixture
notices — and nothing read the procedure inside it. The section now extracts the step-2 and step-3
paragraphs from the assignment the daemon actually wrote, with a length check on each `awk` range so a
renamed heading cannot make either read as a pass over an empty string. ⛔ **But every one of those is a
PRESENCE test, and a presence test is green over a document that also says the wrong thing.** The first
draft of this fix added the cleanup clause to step 3 and ended it with the two denied commands — so
`grep 'worktree remove'` matched, *on the forbidden command*, and printed PASS over precisely the defect
D17 was opened for. The review caught it; the seventh assertion is the absence test that makes the machine
catch it next time, over the whole assignment, matching the backtick-quoted imperative so that prose
*about* the denial still survives — with its own negative control run against the literal pre-fix line,
because a typo in that regex would read as a pass over any document at all.
⚠️ **And the step-3 predicate was wrong in BOTH directions before it settled, which is the smaller lesson
worth keeping.** It grepped for the string `worktree remove`. Before the review that was satisfied *only* by
`worktree remove --force` — green on the denied command. After the fix, step 3 was rewritten to CITE step
2's block rather than repeat it, and the same grep went red over a correct document. One token, a false
pass and then a false fail. It now tests the removal's two endpoints, `checkout HEAD` and `branch -d`,
which survive either shape: a step 3 that inlines the block names them, and a step 3 that cites it names
them as the block's bounds. Both are absent from the pre-fix text, so it still bites. ⚠️ Of the seven, **five** were
watched failing against the genuine 14:09:59 assignment; the two `awk`-range length controls **passed**
pre-fix, as vacuity guards should. An earlier draft of this paragraph said "all five were watched failing",
which was false in a section whose subject is checks that cannot fail.

### The harnesses, and what they caught

`prove-daemon.sh` **118** assertions and `prove-status.sh` **48/0**, measured 2026-08-22 — against a stated 92
⚠️ **`prove-daemon.sh`'s 118 is a TOTAL and the pass count depends on machine load** — read its header. D17's
eight were added on a busy machine, and the honest form of that run is a PAIR: the unmodified tree at
`3078fb0` scored **102 passed / 6 failed** (108 assertions even reaching the end) and the modified tree
**113 passed / 5 failed**, the five a strict **subset** of the six, all in §[3]/§[4]/§[4b]/§[5], with §[4b]'s own
vacuity guard firing. Across the FOUR runs this fix went through, the environmental failure count was 3,
then 1, then 2, then 5 — every one from that same subset of six and never anything else, which is the
flakiness measured rather than asserted. Comparing the sets is what said "busy machine" rather
than "my edit broke it"; a single run could not have. Quoting a bare pass count off this harness is how it
rots —
(itself stale: D12's own section three screens up records 96) and 39. `prove-daemon.sh` §[17] gained
assertions and a new §[17b]; `prove-status.sh` gained a new §[11] and two assertions in §[8]/§[11].
⚠️ Totals only, deliberately: an earlier draft of this paragraph claimed a *delta* ("eight assertions", then
"four") and got it wrong twice while the totals beside it were right. Run the harness; do not do arithmetic
on this paragraph.

⚠️ **The new checks scored 101/2 on their first run and both failures were real defects, one in the
fixture and one in the code.** The fixture put its `.gitignore` in `$REPO` when the payload lived in a
*linked worktree*, which has its own working tree and never saw it — so `add -A` correctly swallowed a
build artefact nothing had told it to ignore. The code defect is the sharper one: `status --porcelain`
collapses a wholly-untracked directory to `dir/` while the diff names every file inside it, so the new
coverage check reported a complete rescue as incomplete. This project writes exactly those directories —
`MRC-2026-08-15/` and its PNG dumps — so unfixed it would have warned on most real strands and taught the
owner to skip the line. Two independent defects out of seven new assertions is the whole argument for
writing them.

`prove-status.sh` §[11] pins the mechanism in **both** directions off one fixture — create the triage file
and the need disappears, delete it and the need returns — so it cannot pass on a constant. It also forced
a fix to the `dirty_off` helper: §[7] creates a *second* worktree to prove the renderer names every orphan
and never cleaned it up, so from §[7] onward the sandbox permanently held a dirty worktree no `dirty_off`
could clear. Harmless for as long as nothing put orphans into `needs`; the moment an unassigned strand
raised one, §[10]'s closing assertion went red — correctly.

## Defects found 2026-08-23, from a session reading the checker it was about to trust

### D18 · The queue's own rule about `(context: …)` asserted the OPPOSITE of what the checker does, and nothing could see it — FIXED

**What happened.** `QUEUE.md`'s "RECORDING A FINISHED SUB-STEP" section told every session that a sub-box
"must cite **no register entry**", on the stated ground that *"`(context: …)` does NOT exempt it — the check
is `[ "$st" = "x" ] && [ "$n_open" -gt 0 ]`, which never looks at which cite word was used"*. That condition
is quoted correctly and the inference from it is false: `n_open` is counted from `cited()`, and `cited()`
matches `/\(origin:[^)]*\)/` and nothing else. The word `context` does not occur in the parser, so the cite
word is *precisely* what it looks at. The rule stood from **2026-08-19 to 2026-08-23** — introduced in
`50e3854`, dated by `git log -S 'does NOT exempt it' -- ops/autonomous/QUEUE.md`, which returns that one
commit.

**Why nothing caught it.** `ops/autonomous/tests/` holds **five** files — `prove-daemon.sh`,
`prove-status.sh`, `prove-stop.sh`, `prove-test-lock.sh`, `mutate-test-lock.sh` — and none for
`check-queue-coherence.sh`. ⚠️ Nor for `next-item.sh` or `check-staleness.sh`, so this is one instance of a
gap rather than the whole of it; what makes this instance the sharp one is that the file whose entire job is
to make a class of drift LOUD had no gate of its own, so its own documentation could contradict it
indefinitely. A checker with no self-test is an assertion nobody has audited.

**The measurement that settled which side was wrong**, on the real tree, one line of `cited()` widened to
`/\((origin|context):[^)]*\)/` and nothing else touched:

| `cited()` harvests | verdict on `QUEUE.md` at `ad5861d` |
|---|---|
| `origin:` only (shipped) | `OK 56 items 6 cited`, exit 0 |
| `origin:` and `context:` | **24 findings — 16 `TICKED-OPEN`, 8 `WOULD-REDO`** — over 31 cited items, exit 1 |

⛔ **All 24 are correct bookkeeping, and the composition is the argument.** Fourteen of the sixteen
`TICKED-OPEN` are `c28-*` sub-boxes — written the way the very section carrying the wrong rule tells you to
write them, so enforcing it as documented would have flagged its own convention on fourteen rows; the other
two are `c30-fork` and `alltext-replica`, the same shape against `C30` and `C28`. Two of the eight
`WOULD-REDO` are `tools-compile` and `mutants`, the pair the `origin:`-vs-`context:` bullets were written for
in the first place, and **each says CLOSED inside its own cite text** — `(context: BUGS.md C25 and T16 —
both CLOSED; they are why this gate matters, not the work itself)` and `(context: BUGS.md T5 — CLOSED; it
records how to tell a real gap from a value nothing depends on)`. ⚠️ Those are **two different strings**: a
draft of this entry quoted the first as though it were both items' text, which is the kind of one-instance
generalisation this README's own D17 was caught making. That is 24 of 56 items crying wolf, which is the
failure the checker's own "WHAT IS **NOT** DRIFT" block exists to prevent. So the script is right and the
prose was wrong, and the prose is what moved.

**The fix is a gate, not a wording change.** `check-queue-coherence.sh --self-test` (fixtures only; its own
`mktemp` dir, reads neither `QUEUE.md` nor `BUGS.md`, milliseconds) runs an eight-row cite-word matrix against
a two-entry register fixture — `C98` FIXED, `C99` OPEN — and asserts fifteen things in six deliberately
different kinds, because none catches the others' failure:

1. **positive controls** — rows `a`, `c` and `f` must produce `TICKED-OPEN` / `WOULD-REDO`, tag and entry
   named. This is what stops "no findings" reading as "the exemption holds": a checker sabotaged to harvest
   nothing at all reports a clean tree, and would pass a self-test built only of negatives.
2. **negative controls on the rule** — the two `context:` rows (`b`, `d`) must produce nothing.
3. **the other two quadrants** — rows `g` and `h`, the *agreeing* `origin:` combinations (`[x]` citing a
   CLOSED entry, `[ ]` citing an OPEN one), which must also be silent. See the defect below; these were the
   ones missing.
4. **the counts** — `8 items, 5 citing BUGS.md` and `3 item(s) disagree`, read off the summary line.
   `N_CITED` is the one that bites: it moves under a context-harvesting change even where a finding's
   presence happens not to.
5. **an inverted row** — `f-mixed` carries *both* cite words on one `[ ]` item, so harvesting `context:`
   makes its finding **vanish** (the open `C99` stops `n_open` being 0) instead of appear. Guards 1–4 all
   catch a finding appearing; only this one catches the sabotage by a finding disappearing.

Row `e`, `e-context-missing`, pins the exemption's **cost** rather than the rule: a `context:` cite naming a
tag that is not in the register raises nothing, not even `CITE-MISSING`. That follows from "not a status
claim" and is not an oversight for the next reader to fix — but it must not change by accident either.

⛔ **AND THE FIRST VERSION OF THIS SELF-TEST COULD NOT FAIL AGAINST ONE WHOLE SABOTAGE CLASS — found by
running it, in the adversarial pass on this very diff, which is the only reason it is not shipping as the
eleventh such check.** It had six rows and eleven checks, and against `TICKED-OPEN`'s guard loosened from
`[ "$n_open" -gt 0 ]` to `-ge 0` — "report every ticked item that cites anything", the condition's entire
meaning gone — it scored **0 red, exit 0**. The cause is that every ticked row it had either carried an open
cite (reported under both the real guard and the sabotage) or **no cite at all** (skipped by
`[ -n "$cites" ]` before any verdict is reached), so no row could tell the two conditions apart.
CONTRIBUTING §4d is both the lesson and the remedy — *enumerate the states against the doors, do not reason
about pairs*: the doors are {`[x]`, `[ ]`} × {cite OPEN, cite CLOSED}, and **two of the four cells had never
been written down**. Rows `g` and `h` are those cells. ⚠️ Note what this says about the ORIGINAL six: they
were chosen by reasoning about which sabotages seemed likely, and that reasoning missed a one-character edit
to the guard the whole file exists to evaluate.

✅ **WATCHED FAILING — FOUR sabotages, `shasum`-distinct copies, one edit each, all exit 5** (CONTRIBUTING
§2/§4a), all re-measured against the final file rather than rescaled from an earlier round:

| sabotage | red | the checks that catch it |
|---|---|---|
| `cited()` widened to `/\((origin\|context):…/` | **7 of 15** | rows b, d, e, f + both counts |
| `cited()` narrowed to `/\(provenance:…/` (harvests nothing) | **7 of 15** | exit code, rows a, c, f + both counts |
| `TICKED-OPEN`'s `[ "$n_open" -gt 0 ]` → `-ge 0` | **2 of 15** | **row g** + finding total |
| `status_of()` stubbed to return closed for every tag | **3 of 15** | rows a, **h**, i |
| the whole `CITE-MISSING` verdict disabled (`if [ -n "$unknown" ]` → `if false`) | **2 of 15** | **row i** + finding total |
| the `if (cl !~ /BUGS\.md/) continue` guard removed | **3 of 15** | **row j** + both counts |
| two lines inserted above the queue fixture, shifting every row | **3 of 15** | rows a, c, f |

⛔ **The kill sets are the argument that the guards are not redundant**: no sabotage's set contains
another's; `g` is the only **row** that catches the `-ge 0` sabotage, and `h` the only **silence assertion**
that catches the `status_of()` one (row `a`'s positive control fires there too, since a closed `C99` removes
its finding — said precisely because a draft of this claimed both were sole outright). The fifth
is a different kind of control — it sabotages the FIXTURE rather than the code, and it is there because the
three positive controls assert the finding's **reported line number** as well as its tag and entry
(`… a-origin-open 3 C99`), so it proves those assertions are exact rather than loose prefix matches. ⚠️ It
is also a real constraint on editing: insert a row in the middle of that heredoc and three checks go red
until the expected line numbers are corrected. That is the intended trade — the alternative is an assertion
that would not notice the checker reporting the wrong line. Shipped:
`self-test ok (15 checks)`, exit 0, run from the worktree root and from `/` by absolute path, and the real
tree still green —
`OK 58 items 6 cited`, the two new ones being this fix's own ticked box and `register-dup-tag`. ⚠️ **Every `56` above is the count at
`ad5861d`, before those boxes existed**, and the two must not be conflated: the *item* total moves with any
queue edit, while `6 cited` is the number the finding counts are actually about and it does not move here,
because the new box cites this README and not the register.

**Wired warn-only into `health-gate.sh`, ahead of the check it protects.** ⛔ Warn-only on the direction of
failure, not the cost: a hard step would PARK the whole run over a self-test on a checker that is itself
warn-only, which is a larger consequence than anything the checker buys. `tools-compile` is hard because a
tool that will not type-check breaks a session's instruments; this does not. ⚠️ The step name
`queue-coherence-selftest` was added to `vision-ocr-autonomous.sh`'s `_classify_red()` case list in the same
commit even though a warn can never reach a `HEALTH GATE: RED` line — that `case` is an exact match with
`*) has_code=1` underneath, so promoting this to a hard `step` later would otherwise report a **document**
failure as a **code regression**. Pre-empted rather than left as a trap.

⛔ **AND THE `✓` ON THAT STEP WAS AMBIGUOUS UNTIL IT WAS CONTROLLED, which is the whole hazard in
miniature.** `step_warn` discards a passing step's output, and `check-queue-coherence.sh` with the argument
*dropped* also exits 0 — so `✓ queue-coherence-selftest` in the gate log is consistent with the self-test
never having run. Reading `step_warn`'s `shift 2` / `"$@"` says the argument is forwarded; that is reasoning,
not evidence. Measured instead, by extracting the real `step_warn` from `health-gate.sh` and calling it
against a probe script that exits 5 iff it receives `--self-test`: `⚠ probe-selftest (rc=5)` with the probe's
own `probe: got --self-test` printed beneath it, and `✓ probe-noarg` on the same probe called without it. So
the argument does arrive, and the gate's `✓` means what it says. A gate step whose pass is indistinguishable
from its own no-op is the eleventh check that could not fail, and this one came within a control of being it.

⚠️ **What this does NOT cover, re-derived by SABOTAGE rather than by reading** — the first version of this
paragraph was written from the code and was itself incomplete, which is exactly how two of the exemptions
above came to be unpinned. Each of these was confirmed still green under a one-line deletion: the greedy
item-span rule, the fence/blockquote skipping, `DUPLICATE-TAG`, and the tag-shape test
(`^[A-Za-z]+[0-9]+([.][0-9]+)*$` — remove it and the real tree reports `CITE-MISSING C24b … FIXED`), plus the
mirror-`next-item.sh` property the file's header calls load-bearing. So **three of the checker's four verdict
classes** are now exercised — `TICKED-OPEN`, `WOULD-REDO`, `CITE-MISSING` — and `DUPLICATE-TAG` is not. A
second cite-word row is not what is missing; a second *kind* of row is, and rows `i` and `j` are the evidence,
since each was added only after a sabotage walked through the gate.

⚠️ **Two side-findings, recorded rather than fixed here.** (1) This script's own comment claimed its inline
register fallback was a *"verbatim copy"* of `bugs-entry.sh`'s rules. Measured, the two disagree on the real
register — **169 rows against 168** — because `BUGS.md` carries **two `### R63` headings** (lines 12145 and
12618) and only the fallback dedupes, via `seen[tag]`. Harmless today (both `FIXED`, first match wins) and
live the moment those two statuses diverge; the comment is corrected in place and the duplicate is carried as
the queue's `register-dup-tag`. ⚠️ `--self-test` is structurally blind to it — its fixture register has no
duplicate tag and only `FIXED`/`OPEN`, never `WONTFIX`, `NO DEFECT` or `HALF FIXED`, so it stays green with
`bugs-entry.sh` un-executable or absent. (2) Of the fifteen checks, one — `[ -r "$st_self" ]` — appears in no
sabotage's kill set and is belt-and-braces rather than an independent assertion, so **fourteen is the honest
count of checks that distinguish something**, and it is written here rather than rounded up.

## What this deliberately does not have

The sibling daemon has eleven helper scripts and thirteen proof harnesses. Most of what is missing here is
downstream of *that project's* shape, not of autonomy:

| dropped | why |
|---|---|
| A gitignored plan file with its own WORK QUEUE | It duplicated the committed tracker. Keeping one list is what makes `check-tracker-sync.sh`, `check-todo-stubs.sh` and a handoff-audit step unnecessary — three scripts that exist only to police two lists. |
| Per-file context budgets (`context-budget.sh`) | Its own owner demoted per-file caps to advisory after a byte-budget trim deleted a whole policy section from a guide and the falling byte count was reported as success. The orientation cost here is handled where it actually bites: the resume prompt's read-narrowly rule plus `bugs-entry.sh`. |
| A doc-fix pre-gate with its own attempt counter | ~180 lines to route a document trim to a session and park after three failures. Here the standing remedy is one ordinary queue item (`stale-docs`) plus a warn-only gate step. |
| Paced code reviews (`next-review-unit.sh`) | Switched off in the original since 2026-07-29 while it kept shipping work — the strongest available evidence that it is optional. `REVIEW-2026-08-14.md` already holds this project's findings, and three of them are queue items. |
| A GUI VM lane to build | Already solved: `Tools/vm-gui-check.sh` runs off-screen in the Tart VM with the exact 0/1/3 exit contract the gate wants. It is wired in as a skippable step. |
| PATH shims + a PreToolUse host-GUI hook | Replaced by tool-layer denies (`open`, `osascript`, `cliclick`, `build.sh --install/--run`) plus the resume prompt's rule. Not a hard boundary — a child process could still reach `open` — so the prompt is the primary control and the deny is defence in depth. |
| Code signing, keychain partition lists, notarization | This app is ad-hoc signed and unnotarized by choice. The one generalisable lesson is kept: any credential the daemon needs must be readable non-interactively, because a password prompt is an unbounded hang, and a hang is worse than a failure. |
| Per-session `--max-budget-usd` tuned for paid API calls | Kept, but the OCR here is local (Apple Vision), so there is no per-item spend to gate. |

Three mechanisms were kept **because** their absence caused a silent failure over there, and silence is the
failure mode this project cares most about: the derived work fingerprint, `step_skippable`'s
skip-is-not-pass, and the compactor's exit-code contract with its over-budget-but-no-entries-detected alarm.

Two known consequences of the cuts, stated rather than hidden:

- **The daemon's document-vs-code RED classification is defensive, not live.** `staleness` and
  `queue-coherence` are the only steps it classifies as DOCUMENT, and both are warn-only, so they cannot
  reach the failing set. The branch is there so that promoting either to a hard step later cannot
  accidentally report a docs problem as a build regression.
- **`RUN.md` is not in git.** Its history is not recoverable, only its `.bak` and the session archive beside
  it. That is the deliberate trade for not churning a commit per session; everything that belongs in the
  project's history is in the register, the queue and the changelog, which are all committed.

## Changing this setup

Treat every change here like a change to code with no undo, because it drives self-pushing work:

- **Adversarially review it before installing.** The original's idle watchdog false-killed healthy sessions
  because plain-text `claude -p` buffers output to the end — one question would have caught it: *does it write
  to the log incrementally?* It does not in text mode, which is exactly why this daemon uses stream-json.
- **Prove the mechanism, don't assume it.** Run both harnesses before installing anything. An unrun test
  reads as coverage in review and asserts nothing at runtime.
- **Never install a daemon change straight onto a running run** without the above.
- Keep the `RUN STATUS:` line plain. Keep the verdict lines in `health-gate.sh` byte-exact — the daemon
  parses them. Keep `next-item.sh` and `bugs-entry.sh` agreeing about what a tag and a status are.
