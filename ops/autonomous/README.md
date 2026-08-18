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
| proof harnesses | 15 | **4** | it guards far less machinery |
| core shell lines | 4,295 | **4,381** | *no longer fewer at all* |
| harness lines | 2,866 | 1,515 | |

⚠️ **Two of those numbers were wrong and are corrected here, re-counted 2026-08-17 with `wc -l`.** The
harness row read **2** while three harnesses were committed — it was written when two existed and was never
re-counted as `prove-status.sh` landed, which is the ordinary way a measured figure rots into an asserted one.
It is **4** now that `prove-stop.sh` exists (README §Defects D5: `daemon.sh` had no coverage, and it was the
file that failed). The core-shell row read **3,668**; the real count is **4,381**, so the "only ~15% fewer"
claim below has become "slightly more" — the honest reading of the paragraph that follows is now stronger, not
weaker, and the row is left in place rather than quietly dropped.

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

It was timed on 2026-08-16, and the answer is that **the suite has no single duration on this machine**:

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
  overrun counts as a TIMEOUT, two of which **park the run**. Now 9000.
- **`test-lock.sh`'s wait was 1800** — shorter than a single loaded-machine suite. Anything queued behind a
  healthy run gave up early, and `pre-commit` then announced the lock "never freed". Now 3600.

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

- **Wall-clock backstop** (`MAXRUN`, 2.5 h) — polls the child's liveness rather than sleeping blindly, so it
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
is touched only when it is an ancestor of `origin/main` and therefore provably pushed. It is purely local (no
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
```

`prove-stop.sh` is the newest and the reason it exists is worth keeping: `daemon.sh` had **no** harness, and
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
- `python3 Tools/mutate.py --only …` — ~45 min per mutant, and it does not take the suite lock itself;
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

Now every newly-seen orphan gets `git diff HEAD` written to `$STATE/rescue/<worktree>.patch`, with the base
sha beside it. A patch rather than a copy: a few KB against a worktree's hundreds of MB (each carries its own
`build/`), diffed against a sha that is already pushed, restorable anywhere with `git apply`. `$ORPHSEEN`
already bounds it to once per worktree per daemon lifetime, and the first snapshot is never overwritten.

⚠️ **What a patch cannot hold: untracked files.** `orphaned_work` uses `--untracked-files=no` on purpose
(every worktree has an untracked `build/`, so counting it would report every worktree always), and `git diff`
cannot see untracked content either. So a session whose only output is a *new, unstaged* file is still not
backed up — the rescue logs a loud warning naming that case rather than reporting a green snapshot.

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
