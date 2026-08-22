#!/usr/bin/env bash
# Vision OCR — autonomous self-resume daemon (L1).
#
# Fires a FRESH headless `claude -p` every cycle to advance the queue by ONE bounded item, then the session
# commits, pushes and stops. Resilient to usage cutoffs: an exhausted window fails fast in ~3 s and the next
# cycle retries when the cap resets. The durable state is the REPO — `BUGS.md`, `TODO.md`, `QUEUE.md` and
# `git log` are all committed, so a fresh session recovers everything from them. That is deliberate and it is
# the main structural difference from the daemon this was ported from, whose queue lived in a gitignored
# 130 KB plan file: here there is no private plan to drift out of step with the trackers.
#
# Scaled down from `Archive Suite/ops/autonomous/archive-suite-autonomous.sh` (1,250 lines). What was
# dropped and why is in ops/autonomous/README.md §"What this deliberately does not have". What was KEPT is
# everything whose absence caused a *silent* failure over there: a status line that lied about throttling, a
# gate that printed ✓ for zero tests, a compactor that aborted invisibly for weeks, and a health line
# structurally unable to report a current failure.
#
# HARD SAFETY:
#   * --permission-mode default (NEVER bypassPermissions / --dangerously-skip-permissions)
#   * scoped --allowedTools + a destructive --disallowedTools denylist (deny wins over allow)
#   * per-session --max-budget-usd + a wall-clock backstop, so no single resume runs away
#   * this script and the `claude` binary live OUTSIDE ~/Desktop (TCC): a launchd-context bash cannot exec a
#     script under Desktop — it dies with "Operation not permitted" and silently no-ops every cycle.
#
# Self-terminates when $RUN's "RUN STATUS:" line reads COMPLETE (a plain greppable line — never markdown).
set -uo pipefail

# ⚠️ EXPLICIT PATH, and this is not boilerplate. vision-ocr's CLAUDE.md documents it as an environment
# trap: "Backgrounded shell commands have essentially no PATH — basename, cut, timeout fail silently and
# loops report bogus results. Use absolute paths." A launchd job is the extreme case of that. Without
# /opt/homebrew/bin the build cannot find `jbig2`/`qpdf` and `bundle-libs.py` reports them "not installed",
# which `build.sh` treats as benign — so the daemon would ship a bundle missing its own tools.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

# Am I being SOURCED rather than executed? Decided here, at the top, because the config validation below
# needs to know before it can safely refuse.
#
# ⚠️ WHY THIS IS NOT MERELY TIDY. `exit` inside a sourced file exits the CALLING SHELL. The full source
# guard lives further down (above the traps, so that sourcing still loads config + functions for a
# maintainer inspecting $DENY/$ALLOW), but the REPO checks below it come FIRST and used to `exit 2` — so
# `. vision-ocr-autonomous.sh` with VISIONOCR_REPO unset would have killed the maintainer's interactive
# shell. Found by running exactly that. When sourced, those checks warn and fall through instead; the
# source guard then stops before anything with a side effect.
_SOURCED=0
[ "${BASH_SOURCE[0]}" != "${0}" ] && _SOURCED=1

# ===== PROJECT CONFIG — env-overridable; `daemon.sh` sets REPO from its own checkout ====================
LABEL="${VISIONOCR_LABEL:-visionocr}"
# The checkout to work in. This script is INSTALLED to ~/.local/bin, outside any checkout, so it cannot
# derive the path from its own location. There is deliberately NO hardcoded fallback: guessing wrong means
# working in a directory that does not exist and failing obscurely every cycle, which is worse than
# refusing to start.
REPO="${VISIONOCR_REPO:-}"
if [ -z "$REPO" ]; then
  echo "vision-ocr-autonomous: VISIONOCR_REPO is unset. Start via ops/autonomous/daemon.sh, which sets it" >&2
  echo "from its own checkout, or export it yourself: VISIONOCR_REPO=/path/to/vision-ocr $0" >&2
  [ "$_SOURCED" = 1 ] || exit 2      # sourced: warn only — `exit` here would kill the caller's shell
fi
if [ -n "$REPO" ] && [ ! -d "$REPO/.git" ] && [ ! -f "$REPO/.git" ]; then
  echo "vision-ocr-autonomous: VISIONOCR_REPO='$REPO' is not a git checkout — refusing to start." >&2
  [ "$_SOURCED" = 1 ] || exit 2
fi
STATE="${VISIONOCR_STATE:-$HOME/.local/state/visionocr-autonomous}"
CLAUDE="${VISIONOCR_CLAUDE:-$HOME/.local/bin/claude}"
# =======================================================================================================
RUN="${VISIONOCR_RUN:-$STATE/RUN.md}"          # run state: RUN STATUS + FOCUS + HOLD + SESSION LOG
QUEUE="${VISIONOCR_QUEUE:-$REPO/ops/autonomous/QUEUE.md}"
LOCK="$STATE/engine.lock"; LOG="$STATE/daemon.log"; PROMPT="$STATE/resume-prompt.txt"
# The live session's `claude` pid, on disk rather than in a variable, for two readers that cannot see a shell
# local: this daemon's OWN signal traps (a TERM can land while the loop is anywhere, and $cpid is `local` to
# the launcher, so under `set -u` a trap that referenced it would abort instead of cleaning up), and
# `daemon.sh stop`, which is a SEPARATE PROCESS and otherwise has nothing but `pgrep -f` patterns to aim at.
# Written after launch, removed after `wait`. Treat its content as a HINT, never as proof of liveness: it
# survives a SIGKILL, so every reader must re-verify that the pid is still the session before signalling it.
# The two readers verify DIFFERENTLY, and each uses the strongest test available to it: the trap in this file
# checks `ppid == $$` (exact — it is the parent); `daemon.sh stop` cannot, so it cross-checks the pid against
# its own `pgrep` for the resume-prompt phrase.
SESSPID="$STATE/session.pid"
COMPACTOR="${VISIONOCR_COMPACTOR:-$HOME/.local/bin/compact-runlog.sh}"
JOB="com.${LABEL}.autonomous"

# ⚠️ EVERY TIMING CONSTANT IN THIS BLOCK WAS SIZED AGAINST A "3-6 MIN" SUITE THAT NOBODY HAD TIMED. Timed on
# 2026-08-16, the same suite ran 416-632 s on a quiet machine and ~37-40 min with other work alongside, and
# ~45 min per run under the C24b campaign's overnight load. (This said 80-632 s: the 80 s and 89 s rows it
# read as a floor are `exit 133` crashes, not fast suites — BUGS.md C24b. A constant sized off 80 s is
# sized off a suite that died.) The health gate that wraps it measured 44m53s.
# There is no single correct number here: this is a personal
# laptop that throttles, and the daemon exists to keep it busy. So the constants below are sized off the
# WORST observed run plus headroom, not off a mean or a single sample, and `test-lock.sh` now records every
# run to $STATE/suite-timings.tsv with its load average so the next person re-derives from data. Two of
# them were wrong by enough to cause real failures — see each one.
INTERVAL="${VISIONOCR_INTERVAL:-90}"      # gap between cycles while the run is PRODUCTIVE. Sessions here run
                                          # long (every code commit triggers a ~40 min suite via the
                                          # pre-commit hook), so this is near-back-to-back in practice.
# ⚠️ LEFT AT 1800 DELIBERATELY, after a change to 9600 was proposed and REFUTED. The tempting argument is
# "a session now runs 95 minutes, so a 30-minute staleness window condemns a healthy session's lock" — and
# it is WRONG, because this lock is HEARTBEATED. See the `touch "$LOCK"` loop in the session launcher: a
# background subshell re-touches it every 60 s for as long as the daemon lives. Verified on the live run —
# engine.lock's mtime tracked wall-clock the whole way through a 95-minute session. So the age of this lock
# never measures how long the session has run; it measures HOW LONG THE HEARTBEAT HAS BEEN DEAD, and the
# heartbeat only dies with the daemon. 1800 s is therefore already "30 missed beats", which is generous.
#
# What raising it to MAXRUN + slack would actually have bought: after a hard kill (lid, SIGKILL) plus a
# launchd restart, the new daemon would sit doing NOTHING for 2 h 40 m before taking over, instead of 30
# minutes. That is a pure regression, and the comment justifying it had the failure mode backwards.
# The real improvement here is not a bigger number: it is recording the session pid IN the lock (it is a
# 0-byte file today) and testing `kill -0`, the way test-lock.sh already does. Left as a follow-up rather
# than done blind.
STALE="${VISIONOCR_STALE:-1800}"          # 30 missed 60-second heartbeats. NOT a session-length budget —
                                          # re-read the note above before touching it.
MAXRUN="${VISIONOCR_MAXRUN:-14400}"       # OUTER wall-clock backstop (4 h). The health watchdog below is
                                          # the PRIMARY killer; this only fires if that fails or a session is
                                          # productive-but-endless.
# ⚠️ RAISED 9000 -> 14400 on 2026-08-19, for the same reason the budget went 20 -> 35 above: A SESSION MUST
# SURVIVE ITS OWN COMMIT. Sized the way the README says to size these -- the WORST row in
# $STATE/suite-timings.tsv you are willing to survive, plus headroom; never the mean, never one run. That
# worst pre-commit row is 5554 s (92.6 min).
# ⛔ AND LOADAVG DOES NOT PREDICT WHERE A RUN LANDS, so there is no quiet-machine discount to bank on: the
# 14 pre-commit rows span 474-5554 s, with 864 s measured at loadavg 12.64 and 3569 s at 3.59.
# A CODE commit under this repo's own discipline needs TWO of those runs -- the watch-the-new-check-fail
# control, then the hook's green run -- so 2 x 5554 s plus the session's own work is ~12300 s, and 9000 s
# cannot fit it.
# WHAT 9000 COST ON 2026-08-19: four consecutive sessions committed work but completed NO item. The fifth ran
# its control at 19:10 (4252 s, rc=1, label `c26-watch-fail`) and was 27 min into its real hook against a
# 20:13 backstop when the owner stopped the daemon -- on course to miss it, though stopped rather than timed
# out, so that last step is inference. The owner landed C26 by hand; that hook took 864 s with the daemon off.
# ⚠️ Read ONCE at module scope, so a change here needs a `daemon.sh start` to take effect -- and the repo is
# the source of truth: `start` re-runs `install -m 755` over ~/.local/bin, so do NOT edit that copy.
# --max-budget-usd per resume session. RAISED 20 -> 35 on the owner's decision, 2026-08-17, and the reason is
# a measurement rather than a preference (README §Defects D6): a session must survive its own commit, and a
# commit here costs a ~43-minute hook (2,552 / 2,575 / 2,615 s, three consecutive rows in
# $STATE/suite-timings.tsv). The 05:19 session died `budget_exhausted` at **$20.14 of $20** with its hook
# still in the suite; the commit landed anyway and the NEXT session had to discover and push it, and the log
# it left behind says "THE COMMIT HAD NOT LANDED" about a commit that had. Three sessions in a row ended that
# way, which is what drives `nocomplete.count` toward the auto-park.
# ⚠️ THE HEADROOM IS FOR POLLING, NOT FOR MORE WORK. Waiting on a detached commit is cheap per wall-clock
# minute but not free: each poll turn re-reads a large context, ~$0.35-0.40 at the sizes these sessions reach
# (the 05:19 session read 23.3M cached tokens over 151 turns). ~43 minutes of polling is therefore ~$4, and
# $15 of headroom is deliberately more than that — a session that has done its work must never be unable to
# AFFORD to land it. If this stops helping, the next lever is item size, not another raise.
BUDGET="${VISIONOCR_BUDGET:-35}"
EFFORT="${VISIONOCR_EFFORT:-xhigh}"       # low|medium|high|xhigh|max. xhigh, not max: it is the documented
                                          # sweet spot for agentic coding work, while max overthinks for
                                          # diminishing returns AND reaches the usage cap sooner — which on
                                          # this laptop costs COMPLETED ITEMS per window, not quality.
                                          # NOTE both this and --model resolve BEFORE the session picks its
                                          # item, so per-ITEM tuning is not expressible here. What a session
                                          # CAN vary per task is its SUBAGENTS' model/effort; the resume
                                          # prompt delegates that to it explicitly.

# Idle backoff — the loop's answer to "nothing is happening". Any cycle that advances nothing doubles the
# gap up to $MAXBACKOFF; any progress resets it instantly; $IDLE_STOP of unbroken no-progress PARKS the run.
MAXBACKOFF="${VISIONOCR_MAXBACKOFF:-1800}"
IDLE_STOP="${VISIONOCR_IDLE_STOP:-259200}" # 72 h, not 6 h: a long usage-cap outage reads as "waiting", not
                                           # "idle". A weekly cap can exceed the ~5 h rolling window, so a
                                           # short idle clock would park a run that is merely waiting for the
                                           # window to reopen. 0 disables the auto-park.

MINFREE_MB="${VISIONOCR_MINFREE_MB:-8192}" # a full disk fails EVERY build; park below 8 GB. Lower than the
                                           # sibling's 10 GB because this project builds one small app rather
                                           # than three, but the corpus is 1.2 GB so it is not tiny either.

# Attempt cap — the one waste the idle backoff CANNOT catch. Backoff keys off the fingerprint MOVING, and a
# mis-sized or subtly-failing item that commits a checkpoint each session keeps moving it, so it reads as
# progress forever. This counts consecutive sessions that committed work but completed NO item.
MAX_NOCOMPLETE="${VISIONOCR_MAX_NOCOMPLETE:-5}"

