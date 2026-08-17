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
COMPACTOR="${VISIONOCR_COMPACTOR:-$HOME/.local/bin/compact-runlog.sh}"
JOB="com.${LABEL}.autonomous"

# ⚠️ EVERY TIMING CONSTANT IN THIS BLOCK WAS SIZED AGAINST A "3-6 MIN" SUITE THAT NOBODY HAD TIMED. Timed on
# 2026-08-16, the same suite ran 80-632 s on a quiet machine and ~37-40 min with other work alongside, and
# the health gate that wraps it measured 44m53s. There is no single correct number here: this is a personal
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
MAXRUN="${VISIONOCR_MAXRUN:-9000}"        # OUTER wall-clock backstop (2.5 h). The health watchdog below is
                                          # the PRIMARY killer; this only fires if that fails or a session is
                                          # productive-but-endless.
BUDGET="${VISIONOCR_BUDGET:-20}"          # --max-budget-usd per resume session
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
GATE_MAXRUN="${VISIONOCR_GATE_MAXRUN:-9000}"   # 2.5 h = one full gate (~45 min) + a full lock wait (60 min)
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
# comment gave. It said "the full catalogue is ~70 min", which was arithmetic on a 2-4 min suite; the suite
# is 39m30s and `Tools/mutate.py` runs the WHOLE of it per mutant over 84 mutants, so the full catalogue is
# on the order of 55 HOURS and no watchdog setting makes it survivable — the resume prompt forbids it
# outright instead. The real case this must not kill is the ordinary one: a session sitting inside its own
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
work_fingerprint() {
  {
    git -C "$REPO" rev-parse HEAD 2>/dev/null || echo no-head
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
  [ "$skipped" -gt 0 ] && log "housekeeping: left $skipped merged-but-dirty/in-use worktree(s) for manual review"
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
rm -f "$IDLE_SINCE" "$NOCOMPLETE" "$STATE/gate-timeouts" "$ORPHSEEN" 2>/dev/null || true

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
_log_exit() {
  local st=$?                      # MUST be the first statement — any command clobbers $?
  local up=$(( SECONDS - _DAEMON_STARTED ))
  local sess="no"
  [ -f "$LOCK" ] && sess="YES (engine.lock present — a resume session was in flight and may leave it stale)"
  log "=== daemon down (pid $$) — reason: ${_EXIT_REASON} | status=${st} | uptime=${up}s | session-in-flight=${sess} ==="
}
trap _log_exit EXIT
trap '_EXIT_REASON="SIGTERM — launchd bootout/stop, logout, shutdown, or the laptop lid closing"; exit 0' TERM
trap '_EXIT_REASON="SIGINT — Ctrl-C / interactive interrupt"; exit 0' INT
trap '_EXIT_REASON="SIGHUP — controlling terminal closed / login session ended"; exit 0' HUP

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
_terminate_tree() {
  local root="$1" victims p
  kill -0 "$root" 2>/dev/null || return 0        # never fire on a stale/reused pid
  victims="$(_descendants "$root")"
  for p in $victims; do kill -TERM "$p" 2>/dev/null; done
  ( sleep 8; for p in $victims; do kill -KILL "$p" 2>/dev/null; done ) &
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
    elif _orph="$(orphaned_work)"; then
      # ⚠️ DO NOT BLAME THIS SESSION, AND DO NOT REPEAT IT EVERY CYCLE. A dirty `auto/*` worktree is
      # PERMANENT until a human clears it: housekeeping only removes worktrees whose branch is an ancestor
      # of origin/main, and `git worktree remove` refuses a dirty one regardless. So the obvious phrasing —
      # "session (rc=…) left UNCOMMITTED WORK" every no-progress cycle — would pin a week-old orphan on a
      # session that never created a worktree, and would repeat it until the log held nothing else. Both are
      # the failure this whole change is about: a true sentence that reads as something it is not. So name
      # the WORKTREE, not the session, and say each one once per daemon lifetime.
      log "no progress, and a worktree is holding UNCOMMITTED WORK — this is NOT an empty queue."
      for _d in $_orph; do
        grep -qxF "$_d" "$ORPHSEEN" 2>/dev/null && continue
        printf '%s\n' "$_d" >> "$ORPHSEEN" 2>/dev/null || true
        log "  orphaned: $_d —$(orphaned_work_summary "$_d")"
      done
      log "  a later session can finish it, or rescue it by hand; nothing is lost until that worktree is removed."
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