# Health gate. Every $GATE_EVERY commits the daemon runs the gate itself — deterministic (build/test), so no
# session and no LLM. The last-GREEN sha persists across restarts (the cadence tracks code churn, not daemon
# lifetime); a missing/invalid sha fails OPEN (gate due now). 0 disables.
#
# ⚠️ WHY 10 AND NOT 30. In the project this was ported from, nothing gated a commit except the session's own
# discipline, so the periodic gate was the only backstop and ran every 30. Here `.githooks/pre-commit`
# already runs the FULL suite on every commit that touches Sources/Helper/Tests/Tools/build.sh/run_tests.sh,
# so per-commit regression cover is not this gate's job. Its job is the three things the hook does NOT do:
# `./build.sh` (the hook builds only when a view file is staged, yet the suite excludes App.swift entirely),
# `check-tools-compile.sh` over EVERY tool rather than the staged ones, and the document-coherence checks.
# Those are NOT cheap: the gate runs the suite too, and on 2026-08-16 it measured 44m53s all in. The owner's
# standing decision (2026-08-16) is to KEEP the suite in the gate — it is the one check that does not trust
# the hook, and it is not the throughput bottleneck, since any code commit already pays ~40 min in the hook.
# `VISIONOCR_GATE_QUICK=1` drops the suite AND ./build.sh if that is ever wanted; what remains is
# tools-compile plus the document checks. Deliberately NOT given a duration here — nobody has timed the
# quick gate, and the only bound available (44m53s minus the suite) still includes the build that QUICK
# also drops. Measure it before quoting it.
GATE_EVERY="${VISIONOCR_GATE_EVERY:-10}"
GATE_CMD="${VISIONOCR_GATE_CMD:-$REPO/ops/autonomous/health-gate.sh}"
# ⚠️ WAS 2700, AND THE LAST GATE FINISHED IN 2693 — SEVEN SECONDS UNDER THE CAP. The old comment read "the
# gate itself is ~10 min"; the measured run on 2026-08-16 was 17:54:30 → 18:39:23 GREEN, i.e. 44m53s against
# a 45-minute kill. A gate one percent slower is killed, that counts as a TIMEOUT, and $GATE_MAX_TIMEOUTS of
# them PARKS THE RUN — so the run was one slow gate away from parking itself over nothing. DERIVED: the gate
# is tools-compile (~2 min) + suite (39m30s) + ./build.sh + doc checks ≈ 45 min, and it may additionally WAIT
# up to $VISIONOCR_TEST_LOCK_WAIT (3600) on the lock behind another run. 9000 covers both without ever
# false-parking; the health watchdog, not this cap, is the real defence against a wedged gate.
# ⚠️ RAISED 9000 -> 14400 on 2026-08-19, the same defect as $MAXRUN above and by the README's own stated
# method (take the WORST row you will survive, add headroom, never the mean). The derivation above assumed a
# 39m30s suite. It is not one any more: suite-timings.tsv's worst row is 5554 s (92.6 min), so a gate is
# ~2 min tools-compile + ~93 min suite + ./build.sh + doc checks = ~100 min, and it may STILL wait a full
# $VISIONOCR_TEST_LOCK_WAIT (3600 s) behind another run -- about 9600 s, already OVER the 9000 s cap it was
# being measured against. An overrun counts as a TIMEOUT and $GATE_MAX_TIMEOUTS of them PARKS THE RUN, so
# this was the 2700-vs-2693 mistake a second time, in the same constant, from the suite growing underneath it.
GATE_MAXRUN="${VISIONOCR_GATE_MAXRUN:-14400}"  # 4 h = one full gate (~100 min) + a full lock wait (60 min)
                                               # + margin. A cap below true runtime is what false-parks a
                                               # healthy run, and that had become one bad minute away.
GATE_MAX_TIMEOUTS="${VISIONOCR_GATE_MAX_TIMEOUTS:-2}"

STATUS_CMD="${VISIONOCR_STATUS_CMD:-$REPO/ops/autonomous/status-digest.sh}"

# Health watchdog (Layers 1+2) — detect a session gone astray WITHOUT relying on the clock. The session runs
# with --output-format stream-json --include-partial-messages, so $SLOG grows in real time with a JSON event
# per message/tool AND per token-delta during generation. Token-delta streaming is why a long high-effort
# generation is not mistaken for a hang: the log keeps growing while the model thinks.
#   L1 (event heartbeat): non-rate_limit_event bytes stop growing for HB_STALL -> "quiet".
#   L2 (liveness): when quiet, SPARE the session if a `claude` DESCENDANT exists (a subagent, whose work does
#                  not stream into the parent log and may sit at ~0% CPU blocked on the API) OR the tree is
#                  CPU-busy (a real build/suite). Idle tree + no subagent for HB_IDLE_N polls -> wedged.
#                  CPU-busy + no subagent + no events for HB_HARD -> runaway.
# ⚠️ HB_HARD is 3600 s here (60 min), raised from 3000 on 2026-08-16 and NO LONGER for the reason the old
# comment gave. It said "the full catalogue is ~70 min", which was arithmetic on a 2-4 min suite. Measured
# 2026-08-17 by the C24b campaign: ~45 min per mutant (2621-2719 s) over the whole catalogue — whose size
# is `python3 Tools/mutate.py --list | tail -1` and NOT a number written here, this comment having said 84
# and then 89 while the tool printed 91 — so the full catalogue is on the order of 65 HOURS and no watchdog
# setting makes it survivable; the resume prompt forbids it outright instead. Note the per-mutant figure is
# a reading of the machine and not of the suite: the same catalogue recorded ~630 s per mutant THAT MORNING
# (09:47, committed 09:59 in 41815b9 — this comment said "the evening before", which put both readings in
# the same half of the day and garbled the only argument it was making), across four checks of growth, so
# contention moves it more than size does (BUGS.md C24b).
# The real case this must not kill is the ordinary one: a session sitting inside its own
# `git commit`, which is CPU-busy and silent for the hook's ~40 min. 3000 left only ten minutes of headroom
# over that, and a commit that also waited on the suite lock would have been killed as a runaway while doing
# exactly what it was told to. 60 min is one suite plus half again.
HB_POLL="${VISIONOCR_HB_POLL:-20}"
HB_STALL="${VISIONOCR_HB_STALL:-600}"
HB_HARD="${VISIONOCR_HB_HARD:-3600}"
HB_CPU="${VISIONOCR_HB_CPU:-3}"
HB_IDLE_N="${VISIONOCR_HB_IDLE_N:-3}"

# Tools a work session legitimately needs. DENY WINS OVER ALLOW. These are ARRAYS, not strings: the patterns
# contain spaces, so each MUST be one argv element — passed as "${DENY[@]}", never unquoted (unquoted
# word-splits the space and claude sees "-rf:*)" as an unknown option).
ALLOW=(Bash Edit Write Read Grep Glob Task Agent Workflow TodoWrite WebFetch WebSearch)
DENY=(
  "Bash(sudo:*)" "Bash(launchctl:*)"
  "Bash(rm -rf:*)" "Bash(rm -fr:*)" "Bash(rm -r:*)" "Bash(rm -R:*)"
  "Bash(git push --force:*)" "Bash(git push -f:*)" "Bash(git push --force-with-lease:*)"
  "Bash(git reset --hard:*)" "Bash(git clean:*)"
  "Bash(git worktree remove --force:*)" "Bash(git worktree remove -f:*)" "Bash(git branch -D:*)"
  "Bash(git commit --no-verify:*)" "Bash(git commit -n:*)"
  "Bash(shutdown:*)" "Bash(reboot:*)" "Bash(halt:*)"
  "Bash(diskutil:*)" "Bash(dd:*)" "Bash(mkfs:*)" "Bash(curl:*)" "Bash(wget:*)"
  # Release is owner-only (QUEUE.md HOLD). These block the DIRECT invocation of its steps.
  "Bash(hdiutil:*)" "Bash(gh release:*)" "Bash(/opt/homebrew/bin/gh release:*)"
  # KEEP THE DAEMON OFF THE OWNER'S SCREEN. `./build.sh --install` stages into /Applications and `--run`
  # launches the app; `open`/`osascript` put a window on the physical display. The off-screen lane is
  # `Tools/vm-gui-check.sh`, which runs in the Tart VM with its own virtual display — the resume prompt
  # points there. Not a hard boundary (a child process could still reach `open`), so the prompt rule is the
  # primary control and this is defence in depth.
  "Bash(open:*)" "Bash(osascript:*)" "Bash(cliclick:*)"
  "Bash(./build.sh --install:*)" "Bash(./build.sh --run:*)"
)
# ⚠️ `git commit --no-verify` is denied above and that is load-bearing, not tidiness. The pre-commit hook is
# what makes every code commit test-gated, and it is the ONLY thing standing between an unattended session
# and pushing untested code. A session that hits a failing suite must fix it or stop — never bypass it.

# ⚠️ NO SIDE EFFECTS BELOW THIS POINT UNTIL THE SOURCE GUARD. `mkdir -p "$STATE"` and the startup
# counter-clear both used to live up here and both ran on a mere `source`; see the guard's own comment for
# what that cost. Config, function definitions and `source` of a functions-only library are all that belong
# in this region.

# run-state-lib.sh — the ONE place that decides what "the daemon is not advancing" MEANS. Sourced here, and
# not reimplemented, because its own header is right that a detector written twice is a detector that gets
# fixed once: the daemon's progress verdict and the status digest have to agree about "a session left work
# uncommitted", or the log and the status line contradict each other over the same worktree.
# Guarded and stubbed in the same SHAPE as status-digest.sh, but resolved differently and on purpose:
# the digest uses $HERE so a worktree's digest consults that worktree's lib, whereas this file is
# INSTALLED to ~/.local/bin, outside any checkout, so $HERE would point at the install dir and find
# nothing. $REPO is the only thing that resolves for both the launchd copy and a direct run.
# The guard itself is not optional: this is what launchd relaunches, and it must degrade rather than die
# at line one on a checkout that predates the lib.
if [ -r "$REPO/ops/autonomous/run-state-lib.sh" ]; then
  # shellcheck source=/dev/null
  . "$REPO/ops/autonomous/run-state-lib.sh"
else
  orphaned_work() { return 1; }
  orphaned_work_summary() { return 1; }
fi

log() { printf '%s  %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

# Regenerate the one-screen $STATE/STATUS.md digest. Cheap, read-only, never fatal. Written to a temp then
# mv'd so a concurrent reader never sees a half-written file.
write_status() {   # $1 (optional) = park reason -> render PARKED even though this process is still alive
                   # (park_run calls this BEFORE its bootout, so the digest's pgrep check would else lie).
  [ -x "$STATUS_CMD" ] || return 0
  VISIONOCR_STATUS_PARKED="${1:-}" VISIONOCR_REPO="$REPO" VISIONOCR_STATE="$STATE" \
    "$STATUS_CMD" > "$STATE/STATUS.md.tmp" 2>/dev/null \
    && mv -f "$STATE/STATUS.md.tmp" "$STATE/STATUS.md" 2>/dev/null \
    || rm -f "$STATE/STATUS.md.tmp" 2>/dev/null
  return 0
}

# Alert config lives in its OWN file, sourced WITHOUT `set -a`, and that is load-bearing — NOT style.
# $STATE/env is the CHILD's environment (tick() re-sources it under allexport to hand vars to `claude -p`),
# so anything placed there is inherited by every session — and a session is an LLM agent with Bash+WebFetch
# whose curl/wget denylist exists precisely so it CANNOT phone out. Handing it the operator's alert endpoint
# would defeat that. Keeping ALERT_* as plain non-exported shell vars means notify() sees them and the child
# never does. Also deliberately NOT sourcing $STATE/env here: that file may set PATH, and this runs before
# the `caffeinate` launch below — a PATH without /usr/bin would silently fail to keep the Mac awake.
[ -f "$STATE/alert.env" ] && . "$STATE/alert.env"

# Remote alerting — reach an owner who is NOT at the machine, which is exactly when an unattended run needs
# them (a Desktop file and a local notification are useless to someone who is out). Deliberately generic: a
# plain POST, so no service is baked in. ntfy.sh works with zero setup. NO-OP when unconfigured, NEVER
# fatal, and --max-time so a dead network cannot hang the loop.
#   NOTE: `curl` is denied to SESSIONS, not to this loop. Sessions must not phone out; the operator's daemon
#   must. That asymmetry is intentional.
notify() {
  local title msg
  # Strip CR/LF: $title becomes an HTTP header value and curl does NOT reject embedded newlines — it emits
  # them as extra real headers. Callers pass free-ish text, so sanitise at the boundary.
  title=$(printf '%s' "$1" | tr -d '\r\n')
  msg="$2"
  [ -n "${ALERT_URL:-}" ] || return 0
  # ARRAY, not a string — a header value contains spaces so it must be exactly one argv element. Seeded
  # non-empty so "${args[@]}" is safe under `set -u` on macOS bash 3.2, where an empty array expansion is an
  # "unbound variable" error.
  local -a args=(-fsS --max-time 15 -X POST -H "Title: $title")
  [ -n "${ALERT_AUTH:-}" ] && args+=(-H "Authorization: $ALERT_AUTH")
  # Body via STDIN, never as an argv value: curl treats a LEADING '@' in --data-binary as "read this file",
  # and '@-' means stdin — which from a nohup'd daemon whose stdin is an idle TTY hangs FOREVER and is not
  # bounded by --max-time. Make it structurally impossible: the arg is always the literal '@-'.
  args+=(--data-binary @- "$ALERT_URL")
  if printf '%s' "$msg" | curl "${args[@]}" >/dev/null 2>&1; then log "alert sent: $title"
  else log "alert FAILED (non-fatal, continuing): $title"; fi
  return 0
}

# ---- Disk guard ----
# macOS/BSD `df -m` column 4 = Available MB. Any unparseable output (empty, a wrapped long-device-name line,
# a suffix, a negative) trips the numeric guard and FAILS OPEN — a broken check must never stop a good run.
free_mb() { df -m "$REPO" 2>/dev/null | awk 'NR==2 {print $4}'; }
LAST_FREE_MB="?"
disk_ok() {
  local f; f="$(free_mb)"
  case "$f" in ''|*[!0-9]*) return 0 ;; esac
  LAST_FREE_MB="$f"
  [ "$f" -ge "$MINFREE_MB" ] && return 0
  log "low disk: ${f}MB free (< ${MINFREE_MB}MB) — running housekeeping to reclaim…"
  housekeeping
  f="$(free_mb)"
  case "$f" in ''|*[!0-9]*) return 0 ;; esac
  LAST_FREE_MB="$f"
  [ "$f" -ge "$MINFREE_MB" ] && { log "disk reclaimed: ${f}MB free — continuing."; return 0; }
  return 1
}

# ===== Progress, DERIVED and never self-reported =====================================================
# A cycle counts as progress iff this fingerprint MOVED. The model cannot forget to set a flag, and a
# session that believes it worked cannot lie past an unchanged hash. Exit code deliberately does NOT gate
# it: a session that ships a commit then gets killed (budget/watchdog) still advanced the run, while a
# usage-limit fast-fail cannot move the hash and falls through to no-progress on its own.
#
# It hashes the DECISION SURFACE a fresh session reads to choose work: the repo tip, the RUN STATUS line, and
# the queue's checkbox state. The SESSION LOG region of $RUN is EXCLUDED ON PURPOSE — a no-op session still
# appends its reasoning there, and hashing that churn would reset the backoff every cycle and silently
# restore the spin this mechanism exists to stop.
#
# QUEUE.md is committed, so it already rides in `rev-parse HEAD`; it is hashed DIRECTLY as well so that the
# owner editing the queue in the working tree — arming an item without committing — wakes the daemon
# immediately via backoff_sleep. That is the single most common way a human unblocks this run.
#
# ⚠️ AND origin/main, BECAUSE "THE TIP" IS NOT ONE REF. A session works in its own worktree and pushes from
# there; fast-forwarding the PRIMARY checkout afterwards is something sessions do only sometimes. Measured
# 2026-08-18: the 02:41 session committed `bd574ac`, pushed it, removed its worktree and stopped — and this
# function, reading only the primary checkout's HEAD, returned an unchanged fingerprint. The daemon logged
# "advanced nothing (queue + tip unchanged)" at 04:14:21 over work that was already public, slept 1800s
# instead of 90s, and left the idle stopwatch reading 21142s. `git reflog` dates it exactly:
# refs/remotes/origin/main reached bd574ac at 04:13:07 — 74 s before that verdict — while main itself did not
# arrive until 04:44:51, dragged there by the NEXT session's `pull --rebase`. So the run's own record of what
# it had accomplished lagged a full cycle behind reality, once per session that pushed this way.
#
# It costs nothing and needs no network: a push updates this checkout's remote-tracking ref, and refs/remotes
# is SHARED with every linked worktree. housekeeping() already relies on precisely that — it deletes branches
# on the strength of this ref and says so ("PURELY LOCAL: no `git fetch` — the session's push already advanced
# the origin/main ref this checkout"). Before this line the daemon's two halves disagreed about where
# "landed" is written down, and the half that scored the run was the one that had it wrong.
#
# A move made by someone ELSE — the owner pushing from another machine, an interactive session landing a
# commit — reads as progress here, and that is correct rather than tolerated: per the accelerator note below,
# a changed fingerprint means only "the decision surface moved, retry NOW", which is exactly what a fresh
# push from any source warrants.
work_fingerprint() {
  {
    git -C "$REPO" rev-parse HEAD 2>/dev/null || echo no-head
    # --verify --quiet, the same form housekeeping() uses on this ref: a BARE `rev-parse <missing-ref>` echoes
    # the ref name back on STDOUT and *also* exits nonzero, so the `|| echo` fallback would append to it rather
    # than replace it. Deterministic either way, so the fingerprint would still be stable — but a fallback
    # string that never appears alone is a fallback nobody can reason about. (The `HEAD` line above has the
    # same latent shape in a repo with no commits; left alone, and recorded in README §D10, because the daemon
    # refuses to start without a repo and that is a different change.)
    git -C "$REPO" rev-parse --verify --quiet refs/remotes/origin/main 2>/dev/null || echo no-remote-tip
    grep -m1 '^RUN STATUS:' "$RUN" 2>/dev/null || echo no-status
    grep -E '^[[:space:]]*[-*][[:space:]]+\[[ xX]\]' "$QUEUE" 2>/dev/null || echo no-queue
  } | shasum -a 256 2>/dev/null | cut -d' ' -f1
}

# WHY THE FINGERPRINT IS AN ACCELERATOR, NOT A GATE. It is tempting to SKIP the session outright while the
# fingerprint is unchanged ("a fresh session would provably reach the same conclusion — don't pay for it").
# That was rejected on evidence in the sibling project: a session concluded "nothing actionable" at 09:34,
# and at 10:40 — identical HEAD and queue — a session found real work and shipped a real fix. These sessions
# are NONDETERMINISTIC, so "same inputs => same conclusion" is false. An unchanged fingerprint therefore only
# means "keep backing off" (still retrying, just rarely); a CHANGED one is a positive signal to retry NOW.
BACKOFF="$INTERVAL"
IDLE_SINCE="$STATE/idle.since"
NOCOMPLETE="$STATE/nocomplete.count"
# Worktrees already reported as holding orphaned work, so each is named once per daemon lifetime rather
# than once per cycle. Cleared at startup with the other counters — a restart is the owner saying "tell me
# again", exactly as it is for the idle stamp.
ORPHSEEN="$STATE/orphans.seen"
# (The startup clear of these counters lives BELOW the source guard — see the note there. It used to be
# here, where a `source` of this file ran it against whatever $STATE resolved to.)

note_progress() {
  [ "$BACKOFF" != "$INTERVAL" ] && log "progress — backoff reset to ${INTERVAL}s."
  BACKOFF="$INTERVAL"; rm -f "$IDLE_SINCE" 2>/dev/null || true
  return 0
}

# How many work items the run has finished, summed across BOTH places an item can be completed: a ticked
# QUEUE.md box, and a register entry that has become closed. Counting only the queue would read a constant
# through any session whose whole output was closing a `BUGS.md` entry, and would then FALSE-PARK a healthy
# run at $MAX_NOCOMPLETE. Errs toward COUNTING a completion: a missed one false-parks (bad), a spurious one
# only misses a runaway, which the budget cap and idle backoff still backstop.
completed_items() {
  local q b re='^[[:space:]]*[-*][[:space:]]+\[[xX]\]'
  q=$(grep -cE "$re" "$QUEUE" 2>/dev/null)
  # Closed register entries: `### <TAG> · … — FIXED|WONTFIX|NO DEFECT`. Anchored to the heading so a `[x]`
  # or the word FIXED in prose cannot inflate it.
  b=$(grep -cE '^###[[:space:]].*—[[:space:]]*\*?\*?(FIXED|WONTFIX|NO DEFECT)' "$REPO/BUGS.md" 2>/dev/null)
  case "$q" in ''|*[!0-9]*) q=0 ;; esac
  case "$b" in ''|*[!0-9]*) b=0 ;; esac
  echo $(( q + b ))
}

# Verdict for a session that COMMITTED work. $1 = completed-count before, $2 = after.
# Returns 9 when the no-completion streak hits $MAX_NOCOMPLETE (caller parks); 0 to keep going.
note_committed() {
  local cc_before="$1" cc_after="$2" n
  [ "$MAX_NOCOMPLETE" -gt 0 ] || return 0
  if [ "$cc_after" -gt "$cc_before" ]; then
    [ -f "$NOCOMPLETE" ] && log "item completed (done $cc_before->$cc_after) — attempt streak reset."
    rm -f "$NOCOMPLETE" 2>/dev/null || true
    return 0
  fi
  n=$(cat "$NOCOMPLETE" 2>/dev/null); case "$n" in ''|*[!0-9]*) n=0 ;; esac
  n=$(( n + 1 )); echo "$n" > "$NOCOMPLETE" 2>/dev/null || true
  if [ "$n" -ge "$MAX_NOCOMPLETE" ]; then
    local recent; recent="$(git -C "$REPO" log -5 --format='  %h %s' 2>/dev/null)"
    rm -f "$NOCOMPLETE" 2>/dev/null || true   # don't re-park instantly on a bare restart with no fresh streak
    park_run "no item completed in $n sessions" \
      "Vision OCR autonomous run PARKED: $n sessions committed work but completed NO item (no QUEUE.md box
flipped, no BUGS.md entry closed). The current item is likely mis-sized or stuck — checkpoints keep landing
but nothing finishes. Split or re-scope it in ops/autonomous/QUEUE.md, or raise
VISIONOCR_MAX_NOCOMPLETE, then restart. Recent commits:
$recent"
    return 9
  fi
  log "committed but no item completed — attempt streak $n/$MAX_NOCOMPLETE."
  return 0
}

# Sleep out the current $BACKOFF but WAKE EARLY the moment the decision surface changes. This is the other
# half of "accelerator, not gate": backing off is what stops the waste, but the owner arming an item must not
# then sit through a 30-minute nap — that arming is the whole point. Poll cost is one rev-parse + one hash.
backoff_sleep() {
  local fp0 waited=0 step
  fp0="$(work_fingerprint)"
  step="$BACKOFF"; [ "$step" -gt 30 ] && step=30
  while [ "$waited" -lt "$BACKOFF" ]; do
    sleep "$step"; waited=$(( waited + step ))
    if [ "$(work_fingerprint)" != "$fp0" ]; then
      log "decision surface changed during backoff (commit / queue edit) — retrying now."
      note_progress; return 0
    fi
  done
  return 0
}

# Park the run: stop cleanly and say so LOUDLY (log + Desktop file + local notification + remote alert)
# rather than idling forever holding a caffeinate assertion. Deliberately does NOT rewrite RUN STATUS: the
# run stays IN_PROGRESS so a plain restart resumes with no edit.
park_run() {
  local reason="$1" m="$2"
  rm -f "$IDLE_SINCE" 2>/dev/null || true
  # Release the engine lock HERE, not in the caller's cleanup: under KeepAlive the `launchctl bootout` below
  # SIGTERMs THIS process the instant it is called, so everything textually after it — including tick()'s
  # `rm -f "$LOCK"` — never runs. Without this an idle/attempt-cap park leaves a fresh lock behind and a
  # restart within $STALE would no-op with "engine busy".
  rm -f "$LOCK" 2>/dev/null || true
  # Release the SUITE lock too, for the same reason: a park during a gate would otherwise strand it until
  # its MAXAGE, blocking the owner's own `./run_tests.sh` for 90 minutes with no visible cause.
  rm -rf "${VISIONOCR_TEST_LOCK:-$STATE/test.lock}" 2>/dev/null || true
  log "!!!!!!!!!!!! PARKED ($reason) — stopping. $m"
  { echo "[$(date '+%F %T')] $m"; } > "$HOME/Desktop/VISION-OCR-RUN-PARKED.txt" 2>/dev/null || true
  notify "Vision OCR: run parked ($reason)" "$m"
  write_status "$reason"
  # $reason goes in as an argv PARAMETER, never interpolated into the script text: a double quote in it
  # would otherwise close the AppleScript string and the rest would EXECUTE (`do shell script …`). Today's
  # callers are fixed text and numbers, but one future caller surfacing a build error or a path is all it
  # would take, so make it structurally impossible.
  osascript -e 'on run argv
display notification ("Run parked: " & (item 1 of argv) & ". See VISION-OCR-RUN-PARKED.txt on your Desktop.") with title "Vision OCR: autonomous run parked" sound name "Basso"
end run' "$reason" >/dev/null 2>&1 || true
  launchctl bootout "gui/$(id -u)/$JOB" 2>/dev/null || true
  return 0
}

# Returns 9 when the run has been idle past $IDLE_STOP (caller stops the loop); 0 to keep going.
note_no_progress() {
  local now idle since
  now=$(date +%s)
  # Re-stamp on anything non-numeric (missing, empty, a truncated write) — a bad stamp must never wedge the
  # arithmetic, and re-stamping only ever DELAYS the park, so it fails safe.
  since=$(cat "$IDLE_SINCE" 2>/dev/null)
  case "$since" in ''|*[!0-9]*) since="$now"; echo "$now" > "$IDLE_SINCE" 2>/dev/null || true ;; esac
  idle=$(( now - since ))
  BACKOFF=$(( BACKOFF * 2 ))
  [ "$BACKOFF" -gt "$MAXBACKOFF" ] && BACKOFF="$MAXBACKOFF"
  if [ "$IDLE_STOP" -gt 0 ] && [ "$idle" -ge "$IDLE_STOP" ]; then
    local hrs=$(( IDLE_STOP / 3600 ))
    park_run "no progress for ${hrs}h" \
      "Vision OCR autonomous run PARKED: ${hrs}h with no progress — every remaining queue item looks blocked
on you, or the queue is drained. Nothing was lost. Check:  ./ops/autonomous/daemon.sh status
then restart it with:  ./ops/autonomous/daemon.sh start"
    return 9
  fi
  log "no progress (idle ${idle}s) — next attempt in ${BACKOFF}s."
  return 0
}

# ---- Health gate ------------------------------------------------------------------------------------
# Run GATE_CMD once under a wall-clock cap. Sets GATE_RC = 0 green | 1 red | 2 timeout; $glog holds output.
# The cap matters because the gate runs SYNCHRONOUSLY in the daemon loop — a hang would freeze the WHOLE
# daemon, so a hung gate is killed and treated as INCONCLUSIVE rather than as a failure.
GATE_STATE="$STATE/last-gate"; GATE_TO="$STATE/gate-timeouts"; glog="$STATE/last-gate.log"
_run_gate_once() {
  "$GATE_CMD" >"$glog" 2>&1 &
  local gpid=$! waited=0
  # 2 s granularity so a finished gate is noticed promptly; still cheap for a minutes-long real gate.
  while kill -0 "$gpid" 2>/dev/null && [ "$waited" -lt "$GATE_MAXRUN" ]; do sleep 2; waited=$(( waited + 2 )); done
  if kill -0 "$gpid" 2>/dev/null; then
    _terminate_tree "$gpid"; wait "$gpid" 2>/dev/null || true   # reap so no zombie lingers
    GATE_RC=2; return 0
  fi
  wait "$gpid"; GATE_RC=$?
  [ "$GATE_RC" -eq 0 ] || GATE_RC=1     # normalize any nonzero to RED
  return 0
}

# Classify a RED verdict in $glog into DOCUMENT vs CODE steps. Assigns the CALLER's vars deliberately (not
# `local`), and MUST reset has_code/doc_list on every call: health_gate() may call this twice, and a second
# document-only verdict inheriting has_code=1 from the first would be parked as a code regression — the
# precise misreport this classification exists to stop.
_classify_red() {
  vline="$(grep -m1 '^HEALTH GATE: RED' "$glog" 2>/dev/null)"
  # Strip the prefix plus any separator bytes (the em dash is multi-byte, so a byte-based cut could split
  # it), collapse runs of spaces, and trim.
  steps="$(printf '%s' "$vline" | sed 's/^HEALTH GATE: RED[^A-Za-z0-9]*//' | tr -s ' ' | sed 's/^ *//; s/ *$//')"
  has_code=0; doc_list=""
  # Split on spaces EXPLICITLY. Do NOT rely on the ambient IFS: this can run under an inherited environment
  # (launchd, a sourced profile) where IFS is not the default, and with IFS=$'\n' the loop sees one word
  # " staleness" WITH its leading space, no `case` pattern matches, and every document failure silently
  # misclassifies as a code regression.
  local s IFS=' '
  for s in $steps; do
    case "$s" in
      staleness|queue-coherence) doc_list="${doc_list:+$doc_list }$s" ;;
      *)                        has_code=1 ;;
    esac
  done
  return 0
}

# Returns: 9 = RED/park (caller stops the loop) · 10 = ran GREEN (that WAS this cycle's work) ·
# 0 = not due, or an inconclusive timeout-skip (caller continues to a normal session).
# Must be called only when no other engine is active.
health_gate() {
  [ "$GATE_EVERY" -gt 0 ] || return 0
  local last cnt
  last="$(cat "$GATE_STATE" 2>/dev/null)"
  if [ -n "$last" ] && git -C "$REPO" cat-file -e "$last^{commit}" 2>/dev/null; then
    cnt="$(git -C "$REPO" rev-list --count "$last..HEAD" 2>/dev/null || echo "$GATE_EVERY")"
  else
    cnt="$GATE_EVERY"     # never gated, or a stale/rewritten sha -> fail OPEN (gate now)
  fi
  case "$cnt" in ''|*[!0-9]*) cnt="$GATE_EVERY" ;; esac
  [ "$cnt" -ge "$GATE_EVERY" ] || return 0
  [ -x "$GATE_CMD" ] || { log "health gate: GATE_CMD not executable ($GATE_CMD) — skipping (fail-open)."; return 0; }
  log "health gate DUE ($cnt commits since last green) — running $GATE_CMD (build+suite, may take minutes)…"
  _run_gate_once

  # TIMEOUT is INCONCLUSIVE — a hang, not a proven regression — so do NOT park on one. But a PERSISTENT hang
  # (a stuck prompt, a cap below true runtime, a suite lock never released) would silently waste GATE_MAXRUN
  # every cycle forever, so escalate at $GATE_MAX_TIMEOUTS.
  if [ "$GATE_RC" -eq 2 ]; then
    local n; n="$(cat "$GATE_TO" 2>/dev/null)"; case "$n" in ''|*[!0-9]*) n=0 ;; esac; n=$(( n + 1 ))
    echo "$n" > "$GATE_TO" 2>/dev/null || true
    if [ "$n" -ge "$GATE_MAX_TIMEOUTS" ]; then
      rm -f "$GATE_TO" 2>/dev/null || true
      park_run "health gate hung x$n" \
        "Vision OCR autonomous run PARKED — the health gate TIMED OUT $n cycle(s) in a row (${GATE_MAXRUN}s cap).
That is a hang, not a regression. Most likely: a suite lock nobody released (check
./ops/autonomous/test-lock.sh status), or a build waiting on a prompt. Run
./ops/autonomous/health-gate.sh yourself to see where it wedges. Last tail:
$(printf '%s' "$(cat "$glog" 2>/dev/null)" | tail -20)"
      return 9
    fi
    log "health gate TIMED OUT after ${GATE_MAXRUN}s (${n}/${GATE_MAX_TIMEOUTS}) — killed + SKIPPED (inconclusive). See $glog."
    return 0
  fi
  rm -f "$GATE_TO" 2>/dev/null || true     # a conclusive result resets the timeout streak

  if [ "$GATE_RC" -eq 0 ]; then
    git -C "$REPO" rev-parse HEAD > "$GATE_STATE" 2>/dev/null || true
    log "health gate GREEN @ $(git -C "$REPO" rev-parse --short HEAD 2>/dev/null)."
    return 10
  fi

  # RED — RETRY ONCE before parking. A real compounding regression is deterministic and fails the retry too;
  # a flaky check or a transient build blip passes it. Retrying strictly cuts false-parks without hiding a
  # real regression. It matters more here than in the sibling project: this suite runs REAL OCR, and a
  # collision with an out-of-band suite (the very thing test-lock.sh guards) shows up as unrelated failures.
  log "health gate RED — retrying ONCE before parking (guards against a flaky check or a suite collision)…"
  _run_gate_once
  if [ "$GATE_RC" -eq 0 ]; then
    git -C "$REPO" rev-parse HEAD > "$GATE_STATE" 2>/dev/null || true
    log "health gate GREEN on retry — the first failure was transient (not parking)."
    return 10
  fi
  if [ "$GATE_RC" -eq 2 ]; then log "health gate timed out on retry — SKIPPING (inconclusive, not parking)."; return 0; fi

  # WHICH step failed decides what the owner should go and DO, and the gate already says so in a line the
  # park note must quote rather than guess at. In the sibling project a park whose only failing step was a
  # DOCUMENT size check reached the owner as "a reproducible build/test regression" on "a broken tree", and
  # cost him a morning hunting a bug that did not exist. Name the step; assert no cause the gate did not.
  local vline steps has_code=0 doc_list="" diag
  _classify_red
  if [ "$has_code" = 1 ]; then
    # A mixed RED counts as CODE (the conservative reading), but still say the doc step failed too.
    diag="FAILED STEP(S): $steps — a reproducible build/suite regression. The daemon stopped so it does not
  pile more commits on a broken tree.${doc_list:+
  Also failing (document coherence, not code): $doc_list}"
  elif [ -n "$doc_list" ]; then
    diag="FAILED STEP(S): $doc_list — and NOTHING IS WRONG WITH THE CODE: every build and check in this gate
  PASSED. These steps compare what the documents CLAIM against what is true, so this is a document edit,
  not a bug hunt. Reproduce instantly:  ./ops/autonomous/check-staleness.sh"
  else
    diag="the gate exited nonzero but printed no 'HEALTH GATE: RED' verdict line, so the failing step is
  UNKNOWN — read $glog in full before assuming a code regression."
  fi
  park_run "health gate RED (x2)${steps:+ — $steps}" \
    "Vision OCR autonomous run PARKED — the periodic HEALTH GATE failed TWICE in a row.
$diag
Reproduce: ./ops/autonomous/health-gate.sh   ·   full output: $glog
Then restart it: ./ops/autonomous/daemon.sh start
Gate verdict + tail:
${vline:-(no 'HEALTH GATE: RED' line in $glog)}
$(printf '%s' "$(cat "$glog" 2>/dev/null)" | tail -25)"
  return 9
}

# ---- Housekeeping ------------------------------------------------------------------------------------
# GC the daemon's OWN spent worktrees and branches so they do not pile up. Runs BETWEEN sessions.
#
# ⚠️ SCOPE IS DELIBERATELY NARROW: `auto/*` refs only. The owner works in `work/*` worktrees by hand (there
# is a live `work/c24` at /private/tmp/c24 as this is written), and the sibling project's housekeeping was
# widened to every `wt/*` slug — which then made a fully-pushed, fully-clean INTERACTIVE worktree eligible
# for GC between sessions. That is zero data loss but it is a real surprise, and it was only acceptable
# there because its sessions improvised branch slugs. Here the resume prompt mints `auto/<stamp>` every
# time, so a narrow namespace loses nothing and cannot touch the owner's work at all.
#
# Safety is STRUCTURAL, in layers:
#   * NO --force, EVER. A plain `git worktree remove` makes git itself REFUSE any worktree with uncommitted
#     or untracked content, so housekeeping CANNOT destroy in-progress work — not a maintainer's, not a
#     watchdog-killed session's, not a live build's. A dirty worktree is SKIPPED and logged.
#   * MERGED-ONLY: only a ref that is an ANCESTOR of origin/main, so its commits are provably pushed and
#     `branch -D` drops nothing reachable.
#   * PURELY LOCAL: no `git fetch` — the session's push already advanced the origin/main ref this checkout
#     sees — so it can never hang the loop on a dead network.
#   * NEVER the primary checkout; every step best-effort, so a failing git call cannot abort the loop.
housekeeping() {
  cd "$REPO" 2>/dev/null || return 0
  git rev-parse --verify --quiet origin/main >/dev/null 2>&1 || return 0
  git worktree prune 2>/dev/null || true
  local dir ref br removed=0 skipped=0 delbr=0
  while IFS="$(printf '\t')" read -r dir ref; do
    [ -n "$dir" ] || continue
    [ "$dir" = "$REPO" ] && continue
    case "$ref" in refs/heads/auto/*) ;; *) continue ;; esac
    git merge-base --is-ancestor "$ref" origin/main 2>/dev/null || continue
    if git worktree remove "$dir" 2>/dev/null; then removed=$((removed+1)); else skipped=$((skipped+1)); fi
  done < <(git worktree list --porcelain \
             | awk '/^worktree /{w=substr($0,10)} /^branch /{print w"\t"substr($0,8)}')
  git worktree prune 2>/dev/null || true
  # Branch deletion must FOLLOW worktree removal: git refuses to delete a branch still checked out in any
  # worktree, which is also what protects an active one (a dirty one skipped above, the owner's, or a
  # running session's).
  while read -r br; do
    [ -n "$br" ] || continue
    case "$br" in auto/*) ;; *) continue ;; esac
    git merge-base --is-ancestor "$br" origin/main 2>/dev/null || continue
    git branch -D "$br" 2>/dev/null && delbr=$((delbr+1))
  done < <(git for-each-ref --format='%(refname:short)' refs/heads/auto/ 2>/dev/null)
  [ $((removed + delbr)) -gt 0 ] && log "housekeeping: GC'd $removed spent worktree(s), $delbr merged branch(es)"
  # ⛔ "FOR MANUAL REVIEW" WAS A REQUEST NOBODY WAS GOING TO GRANT, AND IT MADE IT 57 TIMES in the log this
  # line is being edited from — against zero parks, so it is by far the most repeated thing this daemon has
  # ever asked a human for. The owner's answer, 2026-08-22: *"I don't really need to review stray worktrees
  # and decide what to do with them."* Nothing about the GC changes — a dirty worktree still cannot be
  # reaped here, and `git worktree remove` refusing it is correct — but the sentence now points at the
  # mechanism that actually resolves it (`report_and_rescue_orphans` snapshots each one and writes a session
  # a task), instead of at a reader who was never going to act. Still a count rather than names: the names
  # are logged once per worktree by the orphan path, and repeating them every cycle is what buried them.
  [ "$skipped" -gt 0 ] && log "housekeeping: left $skipped dirty/in-use worktree(s) in place — snapshotted and assigned to a session, not waiting on the owner"
  # ⛔ AND GC THE ASSIGNMENTS, or the inbox outlives the work and starves the queue. A triage file points at
  # a worktree in /private/tmp, which macOS sweeps for age and clears on reboot — so the directory can
  # vanish under an assignment nobody has picked up yet. Left alone, STEP 1.5 outranks the queue, so every
  # session would open a task naming a path that no longer exists and burn its one item deciding what to do
  # about nothing. The rescue patch is deliberately NOT touched: it is the durable copy and it outliving the
  # worktree is the whole point of writing it.
  local _tf _tw _gcd=0
  for _tf in "$STATE"/triage/*.md "$STATE"/triage/*.escalated; do
    [ -f "$_tf" ] || continue
    _tw="$(awk '/^worktree:/ {print $2; exit}' "$_tf" 2>/dev/null)"
    [ -n "$_tw" ] || continue
    [ -d "$_tw" ] && continue
    rm -f "$_tf" 2>/dev/null && _gcd=$((_gcd + 1))
  done
  [ "$_gcd" -gt 0 ] && log "housekeeping: dropped $_gcd triage assignment(s) whose worktree is gone — /private/tmp was swept; the rescue patch is kept"
  return 0
}

# SOURCE GUARD, placed HERE, above the traps. Everything above is config plus function definitions and is
# safe to source. Everything BELOW has side effects — it installs process traps, scrubs the env, spawns
# caffeinate, and runs the loop that launches `claude -p`. If a maintainer sources this file to inspect
# $DENY/$ALLOW, stop here: do NOT install a `trap 'exit 0'` in their interactive shell or fork a
# budget-spending run. (In the sibling project, sourcing-to-inspect actually spent budget once.)
#
# ⚠️ THAT CLAIM USED TO BE FALSE, AND IT DESTROYED LIVE RUN STATE. The startup counter-clear
# (`rm -f $IDLE_SINCE $NOCOMPLETE gate-timeouts`) and `mkdir -p "$STATE"` both sat ABOVE this guard at module
# scope, so they ran on a SOURCE as well as on a start. Measured 2026-08-16 21:2x: sourcing this file to
# check that the guard worked — with $VISIONOCR_STATE unset, so $STATE defaulted to the REAL
# ~/.local/state/visionocr-autonomous — deleted the live daemon's `idle.since` out from under a session that
# was 70 minutes into its work. The status digest then rendered a bare "Working now" with no elapsed time,
# because the stamp it reads was gone. Nothing else broke, and it could have: $NOCOMPLETE is an attempt cap
# and `gate-timeouts` a park trigger, so the same keystroke silently resets two counters whose whole purpose
# is to stop a runaway. Both are now BELOW the guard. Keep every side effect below this line — the comment
# above is a promise this file has already broken once.
if [ "$_SOURCED" = 1 ]; then
  echo "vision-ocr-autonomous.sh sourced, not executed — config + functions loaded; daemon NOT started." >&2
  return 0 2>/dev/null || exit 0
fi

# ---- STARTUP SIDE EFFECTS — everything from here down runs ONLY on a real start ------------------------
mkdir -p "$STATE"
# Clear ALL THREE counters at every startup so on-disk state shares the daemon's lifetime (BACKOFF is
# in-memory and resets on start; these must too). Otherwise a stale stamp from a PRIOR run makes the FIRST
# cycle park immediately — turning the owner's restart, which is an explicit "try again" signal, into a
# single retry. Starting a run always buys a full window.
#
# ⚠️ `gate-timeouts` WAS MISSING FROM THIS LINE and that was a real bug, caught by tests/prove-daemon.sh
# §[7b]. The gate-timeout streak is exactly the same kind of counter as the other two, but it was declared
# further down with the rest of the gate state (as $GATE_TO) and so was overlooked here. The consequence: a
# run whose gate hangs once and is then stopped — a lid close, `daemon.sh stop`, a bootout — came back with
# the streak at 1, so the FIRST hang of the fresh run parked it while reporting "the health gate TIMED OUT
# 2 cycle(s) in a row". That sentence was false, and a gate timeout is the daemon's own INCONCLUSIVE case,
# so it parked a healthy run on non-evidence. Measured: planted a `1`, and the daemon parked 3 s after
# startup on its first hang.
#
# Spelled as a literal path rather than "$GATE_TO" because that variable is defined further down, next to
# the gate functions that use it; referencing it here would silently expand to "/gate-timeouts" under
# `set -u`'s blind spot for a not-yet-assigned name. Keep the two spellings in step if either ever moves.
#
# ⛔ Do NOT add "$GATE_STATE" ($STATE/last-gate) to this line. That one holds the last GREEN gate's sha and
# is MEANT to outlive the daemon: the gate cadence tracks code churn, not daemon lifetime, so clearing it
# would make every restart re-run a full gate it had already passed.
#
# `$SESSPID` belongs here for a DIFFERENT reason from the counters, and it is worth stating: it is not a
# streak to be forgiven but a stale POINTER. It is removed after every `wait` and by the signal traps, so a
# file surviving into startup means the last daemon was SIGKILLed or OOM-killed — and by now that pid may
# belong to anything. Its readers re-verify before signalling, but a fresh run should not start out holding a
# pid it can no longer vouch for: this daemon's `ppid == $$` test would reject it anyway, and a pointer that
# is guaranteed to fail its own guard is just a thing to misread in `ls $STATE`.
rm -f "$IDLE_SINCE" "$NOCOMPLETE" "$STATE/gate-timeouts" "$ORPHSEEN" "$SESSPID" 2>/dev/null || true

# ---- WHY a daemon used to vanish without a trace -----------------------------------------------------
# Only the NORMAL loop exit logged a "daemon down" line. `trap 'exit 0' TERM INT` exited immediately, so a
# SIGTERM logged NOTHING — and SIGTERM is what launchd sends on bootout, logout and shutdown, i.e. what
# effectively happens when this laptop's lid closes. The daemon just disappeared mid-cycle, which on
# inspection is indistinguishable from a crash. Now every TRAPPABLE exit says why.
#
# HARD LIMIT, and it is itself diagnostic: SIGKILL, an OOM kill and a power cut CANNOT be trapped, so they
# still produce no line. Therefore "daemon up" with NO matching "daemon down" means a hard kill — on a
# personal laptop almost always the lid closing or the battery dying, not a defect.
_DAEMON_STARTED=$SECONDS
_EXIT_REASON="fell out of the main loop (rc 9 — RUN STATUS: COMPLETE, or parked)"
_KILLED_INFLIGHT=""                # set by _terminate_inflight_session so _log_exit can say what it did
_log_exit() {
  local st=$?                      # MUST be the first statement — any command clobbers $?
  local up=$(( SECONDS - _DAEMON_STARTED ))
  local sess="no"
  # ORDER MATTERS: the killed case is checked FIRST, because _terminate_inflight_session REMOVES $LOCK and
  # the `-f` test below would then report "no" over a session this daemon had just torn down — hiding the
  # single most useful fact in the line.
  if [ -n "$_KILLED_INFLIGHT" ]; then sess="$_KILLED_INFLIGHT"
  elif [ -f "$LOCK" ]; then sess="YES (engine.lock present — a resume session was in flight and may leave it stale)"
  fi
  log "=== daemon down (pid $$) — reason: ${_EXIT_REASON} | status=${st} | uptime=${up}s | session-in-flight=${sess} ==="
}

# ⚠️ TEAR THE IN-FLIGHT SESSION DOWN ON A TRAPPABLE EXIT — the whole TREE, not just `claude`.
#
# WHY THIS EXISTS (measured 2026-08-17 07:55): the owner ran `daemon.sh stop` while a session was 22 minutes
# into a scoped mutant campaign. The daemon logged its "daemon down … session-in-flight=YES" line and exited,
# and `claude` died — but the session's own subtree did NOT. Forty minutes later
#   bash ops/autonomous/test-lock.sh run --label mutants-C24-override -- python3 Tools/mutate.py …
#     -> ./run_tests.sh -> ./build/tests
# was still alive at ppid 1, pinning 98% of a core and HOLDING THE SUITE LOCK, with no `git` and no session
# left to read its result. `daemon.sh stop` then reported the lock as "not ours to break".
#
# The old trap body was `exit 0`. It REPORTED the hazard in the down line and did nothing about it, which is
# the shape this project keeps paying for: an instrument that names a problem is not a fix for it.
#
# This is deliberately the DAEMON's trap and not only `daemon.sh stop`'s business, because three of the four
# ways this run ends never go through that script at all — logout, shutdown, and this laptop's lid closing all
# arrive here as a bare SIGTERM from launchd.
#
# HARD LIMIT, unchanged: SIGKILL and an OOM kill cannot be trapped, so they still orphan the tree. That is
# what `daemon.sh stop`'s own sweep is for, and why it does not simply trust this.
_terminate_inflight_session() {
  local cp="" pp="" n=0
  cp="$(cat "$SESSPID" 2>/dev/null)"
  case "$cp" in ''|*[!0-9]*) cp="" ;; esac
  pp="$(ps -o ppid= -p "${cp:-0}" 2>/dev/null | tr -d ' ')"
  # ⚠️ PID-REUSE GUARD: the pid must still be OUR OWN CHILD. The first version of this checked
  # `ps -o comm= -p $cp | grep -q claude` and that was wrong in a way worth recording, because it fails
  # SILENTLY — the worst shape for a guard on a cleanup path. `comm` reports the RESOLVED executable, and
  # $CLAUDE is a symlink to a versioned file whose own name carries no "claude" at all
  # (~/.local/bin/claude -> ~/.local/share/claude/versions/2.1.222). It matches here only because an ancestor
  # DIRECTORY happens to be called `claude`; installed anywhere else, the grep misses, the branch is skipped,
  # and the tree is orphaned exactly as before while the log claims a clean stop.
  # `ppid == $$` needs no such luck: this daemon launched the session as a direct background child, so the
  # test is exact, costs one `ps`, and cannot be fooled by a recycled pid belonging to anything else.
  if [ -n "$cp" ] && [ "$pp" = "$$" ] && kill -0 "$cp" 2>/dev/null \
     && declare -F _terminate_tree >/dev/null 2>&1; then
    n="$(_descendants "$cp" 2>/dev/null | wc -w | tr -d ' ')"
    _terminate_tree "$cp"
    # Clear the engine lock ONLY HERE — inside the branch that proved the dying session was OURS. It is
    # heartbeated by a subshell that dies with this daemon, so leaving it costs the NEXT run up to $STALE
    # (1800s) of "engine busy — skip" cycles: measured after the 07:55 stop, a restart would have idled ~20
    # minutes over a session already dead.
    rm -f "$LOCK" 2>/dev/null || true
    _KILLED_INFLIGHT="YES — TERMed pid $cp and its ${n}-process tree (suite/build/mutate children included), \
engine.lock cleared; a detached KILL backstop follows in 8s"
  else
    # ⛔ AND IT MUST *NOT* BE CLEARED HERE. The first version of this function removed $LOCK unconditionally,
    # "either way", and that was a genuine defect — caught by tests/prove-daemon.sh §[12] rather than by
    # reading, which is the whole argument for the harness. What the log showed:
    #
    #   09:26:48  === daemon up (pid 83707 …) ===          <- a second daemon starts
    #   09:26:48  engine busy (lock 0s old) — skip.        <- correctly defers to the live lock
    #   09:26:49  === daemon down (pid 83428) … SIGTERM …  <- the FIRST daemon's trap finally runs
    #   09:26:49  launching fresh resume session …         <- 83707 now sees NO lock, and launches
    #
    # A dying daemon deleted a LIVE daemon's lock, one second after that daemon had correctly stood down. And
    # engine.lock is not bookkeeping: it is the mutual exclusion BETWEEN daemon instances. Removing another
    # instance's lock permits two concurrent sessions, therefore two concurrent suites — `~/Library/Preferences/
    # tests.plist` is shared, so that is CLAUDE.md's first environment trap and it corrupts BOTH runs into a
    # nearly-green result with unrelated failures. Trading D1's orphan for that would have been a bad trade:
    # an orphan wastes a core and is visible, this manufactures wrong evidence and is not.
    #
    # The ownership test is simply the branch above: this daemon `touch`es $LOCK at launch and removes it after
    # `wait`, so a lock present with no session of OURS behind it belongs to somebody else — or is genuinely
    # stale, in which case `tick`'s existing stale-lock takeover reclaims it after $STALE and no daemon has to
    # guess. Leaving it is the conservative half of both cases.
    if [ -f "$LOCK" ]; then
      _KILLED_INFLIGHT="none of this daemon's (engine.lock present but no session of OURS behind it — LEFT \
ALONE, since it may belong to another live daemon; tick's stale takeover reclaims it if it is truly dead)"
    fi
  fi
  rm -f "$SESSPID" 2>/dev/null || true
  return 0
}
trap _log_exit EXIT
trap '_EXIT_REASON="SIGTERM — launchd bootout/stop, logout, shutdown, or the laptop lid closing"; _terminate_inflight_session; exit 0' TERM
trap '_EXIT_REASON="SIGINT — Ctrl-C / interactive interrupt"; _terminate_inflight_session; exit 0' INT
trap '_EXIT_REASON="SIGHUP — controlling terminal closed / login session ended"; _terminate_inflight_session; exit 0' HUP

# Children must be INDEPENDENT claude sessions, not NESTED. When this daemon is started from an interactive
# Claude session it inherits CLAUDECODE / CLAUDE_CODE_* / CLAUDE_EFFORT etc., and a child `claude -p` would
# refuse to launch ("cannot be launched inside another Claude Code session"). The daemon needs none of them,
# so scrub every CLAUDE* var from this process; children then inherit a clean env.
for _v in $(env | sed -n 's/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$_v"; done

# Keep the machine awake for the daemon's whole lifetime. `-d` (prevent DISPLAY sleep) is essential, not
# just `-i`: even on AC, once the display sleeps macOS drops its "prevent sleep while display is on"
# assertion and the machine darkwakes anyway. In the sibling project that cost a ~5 h overnight stall.
caffeinate -di -w "$$" &

log "=== daemon up (pid $$, interval ${INTERVAL}s, budget \$$BUDGET, gate every ${GATE_EVERY} commits) ==="

# Retire the previous park's Desktop note. A run reaching this line IS the event that retires it: the
# restart it asks for has happened. Without this, `status` goes on telling the owner to restart a daemon
# that is already running, for as long as it takes them to notice and delete the file by hand.
rm -f "$HOME/Desktop/VISION-OCR-RUN-PARKED.txt" 2>/dev/null || true

# ---- Health watchdog helpers -------------------------------------------------------------------------
# Print pid $1 and every descendant. macOS `ps` has no recursive ppid filter, so snapshot the whole
# pid/ppid table once and BFS it. Best-effort: a dead pid just yields nothing.
_descendants() {
  local root="$1" map frontier all next p k kids
  map="$(ps -axo pid=,ppid= 2>/dev/null)"
  frontier="$root"; all="$root"
  while [ -n "$frontier" ]; do
    next=""
    for p in $frontier; do
      kids="$(printf '%s\n' "$map" | awk -v pp="$p" '$2==pp{print $1}')"
      for k in $kids; do
        case " $all " in *" $k "*) ;; *) all="$all $k"; next="$next $k" ;; esac
      done
    done
    frontier="$next"
  done
  printf '%s\n' $all
}

# Kill pid $1 AND its whole descendant tree, so a runaway build/suite child is not orphaned when claude
# dies. Snapshots the tree UP FRONT (once claude dies its children reparent to init and drop off
# _descendants), TERMs all now, and schedules a DETACHED KILL backstop that survives this daemon's own
# cleanup of the watchdog — so there is no race between reaping the watchdog and the KILL landing.
#
# ⚠️ THE DELAYED KILL RE-CHECKS IDENTITY, and it did not used to. The old backstop was
#     ( sleep 8; for p in $victims; do kill -KILL "$p" 2>/dev/null; done ) &
# which signals a snapshot taken BEFORE the TERM, eight seconds earlier, with no check that each pid is still
# the process it was. The TERM itself frees those pids; a machine forking as hard as this one (a suite, a
# build, a harness) can reissue one inside that window, and the victim then takes an uninterruptible SIGKILL
# it has nothing to do with.
# The reason this counts as a defect rather than a worry is that the rest of this file already treats pid
# reuse as real: the `kill -0 "$root"` line below says "never fire on a stale/reused pid" in those words, the
# outer backstop watchdog polls liveness for the same stated reason, and the test harness reaps only pids
# whose command name still matches. One loop was left outside a rule everything else follows.
# It also became far more likely the moment the signal traps started calling this on EVERY stop rather than
# only on a watchdog kill — so it is fixed in the same change (README §Defects D9).
# `ps -o lstart=` is the identity: a pid plus its start time is unique in practice, and a recycled pid gets a
# different one. Cost is one `ps` per victim, paid once.
_terminate_tree() {
  local root="$1" victims p snap=""
  kill -0 "$root" 2>/dev/null || return 0        # never fire on a stale/reused pid
  victims="$(_descendants "$root")"
  for p in $victims; do
    snap="$snap$p $(ps -o lstart= -p "$p" 2>/dev/null | tr -s ' ' | sed 's/^ *//; s/ *$//')
"
  done
  for p in $victims; do kill -TERM "$p" 2>/dev/null; done
  ( sleep 8
    printf '%s' "$snap" | while read -r _vp _vstart; do
      [ -n "$_vp" ] || continue
      _now="$(ps -o lstart= -p "$_vp" 2>/dev/null | tr -s ' ' | sed 's/^ *//; s/ *$//')"
      [ -n "$_now" ] || continue                 # already gone: nothing to kill
      [ "$_now" = "$_vstart" ] || continue       # pid REISSUED since the snapshot — not ours, leave it
      kill -KILL "$_vp" 2>/dev/null
    done ) &
  return 0
}

# Integer sum of %CPU across pid $1's tree. macOS `ps %cpu` is a decaying average over recent real time, so
# a tree quiet for HB_STALL decays toward 0 while a live build/suite stays high.
_tree_cpu() {
  local p cpu total=0
  for p in $(_descendants "$1"); do
    cpu="$(ps -o %cpu= -p "$p" 2>/dev/null | tr -d ' ')"
    case "$cpu" in ''|*[!0-9.]*) continue ;; esac
    total="$(awk -v t="$total" -v c="$cpu" 'BEGIN{printf "%d", t + c}')"
  done
  printf '%s\n' "$total"
}

# Meaningful log bytes = the stream-json log EXCLUDING rate_limit_event lines, so a rate-limit spin (log
# growing with only throttle notices) does NOT register as progress. Anchored to the "type":"…" key rather
# than a bare substring, so a tool_result that merely CONTAINS the text is not dropped.
_meaningful_bytes() { grep -v '"type":"rate_limit_event"' "$1" 2>/dev/null | wc -c | tr -d ' '; }

# True if any DESCENDANT of pid $1 is a `claude` process = a running subagent. A subagent's work does NOT
# stream into the parent's log and may sit at ~0% CPU blocked on the API, so its presence is an independent
# liveness signal.
# ⚠️ Matches a lowercase "/claude" path component (the CLI lives under ~/.local/…/claude). The repo path is
# ~/Claude with a capital C, so built products under it are NOT matched.
_has_claude_descendant() {
  local p comm
  for p in $(_descendants "$1"); do
    [ "$p" = "$1" ] && continue
    comm="$(ps -o comm= -p "$p" 2>/dev/null)"
    case "$comm" in */claude|*/claude/*) return 0 ;; esac
  done
  return 1
}

# Monitor claude pid $1 and TERM/KILL it when the session is wedged or a tool has run away.
#   $1=cpid  $2=stream-json logfile  $3=baseline meaningful-byte count at launch.
health_watchdog() {
  local cpid="$1" logf="$2" last="$3"
  local quiet_since=0 now sz quiet busy idle_streak=0
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  while kill -0 "$cpid" 2>/dev/null; do
    sleep "$HB_POLL"
    sz="$(_meaningful_bytes "$logf")"
    case "$sz" in ''|*[!0-9]*) sz="$last" ;; esac
    if [ "$sz" -gt "$last" ]; then last="$sz"; quiet_since=0; idle_streak=0; continue; fi  # L1: alive
    now="$(date +%s)"
    [ "$quiet_since" = 0 ] && quiet_since="$now"
    quiet=$(( now - quiet_since ))
    [ "$quiet" -lt "$HB_STALL" ] && continue
    # L2 — quiet long enough to judge. Spare the session on EITHER liveness signal.
    if _has_claude_descendant "$cpid"; then idle_streak=0; continue; fi
    busy="$(_tree_cpu "$cpid")"; case "$busy" in ''|*[!0-9]*) busy=0 ;; esac
    if [ "$busy" -gt "$HB_CPU" ]; then
      idle_streak=0
      [ "$quiet" -lt "$HB_HARD" ] && continue    # a legitimate long build/suite/mutation run -> spare it
      printf '%s  %s\n' "$(date '+%F %T')" \
        "watchdog: CPU-busy but no events ${quiet}s (>= HB_HARD ${HB_HARD}s), no subagent — runaway, killing tree of pid $cpid" >> "$LOG"
      _terminate_tree "$cpid"; return 0
    fi
    # ⚠️ QUEUED BEHIND SOMEONE ELSE'S SUITE IS NOT A WEDGE — SPARE IT. This branch used to claim it covered
    # "waiting on the suite lock" with HB_IDLE_N polls, i.e. 60 seconds of tolerance, and that was never
    # true: `test-lock.sh acquire` polls in `sleep 5`, so the tree sits at ~0% CPU with no subagent and no
    # stream events for as long as the wait lasts, and this killed it at HB_STALL + HB_IDLE_N×HB_POLL =
    # 660 s. A single suite is ~40 minutes, so ANY session that queued behind the health gate was killed as
    # wedged while doing exactly what the lock told it to do — and raising the lock wait to 3600 s without
    # this would have made that the normal outcome rather than a rare one.
    #
    # `pgrep -x tests` (never `-f build/tests` — CLAUDE.md's trap) is the right question here because both
    # answers are safe: if the running suite is OUR OWN, the tree is CPU-busy and we never reach this
    # branch at all; if it is someone else's, we are legitimately waiting. So a live suite means "not
    # wedged" either way. This cannot mask a real hang indefinitely — a suite cannot outlive
    # $VISIONOCR_TEST_LOCK_MAXAGE (5400 s), after which the lock breaks and the wait ends, and $MAXRUN
    # remains the outer backstop regardless.
    if pgrep -x tests >/dev/null 2>&1; then
      idle_streak=0
      continue
    fi
    # Idle tree, no subagent, no suite anywhere. Require HB_IDLE_N consecutive idle polls so a brief
    # low-CPU dip (linking, I/O wait) inside a real tool does not false-kill.
    idle_streak=$(( idle_streak + 1 ))
    [ "$idle_streak" -lt "$HB_IDLE_N" ] && continue
    printf '%s  %s\n' "$(date '+%F %T')" \
      "watchdog: session wedged (${quiet}s no events, tree idle ${busy}% CPU, ${idle_streak} idle polls) — killing tree of pid $cpid" >> "$LOG"
    _terminate_tree "$cpid"; return 0
  done
  return 0
}

# ⛔ NAMED AND RESCUED ON EVERY PATH, because "is a worktree holding uncommitted work" is a fact about the
# tree and has NOTHING to do with whether the fingerprint moved. This block used to live inside the
# no-progress branch, which made the rescue reachable only when nothing else had advanced.
#
# Measured 2026-08-20: the OWNER landed a docs commit at 14:40 while a session ran 14:29-16:36. The
# fingerprint moved — correctly, per work_fingerprint()'s own note that an outside push means "the decision
# surface moved, retry NOW" — so tick() took the progress branch, logged "committed but no item completed",
# and skipped BOTH the orphan naming and the snapshot over 481 uncommitted insertions across 9 files,
# including Sources/Flattener.swift and Tests/main.swift. $STATE/rescue held nothing for it and the only
# copy was in /private/tmp; the owner wrote the patch by hand. The next session did recover the work, but
# only because it read the SESSION LOG entry claiming "pushed" and checked it — which is luck, not a net.
#
# ⚠️ THE OLD REGRESSION TEST DID NOT CATCH THIS AND COULD NOT HAVE. prove-daemon.sh [17] drives the daemon
# with "0:no" — a session that moves nothing — so it exercised the rescue from the only branch that could
# reach it. It proved the rescue WORKS, never that it RUNS. [18] is the missing half: idle first so the
# backoff rises, THEN create the orphan, THEN commit, so a patch can only have come from a progress cycle.
#
# One value was answering two questions. It still answers the retry one; this function answers the other.
# $1 is the lead-in, so the log still reads as prose on both paths without the caller re-deriving anything.
report_and_rescue_orphans() {   # $1 = lead-in phrase; returns 0 if any orphan was found and reported
  local _orph _d _rescue _rb _ridx _tmp _complete _ahead _un _triage _assign
  _orph="$(orphaned_work)" || return 1

  # ⚠️ DO NOT BLAME THIS SESSION, AND DO NOT REPEAT IT EVERY CYCLE. A dirty `auto/*` worktree is
  # PERMANENT until a human clears it: housekeeping only removes worktrees whose branch is an ancestor
  # of origin/main, and `git worktree remove` refuses a dirty one regardless. So the obvious phrasing —
  # "session (rc=…) left UNCOMMITTED WORK" every no-progress cycle — would pin a week-old orphan on a
  # session that never created a worktree, and would repeat it until the log held nothing else. Both are
  # the failure this whole change is about: a true sentence that reads as something it is not. So name
  # the WORKTREE, not the session, and say each one once per daemon lifetime.
  log "$1 a worktree is holding UNCOMMITTED WORK — this is NOT an empty queue."
  for _d in $_orph; do
    grep -qxF "$_d" "$ORPHSEEN" 2>/dev/null && continue
    printf '%s\n' "$_d" >> "$ORPHSEEN" 2>/dev/null || true
    log "  orphaned: $_d —$(orphaned_work_summary "$_d")"
  done
  # ⚠️ AND THE PATCH IS SAVED, because the sentence this used to end on was optimistic. It read
  # "nothing is lost until that worktree is removed" — true of `git worktree remove`, and NOT true of the
  # directory those worktrees live in. Every session works in `/private/tmp/vo-<stamp>`, and /private/tmp
  # is cleared by macOS on reboot and swept for age while running. So the daemon's own answer to "is this
  # work safe?" rested on a volatile filesystem, and the ONLY copy of a killed session's work sat there.
  #
  # Measured 2026-08-17: `/private/tmp/vo-20260817-072554-25857` held 114 uncommitted insertions across 7
  # files — a session's discovery of an ELEVENTH check that could not fail in the commit that had landed
  # 45 minutes earlier, plus the new mutant that catches it and a published figure corrected from a flat
  # "1,961 at every resolution" to 1,960-1,962. A reboot would have taken all of it, and the register
  # would have kept the check that cannot fail.
  #
  # A patch, not a copy: it is a few KB against a worktree's hundreds of MB (each carries its own build/),
  # it diffs against a sha that IS pushed, and `git apply` restores it anywhere. Cheap enough to do on
  # every newly-seen orphan without a size guard, and $ORPHSEEN already makes that once per worktree per
  # daemon lifetime. Best-effort throughout: a failure here must never affect the run's verdict.
  # ⛔ THE SNAPSHOT HAS TO SEE UNTRACKED FILES, AND IT MUST NEVER SAVE LESS THAN THE OLD ONE DID. Those are
  # two requirements and the first version of this fix met only the first, which is the more embarrassing
  # half of the story.
  #
  # The bug it fixes: `git diff HEAD` cannot see an UNTRACKED file, so a worktree holding five modified files
  # and one new one produced a patch with five in it, exit 0, and a cheerful "rescued: … bytes" line — while
  # the guard that exists for this tests whether the patch is EMPTY, not whether it is COMPLETE, so it never
  # ran. Measured 2026-08-22 on `vo-20260822-014509-85956`: the saved patch is **90,263 B holding 5 tracked
  # files**, and `WIDEN-2026-08-22.tsv` — 10,465 B of measurement, the only copy in existence — was named in
  # the `.status` written beside it and in no patch. The two files this loop writes disagreed and the log
  # sided with the wrong one. (An earlier draft of this comment said "87,402 B"; that is a DIFFERENT
  # worktree's patch, with 7 files in it. Pairing one strand's file count with another's byte count is
  # exactly the kind of number this project keeps having to retract, and it was caught in review.)
  #
  # `GIT_INDEX_FILE=<throwaway> git add -A` then `diff --cached --binary HEAD` sees everything, in pure git:
  # the worktree's REAL index is untouched (verified — a `??` entry is still `??` afterwards), `add -A`
  # honours `.gitignore` so `build/` stays out and this stays a patch rather than a copy, and `--binary`
  # means a dumped PNG survives the round trip. Measured on that worktree: 6 files, 100,934 B.
  #
  # ⛔ BUT `add -A` IS ALL-OR-NOTHING AND THE OLD COMMAND WAS NOT, so on its own it is a REGRESSION on the
  # one function whose entire job is never to lose work. Measured: a worktree with real work in a modified
  # tracked file plus ONE unreadable untracked file (`chmod 000`) gives `add -A` **rc=128** — "unable to
  # index file" — the `&&` chain aborts, the else branch deletes the patch, and NOTHING is saved, where
  # `git diff HEAD` still produced a 118-byte patch containing the work. An unreadable directory is only a
  # warning; an unreadable file is fatal. So the complete form is TRIED FIRST and the old form is the
  # FALLBACK, and a fallback snapshot says so and names what it could not hold. Strictly better than either.
  _rescue="$STATE/rescue"
  mkdir -p "$_rescue" 2>/dev/null || true
  for _d in $_orph; do
    _rb="$(basename "$_d")"
    # ⛔ THE SKIP IS KEYED ON THE `.complete` MARKER, NOT ON THE PATCH EXISTING. "First snapshot wins; never
    # overwrite a saved rescue" is right, and keying it on the patch meant every PARTIAL patch already on
    # disk stayed partial forever — including the live one above, which this daemon would otherwise skip
    # while writing a triage task pointing at it, so a session would be told a durable copy existed and
    # granted `--force` against it. An old partial is preserved as `.patch.partial` rather than clobbered.
    [ -f "$_rescue/$_rb.complete" ] && continue
    _ridx="$STATE/.rescue-index.$$"
    rm -f "$_ridx" "$_ridx.lock" 2>/dev/null || true
    _tmp="$_rescue/.$_rb.new"
    _complete=0
    if GIT_INDEX_FILE="$_ridx" git -C "$_d" read-tree HEAD 2>/dev/null \
       && GIT_INDEX_FILE="$_ridx" git -C "$_d" add -A 2>/dev/null \
       && GIT_INDEX_FILE="$_ridx" git -C "$_d" diff --cached --binary HEAD > "$_tmp" 2>/dev/null \
       && [ -s "$_tmp" ]; then
      _complete=1
    elif git -C "$_d" diff --binary HEAD > "$_tmp" 2>/dev/null && [ -s "$_tmp" ]; then
      _complete=0
    else
      rm -f "$_tmp" "$_ridx" "$_ridx.lock" 2>/dev/null || true
      log "  ⚠️ could NOT snapshot $_d at all — neither a scratch-index 'add -A' nor 'git diff HEAD' produced anything. Copy it by hand; this is the case where /private/tmp is the only copy."
      continue
    fi
    rm -f "$_ridx" "$_ridx.lock" 2>/dev/null || true
    [ -f "$_rescue/$_rb.patch" ] && mv "$_rescue/$_rb.patch" "$_rescue/$_rb.patch.partial" 2>/dev/null
    mv "$_tmp" "$_rescue/$_rb.patch" 2>/dev/null || true
    git -C "$_d" log -1 --format='%H %s' > "$_rescue/$_rb.base"   2>/dev/null || true
    git -C "$_d" status --porcelain      > "$_rescue/$_rb.status" 2>/dev/null || true
    # ⛔ UNPUSHED COMMITS ARE NOT IN THAT PATCH AT ALL, and a session is about to be offered `--force`.
    # `diff --cached HEAD` is relative to the branch TIP, so a strand with commits on it has those commits
    # in neither the patch nor the base file — and `git branch -D` makes them unreachable. `housekeeping()`
    # guards precisely this with an ancestor-of-origin/main test; the triage carve-out needs its own copy.
    _ahead="$(git -C "$_d" rev-list --count origin/main..HEAD 2>/dev/null || echo 0)"
    case "$_ahead" in ''|*[!0-9]*) _ahead=0 ;; esac
    if [ "$_ahead" -gt 0 ]; then
      git -C "$_d" format-patch --stdout origin/main..HEAD > "$_rescue/$_rb.commits.patch" 2>/dev/null || true
      log "  rescued $_ahead unpushed commit(s) to $_rescue/$_rb.commits.patch — the working-tree patch does NOT contain them."
    fi
    if [ "$_complete" = 1 ]; then
      : > "$_rescue/$_rb.complete"
      log "  rescued: $_rescue/$_rb.patch ($(wc -c < "$_rescue/$_rb.patch" | tr -d ' ') bytes, COMPLETE — tracked and untracked) — /private/tmp does not survive a reboot; this does."
    else
      # The fallback's gap is exactly one thing and git will name it exactly, so do not re-derive it by
      # parsing the patch. An earlier version compared `.status` against the patch's own diff headers with
      # awk, and review measured FOUR false-positive classes it got wrong — a pure rename, a mode-only
      # change, a path with a space (git appends a TAB to the `+++` line), and a UTF-8 path (git quotes the
      # whole `"b/…"` operand). `ls-files --others --exclude-standard` is git answering the actual question.
      _un="$(git -C "$_d" ls-files --others --exclude-standard 2>/dev/null | tr '\n' ' ')"
      log "  ⚠️ PARTIAL rescue: $_rescue/$_rb.patch ($(wc -c < "$_rescue/$_rb.patch" | tr -d ' ') bytes) holds TRACKED changes only — 'add -A' failed, so UNTRACKED content is NOT in it: ${_un:-(none)} — copy that by hand NOW."
    fi
  done
  # ---- ASSIGN IT, DO NOT ESCALATE IT ---------------------------------------------------------------
  # ⛔ THIS IS THE POINT OF THE WHOLE FUNCTION AND IT USED TO BE MISSING. Everything above makes the work
  # SAFE; none of it makes the work MOVE. A dirty `auto/*` worktree is permanent — `housekeeping()` only
  # reaps a worktree whose branch is an ancestor of origin/main AND that `git worktree remove` accepts, so a
  # dirty one is skipped forever and logged "left N … for manual review". The owner's verdict on that,
  # 2026-08-22: *"I don't really need to review stray worktrees and decide what to do with them… I'd rather
  # the daemon just decide and execute much of this work."*
  #
  # ⚠️ BUT THE DECISION ITSELF IS NOT MECHANISABLE IN SHELL, and pretending otherwise is how work gets
  # destroyed. Twice now a strand was superseded by a later commit that redid it UNDER A DIFFERENT
  # FILENAME — `MRC_BG=` → `PHOTODETAIL=` (69ebf0e), `estimate-corpus-rate.py` + `SHRINKCOST-*.tsv` →
  # `stratify-corpus.py` + `SHAPETERM-BYTES-*.tsv` (ef9786c) — so no path or name comparison finds it; both
  # were established by reading two tool headers for the same purpose and diffing TSV columns. And in the
  # same sweep a third strand that LOOKED superseded by the same reasoning was not: it held
  # `Flattener.textRegionWideningOverride` plus 112 lines of tests that `git grep` finds nowhere on
  # origin/main, because the commit that appeared to replace it had landed only the tool half.
  #
  # So the daemon does not judge. It ASSIGNS — a session is an LLM and can do exactly that reading. This
  # turns a thing waiting on a human into a thing waiting on the next session, which is the whole ask.
  #
  # ⚠️ AND THE INBOX IS OUTSIDE THE REPO, deliberately. The obvious channel is a `QUEUE.md` box, and it is
  # wrong twice: the daemon would dirty the PRIMARY checkout, and with `rebase.autoStash` unset (verified
  # 2026-08-22) the next session's STEP 1 `git pull --rebase origin main` then FAILS outright; and an
  # appended box walks straight into the greedy-span trap QUEUE.md's own header documents. A file under
  # $STATE touches no tracked path and cannot conflict with anything.
  #
  # Write-once, keyed on the file rather than on $ORPHSEEN: startup does `rm -f $ORPHSEEN`, so keying it
  # there would re-write — and possibly clobber — an assignment a session is part-way through.
  #
  # ⚠️ NEVER ASSIGN A WORKTREE A LIVE SESSION IS USING. Both call sites (tick(), ~1351 and ~1369) run after
  # `wait` returns, so today $SESSPID is already gone and this guard is a no-op — it is here because
  # `orphaned_work` now counts UNTRACKED files, which makes a mid-run session's scratch `.tsv` enough to
  # look like a strand, and a third call site added later would otherwise hand a session its own worktree
  # to triage. Rescuing a live session's work is fine and stays ungated; ASSIGNING it is not.
  _triage="$STATE/triage"
  mkdir -p "$_triage" 2>/dev/null || true
  _assign=1
  if [ -f "$SESSPID" ] && kill -0 "$(cat "$SESSPID" 2>/dev/null || echo 0)" 2>/dev/null; then
    _assign=0
    log "  a session is live — snapshotted, but NOT assigning triage while it runs."
  fi
  for _d in $_orph; do
    [ "$_assign" = 1 ] || break
    _rb="$(basename "$_d")"
    # ⛔ `.escalated` COUNTS AS ASSIGNED. Deleting the file has to mean "resolved", and step 5 of the
    # template — escalate to ## NEEDS OWNER and leave the worktree alone — is also a way to be "done". If
    # both used deletion, the daemon would re-assign next cycle, every following session would spend its one
    # item on the same unresolvable strand, and each would append another duplicate outbox entry. So an
    # escalation RENAMES rather than deletes, and this guard honours both names.
    { [ -f "$_triage/$_rb.md" ] || [ -f "$_triage/$_rb.escalated" ]; } && continue
    {
      printf 'TRIAGE — stranded worktree %s\n' "$_rb"
      printf 'assigned by the daemon at %s. Remove this file when the strand is resolved.\n\n' "$(date '+%F %T')"
      printf 'worktree:  %s   (in /private/tmp — VOLATILE, swept by macOS)\n' "$_d"
      printf 'branch:    %s\n' "$(git -C "$_d" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
      printf 'base:      %s\n' "$(cat "$_rescue/$_rb.base" 2>/dev/null || echo '?')"
      # ⛔ THE ASSIGNMENT MUST STATE WHETHER THE BACKUP IS WHOLE, because the next thing it does is grant
      # `--force`. Naming a path unconditionally — including for a strand whose snapshot just failed and
      # whose patch was never written — tells a session a durable copy exists when it may not, and gives it
      # no way to tell a COMPLETE patch from a TRACKED-ONLY one. Both facts are on disk; print them.
      if [ -f "$_rescue/$_rb.complete" ]; then
        printf 'rescue:    %s  (COMPLETE — tracked and untracked)\n' "$_rescue/$_rb.patch"
      elif [ -f "$_rescue/$_rb.patch" ]; then
        printf 'rescue:    %s\n' "$_rescue/$_rb.patch"
        printf '  ⛔ PARTIAL — TRACKED CHANGES ONLY. Untracked content is NOT in it:\n'
        printf '     %s\n' "$(git -C "$_d" ls-files --others --exclude-standard 2>/dev/null | tr '\n' ' ')"
        printf '     Copy those out BEFORE you remove anything. Do NOT force-remove on this patch alone.\n'
      else
        printf '  ⛔ NO RESCUE PATCH EXISTS for this worktree — the snapshot failed. /private/tmp is the\n'
        printf '     ONLY copy of this work. Do NOT remove the worktree under any circumstances; copy it out.\n'
      fi
      _ahead="$(git -C "$_d" rev-list --count origin/main..HEAD 2>/dev/null || echo '?')"
      printf 'unpushed commits on its branch: %s\n' "$_ahead"
      case "$_ahead" in
        0|'') : ;;
        *) printf '  ⛔ THOSE COMMITS ARE NOT IN THE WORKING-TREE PATCH (it is a diff against the branch TIP).\n'
           printf '     %s holds them. `git branch -D` makes them unreachable — so a strand that is\n' "$_rescue/$_rb.commits.patch"
           printf '     ahead of origin/main MAY NOT be force-removed on a files-only comparison, however\n'
           printf '     superseded its dirty files look. Land them, or leave the branch alone.\n' ;;
      esac
      printf '\n'
      printf 'dirty paths:\n'
      sed 's/^/  /' "$_rescue/$_rb.status" 2>/dev/null || printf '  (none recorded)\n'
      cat <<'EOP'

YOUR JOB — decide and EXECUTE. Do not hand this back to the owner.

1. Is it SUPERSEDED? Compare by CONTENT, never by filename — twice a strand was redone under a
   different name. For each file: read the strand's version and ask what QUESTION it answers, then
   `git grep` / `git log --oneline -20 --` on main for a file answering the SAME question. For a tool,
   compare the two headers. For a TSV, compare the column list and `diff <(cut -f1-N …) <(cut -f1-N …)`
   over the data rows. For code, `git grep` the new symbols on origin/main — if a symbol is absent, that
   half did NOT land, whatever the commit subject suggests.
2. If SUPERSEDED: say so in the SESSION LOG with the evidence (which commit, which columns matched),
   `mv` the rescue trio to `SUPERSEDED-by-<sha>-<name>.{patch,base,status}.bak`, then
   `git worktree remove --force <worktree>` and `git branch -D <branch>`.
   ⚠️ `--force` is normally forbidden here and this is the ONE case that earns it. THREE preconditions,
   all of them, or do not force: (a) the content is provably already on main, by content and not by
   filename; (b) the rescue patch says COMPLETE above — a PARTIAL one does not back what you are about to
   delete; (c) `git rev-list --count origin/main..<branch>` is **0**. A branch that is ahead has commits
   in NO patch this loop wrote, and `branch -D` makes them unreachable. Cite all three in the log.
3. If it holds UNIQUE work: adopt it. Rebase onto main, resolve conflicts KEEPING BOTH SIDES where the
   two are different measurements, run the suite through `test-lock.sh`, commit, push. That is a normal
   item and may be the whole session.
4. If it is TRIVIAL (docs already landed, an empty file, a stray build artefact): remove it as in 2 and
   log one line.
5. If — and only if — deciding needs a judgement the owner has reserved (a new seam in `Sources/`,
   a release, anything touching `testdocs/`), append ONE entry to `## NEEDS OWNER` naming the decision,
   leave the worktree alone, and `mv` this file to `<same-name>.escalated`. ⛔ Do NOT delete it: deletion
   means RESOLVED, and the daemon re-assigns anything with neither name — which would make every later
   session spend its one item re-deciding this and append a duplicate outbox entry each time.
   That branch is the escape hatch, not the default.

Then delete this file (or rename it per step 5). An unresolved assignment is what keeps the strand visible.
⚠️ If the worktree named above no longer EXISTS, /private/tmp was swept. Say so in the SESSION LOG, note
whether a rescue patch survives, and delete this file — there is nothing left to triage.
EOP
    } > "$_triage/$_rb.md" 2>/dev/null || true
    log "  assigned: $_triage/$_rb.md — a session triages this; it is NOT waiting on the owner."
  done
  log "  a later session can finish it, or rescue it by hand. The committed base plus \$STATE/rescue/*.patch"
  log "  is the durable copy; the worktree itself is in /private/tmp and is NOT."
  return 0
}

tick() {
  # 1. Done? unload + stop.
  if grep -q '^RUN STATUS: COMPLETE' "$RUN" 2>/dev/null; then
    log "RUN STATUS: COMPLETE — daemon stopping."
    launchctl bootout "gui/$(id -u)/$JOB" 2>/dev/null || true
    return 9
  fi
  # 2. No run-state file? don't run blind.
  [ -f "$RUN" ] || { log "no run-state file at $RUN — skip."; return 0; }
  # 3. Another engine active? (lock fresh) skip this cycle.
  if [ -f "$LOCK" ]; then
    local age; age=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) ))
    if [ "$age" -lt "$STALE" ]; then log "engine busy (lock ${age}s old) — skip."; return 0; fi
    log "stale lock (${age}s) — taking over."
    # ⚠️ REMOVE it rather than letting the launcher `touch` it back to life. `touch` on an existing file
    # PRESERVES birthtime on APFS (measured), and status-digest.sh reads that birthtime to say how long the
    # current session has been running. Without this the digest inherits the DEAD session's start time and
    # reports "Working now — 3 hours into this session" about a session one minute old — misreporting a
    # fresh run as a stuck one, in the takeover path, which is precisely when the owner is reading it.
    rm -f "$LOCK" 2>/dev/null || true
  fi

  # 3b. Disk guard. AFTER the engine-busy check ON PURPOSE, not for tidiness: disk_ok() calls housekeeping()
  #     to reclaim, and housekeeping's whole safety argument rests on running BETWEEN sessions with none
  #     active. Checking earlier would let this engine GC another live engine's worktree mid-build — and a
  #     plain `git worktree remove` does NOT refuse a worktree whose only content is gitignored, which is
  #     exactly what `build/` is. Still before the launch, so we never start a session we know cannot build.
  if ! disk_ok; then
    park_run "low disk (${LAST_FREE_MB}MB free)" \
      "Vision OCR autonomous run PARKED — LOW DISK: only ${LAST_FREE_MB}MB free on the repo volume (need
${MINFREE_MB}MB). Every build would fail, so the run stopped rather than burning sessions. The usual
culprits are per-worktree build/ directories and Tools/mutation-out/. Free some space, then restart:
./ops/autonomous/daemon.sh start"
    return 9
  fi

  # 3c. Health gate, when due. Placed here for the same reason as the disk guard: it runs synchronously and
  #     must be the sole active engine. RED -> park. GREEN -> it WAS this cycle's work, so mark progress (so
  #     the idle backoff does not count the gate cycle as idle) and end the cycle. Not due -> fall through.
  health_gate; local hg=$?
  [ "$hg" = 9 ] && return 9
  if [ "$hg" = 10 ]; then note_progress; return 0; fi

  # 3d. Snapshot the decision surface BEFORE the session, so afterwards we can tell whether it actually
  #     advanced the run. Also snapshot the completed-item count, to tell a checkpoint from a completion.
  local fp_before cc_before; fp_before="$(work_fingerprint)"; cc_before="$(completed_items)"

  # 4. Acquire the lock + heartbeat it for the child's lifetime, so overlapping cycles skip.
  touch "$LOCK"
  local ppid=$$
  ( while kill -0 "$ppid" 2>/dev/null; do touch "$LOCK" 2>/dev/null; sleep 60; done ) &
  local hb=$!

  # 5. Optional per-project env hook into the child env, without ever printing it.
  set -a; [ -f "$STATE/env" ] && . "$STATE/env"; set +a
  # Defence in depth: alert config belongs in $STATE/alert.env, but if an operator puts ALERT_* in
  # $STATE/env by mistake, the `set -a` above just marked them for export and the session would inherit the
  # alert credential. Strip the export attribute only — notify() (this shell) keeps the value.
  export -n ALERT_URL ALERT_AUTH 2>/dev/null || true
  # The session's "you are unattended" marker, exported LAST so an operator edit to $STATE/env cannot unset
  # it. The owner's interactive sessions never set it, so their own host GUI work stays available.
  export VISIONOCR_UNATTENDED=1
  # Point the session's suite lock at the same place the gate uses, so the pre-commit hook it triggers
  # serialises against everything else.
  export VISIONOCR_TEST_LOCK="${VISIONOCR_TEST_LOCK:-$STATE/test.lock}"
  # And re-assert PATH for the child. `claude -p` inherits this process's env, and a session that shells out
  # to swiftc/jbig2/qpdf through a PATH-less launchd environment gets the silent-failure trap CLAUDE.md warns
  # about — reported as bogus results rather than as an error.
  export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

  log "launching fresh resume session (backstop ${MAXRUN}s, budget \$$BUDGET, health-wd on)…"
  cd "$REPO" || { log "cannot cd $REPO — skip."; kill "$hb" 2>/dev/null; rm -f "$LOCK"; return 0; }
  # Fresh per-session log (keep one previous). stream-json is larger than text, so don't append forever; a
  # fresh file also gives the watchdog a clean zero baseline.
  local SLOG="$STATE/last-session.log"
  [ -f "$SLOG" ] && mv -f "$SLOG" "$SLOG.prev" 2>/dev/null; : > "$SLOG"
  # Run claude in the background so the watchdogs can TERM/KILL it (macOS has no `timeout`). $cpid is
  # claude's own pid. MODEL IS DELIBERATELY FIXED (opus, sonnet only as the overload fallback) and not
  # chosen per item: the flag resolves before the session knows which item it will pick. Per-task tuning
  # lives one level down, in the session's SUBAGENTS — see the resume prompt's closing block.
  "$CLAUDE" -p "$(cat "$PROMPT")" \
      --permission-mode default \
      --model opus --fallback-model sonnet \
      --effort "$EFFORT" \
      --max-budget-usd "$BUDGET" \
      --output-format stream-json --verbose --include-partial-messages \
      --allowedTools "${ALLOW[@]}" \
      --disallowedTools "${DENY[@]}" \
      >> "$SLOG" 2>&1 &
  local cpid=$!
  # Publish the session pid for the two readers that cannot see this local: this daemon's signal traps, and
  # `daemon.sh stop` in another process. Written BEFORE the watchdogs so a TERM arriving in the next
  # microsecond still finds it. Removed after `wait` below, and by the traps themselves.
  printf '%s' "$cpid" > "$SESSPID" 2>/dev/null || true
  # Start stamp, used ONLY to tell a usage-limit fast-fail apart from a genuine no-op in the verdict below.
  # Bash's SECONDS builtin, NOT $(date +%s): a fork+exec here lands in the window a TERM-right-after-launch
  # test races, and a builtin costs nothing and cannot perturb timing.
  local _t0=$SECONDS
  # Watchdog A — OUTER wall-clock backstop. POLLS cpid liveness rather than one long unconditional sleep, so
  # it self-exits promptly when the session ends AND never fires _terminate_tree against a stale/reused pid
  # if the daemon dies uncleanly.
  ( waited=0
    while [ "$waited" -lt "$MAXRUN" ]; do
      kill -0 "$cpid" 2>/dev/null || exit 0
      sleep "$HB_POLL"; waited=$(( waited + HB_POLL ))
    done
    _terminate_tree "$cpid" ) &
  local wpid=$!
  # Watchdog C — health (Layers 1+2). PRIMARY killer for wedged/runaway sessions. Baseline 0 (fresh log).
  # (No separate usage-limit watchdog: the CLI fast-fails an exhausted limit itself, rc=1 in ~2 s, and a
  # rate-limit WAIT is caught by L1 whose heartbeat filters rate_limit_event bytes. A text-scraping usage
  # grep was deliberately not ported — it cannot see stream-json's structured event and would false-kill a
  # session that merely READS a file mentioning the limit phrase, this daemon being one such file.)
  health_watchdog "$cpid" "$SLOG" 0 &
  local cwpid=$!
  wait "$cpid"; local rc=$?
  rm -f "$SESSPID" 2>/dev/null || true   # the session is reaped; the pointer must not outlive it (pid reuse)
  kill "$wpid" "$cwpid" 2>/dev/null; wait "$wpid" "$cwpid" 2>/dev/null
  log "resume session exited rc=$rc"
  # Best-effort readable mirror of the final result (jq present -> extract; else skip).
  if command -v jq >/dev/null 2>&1; then
    jq -rc 'select(.type=="result") | (.result // .error // empty)' "$SLOG" 2>/dev/null \
      | tail -1 > "$STATE/last-session.txt" 2>/dev/null || true
  fi

  # Progress verdict — DERIVED, not self-reported. Deliberately NOT gated on rc==0: a session that ships a
  # commit and is THEN killed (budget cap / watchdog) still advanced the run and must reset the backoff;
  # gating on rc==0 would let a run that keeps committing-then-dying march to a false park. The failure side
  # needs no rc check either: a usage-limit fast-fail cannot move the fingerprint, so it lands in the else.
  # Evaluated HERE — before housekeeping and the compactor — so neither is mistaken for the run advancing.
  local fp_after cc_after; fp_after="$(work_fingerprint)"; cc_after="$(completed_items)"
  local verdict=0
  if [ -n "$fp_after" ] && [ "$fp_after" != "$fp_before" ]; then
    note_progress
    note_committed "$cc_before" "$cc_after" || verdict=9
    # The verdict above is about the RUN advancing. This is about the TREE, and a moved tip does not mean
    # nothing was stranded — an owner commit, or another session's push, moves the fingerprint too.
    report_and_rescue_orphans "the tip moved, but" || true
  else
    # NAME THE CAUSE. A usage-limit fast-fail is NOT an empty queue: the CLI exits nonzero in ~2-3 s when
    # the window is exhausted and cannot move the fingerprint, so it lands here looking identical to "there
    # was nothing to do". Reading that as an idle queue is the misreport run-state-lib.sh exists to undo one
    # level up; this is the log line it leaves behind.
    local _elapsed=$(( SECONDS - _t0 )) _orph _d
    if [ "$rc" -ne 0 ] && [ "$_elapsed" -lt 10 ]; then
      log "session (rc=$rc) exited after ${_elapsed}s — likely USAGE-LIMIT fast-fail, not an empty queue; backing off."
    # ⚠️ "ADVANCED NOTHING" AND "LOST ITS COMMIT" ARE NOT THE SAME EVENT, and the fingerprint cannot tell
    # them apart — it is derived from the tip and the queue, and neither moves in either case. Measured
    # 2026-08-16: a 95-minute session went green 1137/1137, backgrounded `git commit`, ended its turn, and
    # the hook died mid-suite at `Terminated: 15`. This logged "advanced nothing (queue + tip unchanged) —
    # no progress", which was true and read as "the queue is drained" — while 660 insertions across 8 files
    # sat staged in that session's worktree (/private/tmp/vo-20260816-184311-95643), and the NEXT session
    # redid all of it from scratch. Naming it
    # costs one `git status` per worktree and is the difference between the owner rescuing the work and
    # never learning it existed. Checked BEFORE housekeeping, which is what would otherwise GC the evidence.
    elif report_and_rescue_orphans "no progress, and"; then
      :   # the function did the logging; this branch exists only to claim the verdict
    else
      log "session (rc=$rc) advanced nothing (queue + tip unchanged) — no progress."
    fi
    note_no_progress || verdict=9
  fi

  kill "$hb" 2>/dev/null || true
  rm -f "$LOCK" 2>/dev/null || true
  housekeeping   # GC this (and any prior) session's spent worktree/branch. Only after a real run.
  # Keep $RUN's SESSION LOG bounded, so the file a fresh session reads to orient does not inflate its
  # startup cost without limit. Runs HERE — between cycles, lock released, NO session active — so it can
  # never race a session's append.
  #
  # ⚠️ A FAILURE HERE MUST NOT BREAK THE LOOP, but it must no longer be INVISIBLE, which is what a bare
  # `|| true` made it. In the sibling project the compactor aborted on EVERY cycle for weeks; because the
  # error was swallowed here and the script always exited 0, nothing noticed, the plan drifted to 96% of its
  # budget, and the run eventually parked pointing at a different file. So: it exits nonzero ONLY when a
  # pass truly aborted (a legitimate no-op is still 0), and this logs a loud, greppable line.
  if [ -x "$COMPACTOR" ]; then
    if "$COMPACTOR" "$RUN" >> "$LOG" 2>&1; then :; else
      log "⚠⚠ compact-runlog ABORTED (rc=$?) — $RUN is NOT being kept bounded. Detail just above in this log."
    fi
  fi
  # Refresh the digest at the cycle tail, EXCEPT when the cycle parked: park_run already wrote a PARKED
  # digest, and an unflagged write here would clobber it back to "running".
  [ "$verdict" = 9 ] || write_status
  return "$verdict"
}

# The gap is $BACKOFF, not a flat $INTERVAL: it IS $INTERVAL while the run is productive, doubles toward
# $MAXBACKOFF once cycles stop advancing anything, and is cut short the moment the decision surface changes.
# rc 9 = terminal (COMPLETE, or parked) -> fall out of the loop and let the EXIT trap log the reason.
while true; do
  tick; rc=$?
  [ "$rc" = "9" ] && break
  backoff_sleep
done
# NOTE: no log line here on purpose — the EXIT trap is the SINGLE place that logs "daemon down", so every
# path (normal rc-9 exit, SIGTERM/INT/HUP) produces exactly one line, with a reason. Logging here too would
# double-log the normal path and still miss the signal paths.
