#!/usr/bin/env bash
# prove-daemon.sh — prove-the-mechanism harness for vision-ocr-autonomous.sh.
#
# WHY IT IS COMMITTED: every change to ops/autonomous/* is a no-undo change to an UNATTENDED process, and
# "it looked right" is not evidence. This drives the REAL daemon with tuned-down timings against a stub
# `claude`, and asserts the numbers it actually wrote to daemon.log. Run it before installing any change to
# the daemon.
#
# FULLY SANDBOXED — it cannot touch the owner's machine:
#   * its own $HOME (park notes land in $T/home/Desktop), its own $STATE, its own throwaway git repo;
#   * `claude` is a stub driven by a control file, so no session, no model, no money;
#   * df / curl / osascript / launchctl / caffeinate / security are stubbed, so no network, no notification
#     on the owner's screen, no `launchctl bootout` of a real job, no power assertion;
#   * it NEVER runs ./run_tests.sh, ./build.sh, health-gate.sh, swiftc or mutate.py — the gate command is a
#     stub. A second suite corrupts BOTH runs (build/tests has no bundle id, so every worktree shares
#     ~/Library/Preferences/tests.plist), and a suite may well be running while this executes.
#
# ⚠️ HOW THE STUBS ARE INTERPOSED, and why $PATH alone is NOT enough. The daemon's line 32 does
#   export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
# which puts the SYSTEM directories AHEAD of anything this harness prepends — so a $T/bin/df stub is
# shadowed by the real /bin/df, /usr/bin/osascript, /bin/launchctl. A harness that relied on PATH would
# quietly drive the real machine while looking sandboxed. So the stubs are injected as shell FUNCTIONS via
# BASH_ENV (functions beat PATH lookups, and subshells inherit them); $T/bin is prepended as well, purely
# as a second layer. preflight() PROVES the interposition works before any daemon is launched, and aborts
# if it does not — the one check that must never be taken on trust.
#
# EXPECTED RESULT: 126 assertions, 0 skipped — RUN 2026-08-30, not inherited (118 before D20's eight, itself
# 110 before D17's eight). ⚠️ D20's eight were WATCHED THREE WAYS: against the pre-fix daemon this harness read
# 120 passed / 6 failed, exactly the six predicted by name and in order; against the fixed tree 126/0/0; and
# against a one-token sabotage widening the copy allowlist to `Tools/mutation-out/*` it read 125 passed /
# 1 failed, the allowlist-is-a-filter row alone, also predicted first. That third run exists because that row
# is VACUOUS pre-fix — nothing is copied at all, so it cannot be red there — which is the second of two greens
# labelled in place; the other is the negative control, whose real job is pinning the fixture's appended
# `.gitignore` line (see the block itself; its first stated reason was wrong and the review said so). This
# line read "118 passed" when the total was 118, which the note below already warns is the wrong reading. This
# line read "75 passed" while the harness was actually running 86 assertions, and then "92" while D12's own
# section three files away recorded 96 — which is the same way a measured number rots into an asserted one
# that ops/autonomous/README.md's own table records two rows of. Re-measure it when you add a section.
# ⛔ IT IS A TOTAL, NOT "118 passed", AND THE DIFFERENCE IS LOAD: §[3]/§[4]/§[4b] drive a real daemon on 1s
# timings and fail under contention, taking the assertions below them with them. MEASURED 2026-08-22 on a
# busy machine, runs back to back: the UNMODIFIED tree at 3078fb0 scored 102 passed / 6 failed (only
# 108 assertions even reached), and the tree carrying D17's eight scored 113 passed / 5 failed — the five a
# strict SUBSET of the six, same sections. Over the FOUR runs this fix went through, the environmental
# failure count was 3, then 1, then 2, then 5 — every one drawn from that same subset of six and never
# anything else. That spread IS the measurement. §[4b]'s vacuity guard fired ("origin/main unchanged
# — the stub is broken and every assertion below is vacuous"), which is the harness saying so itself.
# So: a red §[3]/§[4]/§[4b] on a loaded machine is the INSTRUMENT. Re-run quiet before believing it, and
# never read a failure there as evidence about a change elsewhere — run the baseline too and compare sets,
# which is the only thing that distinguished "my edit broke it" from "this machine is busy" that day.
# ⚠️ THE 2026-08-22 ADDITIONS FOUND THREE DEFECTS BEFORE THEY EVER RAN FOR REAL, which is the argument for
# writing them. The first run of the [17] additions scored 101/2 and BOTH failures were genuine: `add -A`
# swallowed a build artefact because the fixture's `.gitignore` sat in $REPO rather than in the linked
# worktree (a linked worktree has its own working tree and never sees it), and a coverage check fired on a
# complete rescue because `status --porcelain` collapses an untracked directory to `dir/` while the patch
# names the files inside it. The third came out of the adversarial review of the same diff and is why [17b]
# exists: the complete-snapshot path is all-or-nothing, so one unreadable file made it save NOTHING where
# the command it replaced still saved the tracked work.
#
# Section [4b] is the second CONFIRMED DEFECT this harness has found, and it was found by the daemon in
# production first: `work_fingerprint` read only the primary checkout's HEAD, so a session that pushed from its
# worktree without fast-forwarding scored as "advanced nothing". Written as a failing test against the unfixed
# daemon (88 passed / 3 failed), then fixed. See that section for the reflog timings that date it.
#
# Section [7b] was the one failure when this harness was written; it
# found a CONFIRMED DEFECT in vision-ocr-autonomous.sh (a stale $STATE/gate-timeouts is not cleared at
# startup) which was FIXED the same day by adding the file to the startup clear at line ~294. Kept as the
# regression test for that fix. The original note read:
#   [old] a stale $STATE/gate-timeouts is not cleared at startup, so a
# restarted run parks on its first gate hang and claims two "in a row". The one-line fix is in that section's
# comment; delete this paragraph once it lands and the harness will be all-green. It is deliberately NOT
# softened into a pass: an assertion bent to match a bug reads as coverage in review while asserting nothing.
#
# USAGE:  ops/autonomous/tests/prove-daemon.sh [path/to/vision-ocr-autonomous.sh]
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DAEMON="${1:-$HERE/../vision-ocr-autonomous.sh}"
[ -f "$DAEMON" ] || { echo "no daemon at $DAEMON"; exit 2; }
T="$(mktemp -d)"

# Leak-proof cleanup: every launch() records its pid in $T/daemon.pids and the EXIT trap kills any that is
# STILL running this $DAEMON path — guarded by a command-name check so a RECYCLED pid is never killed.
# Without it a run interrupted BETWEEN launch() and stop() (a harness timeout, a Ctrl-C) reparents its
# daemon to init, which then spins forever against a deleted sandbox. That leak was observed for real in the
# project this was ported from.
reap_launched() {
  [ -f "$T/daemon.pids" ] || return 0
  while read -r _p; do
    [ -n "$_p" ] || continue
    case "$(ps -p "$_p" -o command= 2>/dev/null)" in
      *"$DAEMON"*) kill -9 "$_p" 2>/dev/null ;;
    esac
  done < "$T/daemon.pids"
}
_cleanup() { reap_launched; pkill -f "sleep 987654" 2>/dev/null; rm -rf "$T"; }
trap _cleanup EXIT
# …and on the SIGNALS too, which is the case that actually matters: bash does NOT run an EXIT trap when it
# dies of an UNTRAPPED SIGTERM/SIGINT, so `trap … EXIT` alone leaves both the sandbox AND a running daemon
# behind exactly when the harness is killed — a `pkill` of a long run, a Ctrl-C, a CI timeout. Measured: four
# orphaned sandboxes after four pkill'd runs while writing this file. NOTE the cleanup lands at the END of
# the section that is running, not instantly: bash defers a trap until the current foreground command (here a
# `L=$(run_daemon …)`, up to ~30 s) returns. Verified: TERM at t+12s, daemon reaped and sandbox gone by t+40s.
trap '_cleanup; exit 130' INT
trap '_cleanup; exit 143' TERM
trap '_cleanup; exit 129' HUP
PASS=0; FAIL=0; SKIP=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  \033[33mSKIP\033[0m %s\n' "$1"; SKIP=$((SKIP+1)); }

EM="$(printf '\xe2\x80\x94')"          # em dash — the daemon's log lines and BUGS.md headings use it

# ---- sandbox --------------------------------------------------------------------------------------------
export HOME="$T/home"; mkdir -p "$HOME/Desktop" "$HOME/.local/bin"
PARKNOTE="$HOME/Desktop/VISION-OCR-RUN-PARKED.txt"
BIN="$T/bin"; mkdir -p "$BIN"
CURLLOG="$T/curl.log"

# Recording no-op stubs. Each logs its argv so a test can assert the daemon really reached it (and so
# preflight can prove the interposition).
for c in osascript launchctl caffeinate security; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/%s.log"\nexit 0\n' "$c" "$T" "$c" > "$BIN/$c"; chmod +x "$BIN/$c"
done
# curl: records argv AND drains stdin. Draining matters: notify() pipes the body in under `set -o pipefail`,
# so a stub that exits without reading gives printf a SIGPIPE, the pipeline reports 141, and the daemon
# would log "alert FAILED" for an alert that was in fact delivered.
cat > "$BIN/curl" <<STUB
#!/bin/sh
echo "CURL \$*" >> "$CURLLOG"
cat >> "$T/curl.body" 2>/dev/null
exit \${CURL_RC:-0}
STUB
chmod +x "$BIN/curl"
# df: macOS-style \`df -m\` with a scriptable Available column (\$4). \$DFCTL holds one value per line; each
# call consumes the next then repeats the last, so a test can script "low, then reclaimed". A non-numeric
# value exercises the fail-open path; FAIL makes df exit 1 with no output at all.
DFCTL="$T/dfctl"; echo 999999 > "$DFCTL"
cat > "$BIN/df" <<STUB
#!/bin/sh
echo "df \$*" >> "$T/df.log"
n=\$(cat "$DFCTL.count" 2>/dev/null || echo 0); n=\$((n+1)); echo "\$n" > "$DFCTL.count"
val=\$(sed -n "\${n}p" "$DFCTL" 2>/dev/null); [ -n "\$val" ] || val=\$(tail -1 "$DFCTL" 2>/dev/null)
[ "\$val" = "FAIL" ] && exit 1
echo "Filesystem 1M-blocks Used Available Capacity iused ifree %iused Mounted on"
echo "/dev/disk1 1000000 900000 \$val 91% 1 1 0% /"
STUB
chmod +x "$BIN/df"
dfset() { : > "$DFCTL.count"; printf '%s\n' "$@" > "$DFCTL"; }
export PATH="$BIN:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

cat > "$T/preload.sh" <<PRE
# Sourced via BASH_ENV before the daemon's own first line. Shell functions win over PATH, which is the only
# way to interpose on a script that re-prepends the system directories to PATH itself (see the header).
df()         { "$BIN/df" "\$@"; }
curl()       { "$BIN/curl" "\$@"; }
osascript()  { "$BIN/osascript" "\$@"; }
launchctl()  { "$BIN/launchctl" "\$@"; }
caffeinate() { "$BIN/caffeinate" "\$@"; }
security()   { "$BIN/security" "\$@"; }
PRE

echo "[0] SANDBOX INTEGRITY — the stubs must actually intercept, under the daemon's own PATH"
: > "$T/df.log"; : > "$CURLLOG"; : > "$T/osascript.log"; : > "$T/launchctl.log"; : > "$T/caffeinate.log"
BASH_ENV="$T/preload.sh" bash -c '
  export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
  df -m / >/dev/null 2>&1; printf x | curl -fsS http://127.0.0.1:1/x >/dev/null 2>&1
  osascript -e nope >/dev/null 2>&1; launchctl print gui/0/nope >/dev/null 2>&1
  caffeinate -di -w $$ >/dev/null 2>&1; security find-generic-password -s nope >/dev/null 2>&1' >/dev/null 2>&1
_missed=""
for f in df curl osascript launchctl caffeinate; do [ -s "$T/$f.log" ] || _missed="$_missed $f"; done
if [ -n "$_missed" ]; then
  bad "stub interposition BROKEN for:$_missed — refusing to run (this harness would drive the real machine)"
  echo; echo "=================== $PASS passed, $FAIL failed, $SKIP skipped ==================="
  exit 3
fi
ok "df/curl/osascript/launchctl/caffeinate all resolve to sandbox stubs, not to /bin & /usr/bin"

# ---- throwaway repo + run state -------------------------------------------------------------------------
REPO="$T/repo with space"; mkdir -p "$REPO/ops/autonomous"   # space in the path, like the real checkout's
git -C "$REPO" init -q 2>/dev/null
git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
QUEUE="$REPO/ops/autonomous/QUEUE.md"
BUGS="$REPO/BUGS.md"
RUN="$T/RUN.md"
STATE="$T/state"; mkdir -p "$STATE"
CTRL="$T/ctrl"; echo "1:no" > "$CTRL"          # stub-claude script: "<rc>:<commit?>[:queue|bugs]"
CHILDENV="$T/childenv.log"
printf 'STUB PROMPT — this harness never runs a real session.\n' > "$STATE/resume-prompt.txt"

write_queue() {   # $1 = optional extra item text (a new checkbox line moves the fingerprint)
  { printf '# Autonomous work queue\n\n## The queue\n\n'
    printf -- '- [ ] **C24b** %s stub item one\n' "$EM"
    printf -- '- [ ] **stale-docs** %s stub item two\n' "$EM"
    printf -- '- [ ] **tools-compile** %s stub item three\n' "$EM"
    [ -n "${1:-}" ] && printf -- '- [ ] **armed** %s %s\n' "$EM" "$1"
    printf '\n## HOLD %s owner-only\n\n' "$EM"
    printf -- '- [ ] **release** %s cut a release. [hold] needs: owner\n' "$EM"; } > "$QUEUE"
  return 0
}
write_run() {
  { printf 'RUN STATUS: IN_PROGRESS %s prove-daemon\n\n' "$EM"
    printf '## FOCUS\n\nstub focus\n\n## SESSION LOG\n\n(churn lives here %s must NOT read as progress)\n' "$EM"
  } > "$RUN"
  return 0
}
reset_repo() {    # fresh queue + register, committed, so every test starts from a clean decision surface
  write_queue; printf '# BUGS\n\n### VO-0 %s seed entry %s OPEN\n' "$EM" "$EM" > "$BUGS"
  echo seed > "$REPO/f"
  git -C "$REPO" add -A >/dev/null 2>&1; git -C "$REPO" commit -qm reset >/dev/null 2>&1
  git -C "$REPO" update-ref refs/remotes/origin/main HEAD    # housekeeping returns early without it
  write_run
  return 0
}
reset_repo

# ---- stub claude ----------------------------------------------------------------------------------------
# Behaviour is scripted by $CTRL: "<rc>:<commit?>[:queue|bugs]". EVERY invocation appends to $RUN's
# SESSION LOG — that is the churn a real session produces even when it achieves nothing, and proving it does
# NOT read as progress is the assertion the whole backoff mechanism rests on.
#
# <commit?> is `no`, `yes` (commit on the primary checkout's HEAD) or `pushed` (land the work the way a real
# session actually does — in its own worktree, pushed, with the primary checkout left behind). Those two are
# NOT the same event to the fingerprint, which is what section [4b] exists to prove.
cat > "$T/claude" <<STUB
#!/usr/bin/env bash
env > "$CHILDENV"                       # prove exactly what a session inherits
IFS=: read -r rc docommit complete < "$CTRL"
printf '\n### session note %s.%s\n' "\$(date +%s)" "\$\$" >> "$RUN"
case "\$complete" in
  queue) awk '!d && /^- \[ \]/ {sub(/\[ \]/,"[x]"); d=1} {print}' "$QUEUE" > "$QUEUE.tmp" && mv "$QUEUE.tmp" "$QUEUE" ;;
  bugs)  printf '\n### VO-stub $EM stub defect $EM FIXED\n' >> "$BUGS" ;;
esac
if [ "\$docommit" = yes ]; then
  echo "work \$\$ \$RANDOM \$(date +%s)" > "$REPO/f"
  git -C "$REPO" add -A >/dev/null 2>&1; git -C "$REPO" commit -qm "work \$\$" >/dev/null 2>&1
elif [ "\$docommit" = pushed ]; then
  # A SESSION THAT WORKED IN ITS OWN WORKTREE AND PUSHED — origin/main moves, the primary checkout's HEAD
  # does not. Built with git plumbing rather than a second checkout on purpose: the mechanism under test
  # reads REFS, so the commit deliberately carries HEAD's own tree. This fixture is about which ref moved
  # and nothing else, and \$RANDOM keeps successive cycles from colliding on an identical sha.
  _t=\$(git -C "$REPO" rev-parse "HEAD^{tree}")
  _c=\$(git -C "$REPO" commit-tree "\$_t" -p "\$(git -C "$REPO" rev-parse HEAD)" \\
          -m "pushed from a worktree \$\$.\$RANDOM" 2>/dev/null)
  [ -n "\$_c" ] && git -C "$REPO" update-ref refs/remotes/origin/main "\$_c"
fi
exit "\$rc"
STUB
chmod +x "$T/claude"

printf '#!/bin/sh\necho "STATUS-DIGEST-OK parked=${VISIONOCR_STATUS_PARKED:-no}"\n' > "$T/status-stub.sh"
chmod +x "$T/status-stub.sh"

# ---- gate stubs (NEVER the real gate: it builds and runs the suite) -------------------------------------
printf '#!/bin/sh\necho "gate ok"\nexit 0\n' > "$T/gate-green.sh"
{ printf '#!/bin/sh\necho "BUILD FAILED: boom in the OCR path"\n'
  printf 'echo "HEALTH GATE: RED %s reader"\nexit 1\n' "$EM"; } > "$T/gate-red.sh"
printf '#!/bin/sh\nexec sleep 987654\n' > "$T/gate-hang.sh"    # unique argv, so the kill is checkable
cat > "$T/gate-flaky.sh" <<FLAKY
#!/bin/sh
c="$T/flaky.count"; n=\$(cat "\$c" 2>/dev/null || echo 0); n=\$((n+1)); echo "\$n" > "\$c"
[ "\$n" -ge 2 ] && { echo "green on attempt \$n"; exit 0; }
echo "Lost connection to the test manager (transient) attempt \$n"; exit 1
FLAKY
chmod +x "$T/gate-green.sh" "$T/gate-red.sh" "$T/gate-hang.sh" "$T/gate-flaky.sh"

# ---- drive the daemon -----------------------------------------------------------------------------------
launch() {   # $1 = VISIONOCR_IDLE_STOP ; backgrounds the daemon, echoes its pid
  VISIONOCR_LABEL=provetest VISIONOCR_REPO="$REPO" VISIONOCR_STATE="$STATE" \
  VISIONOCR_RUN="$RUN" VISIONOCR_QUEUE="$QUEUE" VISIONOCR_CLAUDE="${CLAUDE_STUB:-$T/claude}" \
  VISIONOCR_INTERVAL=1 VISIONOCR_MAXBACKOFF=8 VISIONOCR_IDLE_STOP="$1" VISIONOCR_HB_POLL=1 \
  VISIONOCR_MAXRUN="${DMAXRUN:-300}" VISIONOCR_STALE="${STALE:-1800}" VISIONOCR_BUDGET=1 \
  VISIONOCR_MINFREE_MB="${MINFREE:-10240}" VISIONOCR_MAX_NOCOMPLETE="${MAXNC:-0}" \
  VISIONOCR_GATE_EVERY="${GATE_EVERY:-0}" VISIONOCR_GATE_CMD="${GATE_CMD:-$T/gate-green.sh}" \
  VISIONOCR_GATE_MAXRUN="${GATE_MAXRUN:-60}" VISIONOCR_GATE_MAX_TIMEOUTS="${GATE_MAX_TIMEOUTS:-2}" \
  VISIONOCR_STATUS_CMD="${STATUS_CMD:-$T/status-stub.sh}" \
  VISIONOCR_COMPACTOR="${COMPACTOR:-$T/no-such-compactor}" \
  VISIONOCR_TEST_LOCK="$STATE/test.lock" \
  BASH_ENV="$T/preload.sh" \
    bash "$DAEMON" >> "$T/daemon.stdout" 2>&1 &
  local pid=$!; echo "$pid" >> "$T/daemon.pids"; echo "$pid"
}
reset_state() {
  : > "$STATE/daemon.log"; : > "$CURLLOG"; : > "$T/curl.body"; : > "$CHILDENV"; : > "$T/df.log"
  : > "$T/osascript.log"; : > "$T/launchctl.log"; : > "$T/caffeinate.log"
  rm -f "$STATE/idle.since" "$STATE/engine.lock" "$STATE/nocomplete.count" "$STATE/last-gate" \
        "$STATE/last-gate.log" "$STATE/gate-timeouts" "$STATE/STATUS.md" "$STATE/env" \
        "$STATE/alert.env" "$STATE/last-session.log" "$STATE/last-session.log.prev" \
        "$DFCTL.count" "$PARKNOTE" "$T/flaky.count"
  rm -rf "$STATE/test.lock"
  return 0
}
stop() { kill -TERM "$1" 2>/dev/null; wait "$1" 2>/dev/null; sleep 1; }   # settle: let a stub session finish
run_daemon() {   # $1=IDLE_STOP $2=seconds to run ; echoes the log path
  reset_state; local p; p=$(launch "$1"); sleep "$2"; stop "$p"; echo "$STATE/daemon.log"
}
gaps() { grep -o "next attempt in [0-9]*s" "$1" | grep -o '[0-9]*' | tr '\n' ' '; }
nsessions() { grep -c 'launching fresh resume session' "$1"; }

# ================= idle backoff =========================================================================
echo "[1] Idle backoff DOUBLES and CAPS — an rc=1 fast-fail must not spin"
echo "1:no" > "$CTRL"; reset_repo; dfset 999999
L=$(run_daemon 0 26); G=$(gaps "$L"); echo "    backoff gaps: $G"
[ "$(echo "$G" | awk '{print $1, $2, $3}')" = "2 4 8" ] && ok "doubles 2 -> 4 -> 8" || bad "expected '2 4 8', got '$G'"
echo "$G" | grep -qv '16' && ok "never exceeds VISIONOCR_MAXBACKOFF=8" || bad "blew past the cap: $G"
[ "$(nsessions "$L")" -le 6 ] && ok "spawns bounded ($(nsessions "$L") in 26s)" || bad "too many spawns: $(nsessions "$L")"
grep -q "likely USAGE-LIMIT fast-fail" "$L" && ok "names the cause (fast-fail, NOT an empty queue)" || bad "fast-fail not distinguished from an idle queue"

echo "[2] SESSION-LOG CHURN IS NOT PROGRESS (the assertion the mechanism rests on)"
echo "0:no" > "$CTRL"; reset_repo; dfset 999999
L=$(run_daemon 0 18)
[ "$(grep -c '### session note' "$RUN")" -ge 2 ] && ok "sessions really did churn the SESSION LOG" || bad "no churn written — test is vacuous"
grep -q "rc=0) advanced nothing (queue + tip unchanged)" "$L" && ok "clean-but-idle read as no-progress" || bad "churn read as progress"
G=$(gaps "$L"); [ "$(echo "$G" | awk '{print $1, $2}')" = "2 4" ] && ok "still backs off despite the churn" || bad "expected '2 4', got '$G'"

echo "[3] A COMMIT is progress and resets the backoff to VISIONOCR_INTERVAL"
echo "0:no" > "$CTRL"; reset_repo; dfset 999999; reset_state
P=$(launch 0); sleep 12; echo "0:yes" > "$CTRL"; sleep 8; stop "$P"; L="$STATE/daemon.log"
grep -q 'no progress' "$L" && ok "backed off while nothing advanced" || bad "never backed off"
grep -q "progress $EM backoff reset to 1s" "$L" && ok "commit detected as progress -> reset to 1s" || bad "no reset on a real commit"

echo "[4] Progress is INDEPENDENT of exit code (commit, THEN exit nonzero)"
echo "1:no" > "$CTRL"; reset_repo; dfset 999999; reset_state
P=$(launch 0); sleep 12; echo "1:yes" > "$CTRL"; sleep 8; stop "$P"; L="$STATE/daemon.log"
grep -q 'resume session exited rc=1' "$L" && ok "the committing session did exit nonzero" || bad "stub never exited nonzero"
grep -q "backoff reset to 1s" "$L" && ok "rc=1-with-commit counts as progress (rc does not gate)" || bad "commit+rc=1 missed — a commit-then-die run would march to a false park"

echo "[4b] A COMMIT PUSHED FROM A WORKTREE is progress (origin/main is a tip too)"
# THE 2026-08-18 04:14 FALSE BACKOFF, as a regression test. The 02:41 session committed `bd574ac`, pushed it
# and removed its worktree; the daemon logged "advanced nothing (queue + tip unchanged)", slept 1800s instead
# of 90s, and left the idle stopwatch reading 21142s. Nothing was wrong with the session — it never
# fast-forwarded the PRIMARY checkout, and work_fingerprint read only that checkout's HEAD. `git reflog` is
# what settles it: refs/remotes/origin/main reached bd574ac at 04:13:07, SEVENTY-FOUR SECONDS before the
# verdict, and main itself did not get there until 04:44:51 — by the NEXT session's `pull --rebase`.
#
# The two halves of the daemon disagreed about where "landed" is recorded, which is why this is a defect and
# not a preference: housekeeping() already deletes branches on the strength of this very ref, and says so —
# "PURELY LOCAL: no `git fetch` — the session's push already advanced the origin/main ref this checkout".
echo "0:no" > "$CTRL"; reset_repo; dfset 999999; reset_state
P=$(launch 0); sleep 12; H0=$(git -C "$REPO" rev-parse HEAD)
# Count the TRUE "advanced nothing" lines the idle phase has already earned. The assertion below has to be
# about lines added AFTER the push, not about the string's presence: those first cycles really did advance
# nothing, and reporting them is the mechanism working. A whole-log grep here failed for exactly that
# reason on its first run, which is this harness's own recurring lesson about over-broad assertions.
N0=$(grep -c "advanced nothing (queue + tip unchanged)" "$STATE/daemon.log" 2>/dev/null || true)
echo "0:pushed" > "$CTRL"; sleep 8; stop "$P"; L="$STATE/daemon.log"
[ "$(git -C "$REPO" rev-parse HEAD)" = "$H0" ] \
  && ok "the primary checkout's HEAD did NOT move (the incident is reproduced, not approximated)" \
  || bad "HEAD moved — this is testing an ordinary commit, not a worktree push"
[ "$(git -C "$REPO" rev-parse refs/remotes/origin/main)" != "$H0" ] \
  && ok "…and origin/main DID move, so the work really landed" \
  || bad "origin/main unchanged — the stub is broken and every assertion below is vacuous"
grep -q "progress $EM backoff reset to 1s" "$L" \
  && ok "a pushed-from-worktree commit reads as progress -> reset to 1s" \
  || bad "scored as no-progress — the 04:14 false backoff (1800s for 90s) is live"
[ "${N0:-0}" -ge 1 ] \
  && ok "the idle phase did log 'advanced nothing' (${N0}x), so the next assertion is not vacuous" \
  || bad "no 'advanced nothing' before the push — the idle phase never ran"
[ "$(grep -c "advanced nothing (queue + tip unchanged)" "$L" 2>/dev/null || true)" = "${N0:-0}" ] \
  && ok "…and NOT ONE MORE after it: no false line over work that is pushed and public" \
  || bad "still logs 'advanced nothing' over work that is committed, pushed and public"
[ -f "$STATE/idle.since" ] \
  && bad "idle stopwatch still running after real progress (it read 21142s at 04:14)" \
  || ok "idle.since cleared — the stopwatch reset that 04:14 did not get"

echo "[5] A QUEUE EDIT wakes it early from backoff_sleep (the owner arming an item)"
echo "1:no" > "$CTRL"; reset_repo; dfset 999999; reset_state
P=$(launch 0); sleep 10; H0=$(git -C "$REPO" rev-parse HEAD)
write_queue "NEWLY ARMED ITEM"          # working-tree edit only: no commit
sleep 8; stop "$P"; L="$STATE/daemon.log"
grep -q "decision surface changed during backoff (commit / queue edit)" "$L" \
  && ok "uncommitted queue edit cut the nap short" || bad "queue edit did not wake it"
[ "$(git -C "$REPO" rev-parse HEAD)" = "$H0" ] && ok "…and it was the queue, not a commit (HEAD unchanged)" || bad "HEAD moved — the wake proves nothing"

echo "[6] RUN STATUS: COMPLETE stops the daemon"
reset_repo; sed -i '' 's/^RUN STATUS:.*/RUN STATUS: COMPLETE/' "$RUN"; dfset 999999
L=$(run_daemon 0 6)
grep -q "RUN STATUS: COMPLETE $EM daemon stopping" "$L" && ok "COMPLETE terminates the run" || bad "COMPLETE path broken"
[ "$(nsessions "$L")" = 0 ] && ok "COMPLETE spawns no session" || bad "spawned a session despite COMPLETE"
grep -q 'daemon down' "$L" && ok "the loop exited (EXIT trap logged the reason)" || bad "loop did not exit"

echo "[7] A STALE idle.since must NOT park on cycle 1 (a restart always buys a full window)"
echo "1:no" > "$CTRL"; reset_repo; dfset 999999; reset_state
echo "$(( $(date +%s) - 100000 ))" > "$STATE/idle.since"     # ~28h old, left by a dead daemon
P=$(launch 3600); sleep 9; stop "$P"; L="$STATE/daemon.log"
grep -q 'PARKED' "$L" && bad "parked on cycle 1 off a stale stamp" || ok "stale idle.since cleared at startup"
[ "$(nsessions "$L")" -ge 2 ] && ok "kept retrying rather than one-and-park" || bad "only $(nsessions "$L") session(s)"

echo "[7b] A STALE gate-timeouts must NOT park on the first hang of a fresh run (mirror of [7])"
# THIS FOUND A REAL BUG, and the daemon was fixed (startup now clears $STATE/gate-timeouts at line ~294).
# Startup clears $IDLE_SINCE and $NOCOMPLETE (line ~277) for a reason it states itself: "a stale stamp from a
# PRIOR run makes the FIRST cycle park immediately — turning the owner's restart, which is an explicit 'try
# again' signal, into a single retry. Starting a run always buys a full window." $STATE/gate-timeouts is the
# same kind of counter — a CONSECUTIVE-timeout streak — and it was left out of that clear. So a run whose gate
# hung once and was then stopped (lid close, `daemon.sh stop`, bootout) comes back with the streak at 1, and
# the FIRST hang of the fresh run parks it, reporting "TIMED OUT 2 cycle(s) in a row" for one timeout in this
# run. Measured: planted 1, the daemon parked 3 s after startup on its first hang.
# THE FIX IS ONE LINE — add the file to the existing startup clear, e.g. next to line 277:
#     rm -f "$IDLE_SINCE" "$NOCOMPLETE" "$STATE/gate-timeouts" 2>/dev/null || true
# ($GATE_TO is defined further down, hence the literal path.) Do NOT clear $STATE/last-gate there: that one is
# SUPPOSED to outlive the daemon, because the gate cadence tracks code churn rather than daemon lifetime.
echo "1:no" > "$CTRL"; reset_repo; dfset 999999; reset_state
echo 1 > "$STATE/gate-timeouts"      # a streak left behind by a prior run (planted AFTER reset_state)
P=$(GATE_EVERY=1 GATE_CMD="$T/gate-hang.sh" GATE_MAXRUN=2 GATE_MAX_TIMEOUTS=2 launch 0)
sleep 9; stop "$P"; L="$STATE/daemon.log"
grep -q 'health gate DUE' "$L" && ok "the gate ran, so the assertion below is not vacuous" || bad "gate never ran"
# ASSERT ON THE STREAK NUMBER, not on whether a park happened at all. GATE_MAXRUN=2 inside a 9 s window
# leaves room for TWO genuine timeouts, and parking on the second is CORRECT behaviour — so a bare
# `grep PARKED` cannot tell "parked off the planted streak" (the bug) from "parked after two real timeouts in
# this run" (right). The FIRST timeout's own counter says which: (1/2) means startup cleared the planted 1,
# (2/2) means it inherited it. That is the exact fact under test, and it cannot go flaky on timing.
first_to="$(grep -m1 'health gate TIMED OUT' "$L")"
case "$first_to" in
  *'(1/2)'*) ok "stale gate-timeouts cleared at startup (first timeout of this run is numbered 1)" ;;
  *'(2/2)'*) bad "the FIRST timeout of a fresh run was numbered 2 — a stale gate-timeouts streak was inherited, so one hang parks the run while claiming two (the bug this section exists for)" ;;
  '')        # No numbered timeout line at all. MEASURED against a daemon with the fix reverted: that is
             # exactly what the bug looks like, because the planted streak makes the FIRST timeout hit the cap
             # and park_run() is reached without ever logging a "(n/m)" line. So distinguish the two reasons
             # rather than reporting the vaguer one — the park note is the tell.
             if grep -q 'PARKED (health gate hung' "$L"; then
               bad "the first timeout of a fresh run went STRAIGHT to a park with no (n/m) line — the planted gate-timeouts streak was inherited, so one hang parks the run while the note claims two (the bug this section exists for)"
             else
               bad "no 'health gate TIMED OUT' line and no park — the gate never timed out, so this section proved nothing (check the stub gate and GATE_MAXRUN)"
             fi ;;
  *)         bad "unrecognised timeout line, cannot judge the streak: $first_to" ;;
esac
pkill -f "sleep 987654" 2>/dev/null

echo "[8] IDLE PARK — parks, writes the Desktop note INTO THE SANDBOX HOME, notifies, logs PARKED"
echo "1:no" > "$CTRL"; reset_repo; dfset 999999
L=$(run_daemon 5 22)
grep -q 'PARKED' "$L" && ok "parked after VISIONOCR_IDLE_STOP=5s" || bad "never parked"
[ -f "$PARKNOTE" ] && ok "park note written to \$HOME/Desktop (sandbox, not the owner's)" || bad "no park note"
grep -q 'display notification' "$T/osascript.log" && ok "owner notification fired (through the stub)" || bad "no local notification"
grep -q 'daemon down' "$L" && ok "loop exited cleanly" || bad "daemon did not exit"

echo "[9] ATTEMPT CAP — commits that complete NO item park; completing one resets the streak"
echo "0:yes" > "$CTRL"; reset_repo; dfset 999999
L=$(MAXNC=2 run_daemon 0 14)
grep -q "attempt streak 1/2" "$L" && ok "counts checkpoint-only sessions" || bad "no streak count"
grep -q "PARKED (no item completed in 2 sessions" "$L" && ok "parked at the cap, with the reason" || bad "never parked at the cap"
reset_repo; dfset 999999; reset_state
P=$(MAXNC=6 launch 0)
echo "0:yes"      > "$CTRL"; sleep 5      # checkpoints only: streak climbs
echo "0:yes:bugs" > "$CTRL"; sleep 4      # close a BUGS.md entry: a completion the QUEUE cannot see
echo "0:yes"      > "$CTRL"; sleep 5
stop "$P"; L="$STATE/daemon.log"
grep -q "attempt streak reset" "$L" && ok "a closed BUGS.md entry counts as a completion -> streak reset" || bad "BUGS.md completion missed (would false-park a healthy drain)"
grep -q "PARKED (no item completed" "$L" && bad "parked despite a completion resetting the streak" || ok "did not park a healthy run"

# ================= disk guard ============================================================================
echo "[10] DISK GUARD — parks when low, fails OPEN when unreadable, self-heals when reclaimed"
echo "0:no" > "$CTRL"; reset_repo; dfset 100          # 100MB free, persistently (< MINFREE 10240)
L=$(run_daemon 0 8)
grep -q 'PARKED (low disk' "$L" && ok "parked on low disk" || bad "did not park on low disk"
[ "$(nsessions "$L")" = 0 ] && ok "launched no session (never builds on a full disk)" || bad "launched a session anyway"
dfset notanumber
L=$(run_daemon 0 8)
grep -q 'PARKED' "$L" && bad "parked on unparseable df (must fail open)" || ok "garbage df fails OPEN"
[ "$(nsessions "$L")" -ge 1 ] && ok "…and kept working normally" || bad "stopped launching sessions"
dfset FAIL                                            # df exits 1, no output
L=$(run_daemon 0 8)
# Guard against a VACUOUS pass: "no PARKED line" is also true of a daemon that never got as far as the disk
# check, so prove the check ran (df was consulted) and the run continued.
[ -s "$T/df.log" ] && ok "the disk check really ran (df was consulted)" || bad "df never called — the fail-open assertions below are vacuous"
grep -q 'PARKED' "$L" && bad "parked when df exited nonzero (must fail open)" || ok "df exit!=0 also fails OPEN"
[ "$(nsessions "$L")" -ge 1 ] && ok "…and sessions kept launching" || bad "stopped launching sessions"
dfset 100 50000                                       # low, then reclaimed by housekeeping
L=$(run_daemon 0 8)
grep -q 'running housekeeping to reclaim' "$L" && ok "attempted reclaim before giving up" || bad "no reclaim attempt"
grep -q 'disk reclaimed' "$L" && ok "detected the reclaim and continued" || bad "did not continue after the reclaim"
grep -q 'PARKED' "$L" && bad "parked despite reclaiming enough space" || ok "did not park after a successful reclaim"

# ================= health gate ===========================================================================
echo "[11] HEALTH GATE — green/red/flaky/timeout/not-due/bad-sha (all against STUB gates)"
echo "1:no" > "$CTRL"; reset_repo; dfset 999999
L=$(GATE_EVERY=1 GATE_CMD="$T/gate-green.sh" run_daemon 0 10)
grep -q 'health gate GREEN' "$L" && ok "a due gate that passes is GREEN" || bad "gate did not run/pass"
[ -s "$STATE/last-gate" ] && ok "recorded the last-green sha" || bad "last-gate not recorded"
[ "$(nsessions "$L")" -ge 1 ] && ok "GREEN is non-terminal — normal work continued" || bad "daemon stopped after a green gate"

echo "1:no" > "$CTRL"; reset_repo; dfset 999999
L=$(GATE_EVERY=1 GATE_CMD="$T/gate-red.sh" run_daemon 0 14)
grep -q "health gate RED $EM retrying ONCE" "$L" && ok "RED retries once before parking" || bad "no retry before park"
grep -q "PARKED (health gate RED (x2) $EM reader" "$L" && ok "parks on a reproducible RED, naming the step" || bad "did not park (or the reason is anonymous)"
[ "$(nsessions "$L")" = 0 ] && ok "no session launched behind a red gate" || bad "launched a session despite RED"

echo "0:no" > "$CTRL"; reset_repo; dfset 999999
L=$(GATE_EVERY=1 GATE_CMD="$T/gate-flaky.sh" run_daemon 0 12)
grep -q 'GREEN on retry' "$L" && ok "a flaky RED recovers on the retry" || bad "flaky failure not recovered"
grep -q 'PARKED (health gate' "$L" && bad "PARKED on a transient failure" || ok "did not park a healthy run on a flaky check"

echo "0:no" > "$CTRL"; reset_repo; dfset 999999
L=$(GATE_EVERY=1 GATE_CMD="$T/gate-hang.sh" GATE_MAXRUN=2 GATE_MAX_TIMEOUTS=9 run_daemon 0 10)
grep -q 'health gate TIMED OUT' "$L" && ok "a hung gate is capped and killed" || bad "did not time out a hung gate"
grep -q 'PARKED (health gate' "$L" && bad "PARKED on a single hang (inconclusive, must skip)" || ok "a single timeout SKIPS rather than parks"
pgrep -f "sleep 987654" >/dev/null 2>&1 && { bad "the hung gate process leaked"; pkill -f "sleep 987654"; } || ok "the hung gate's process tree was killed"

echo "0:no" > "$CTRL"; reset_repo; dfset 999999
L=$(GATE_EVERY=1 GATE_CMD="$T/gate-hang.sh" GATE_MAXRUN=2 GATE_MAX_TIMEOUTS=2 run_daemon 0 16)
grep -q 'PARKED (health gate hung' "$L" && ok "consecutive timeouts escalate to a park" || bad "persistent hangs never escalated"
pkill -f "sleep 987654" 2>/dev/null

echo "1:no" > "$CTRL"; reset_repo; dfset 999999; reset_state
git -C "$REPO" rev-parse HEAD > "$STATE/last-gate"           # seeded AFTER reset_state, which wipes it
P=$(GATE_EVERY=100 GATE_CMD="$T/gate-green.sh" launch 0); sleep 6; stop "$P"; L="$STATE/daemon.log"
grep -q 'health gate DUE' "$L" && bad "ran a gate when not due" || ok "not due -> no gate"
[ "$(nsessions "$L")" -ge 1 ] && ok "…and a normal session ran instead" || bad "no session ran"

reset_repo; dfset 999999; reset_state
echo deadbeefdeadbeefdeadbeefdeadbeefdeadbeef > "$STATE/last-gate"
P=$(GATE_EVERY=100 GATE_CMD="$T/gate-green.sh" launch 0); sleep 8; stop "$P"; L="$STATE/daemon.log"
grep -q 'health gate DUE' "$L" && ok "an invalid last-gate sha fails OPEN (gate now)" || bad "bad sha silently skipped the gate"

# ================= engine lock ===========================================================================
echo "[12] ENGINE LOCK — a fresh lock skips the cycle, a stale one is taken over"
echo "1:no" > "$CTRL"; reset_repo; dfset 999999; reset_state
touch "$STATE/engine.lock"
P=$(launch 0); sleep 5; stop "$P"; L="$STATE/daemon.log"
grep -q 'engine busy' "$L" && ok "fresh lock -> cycle skipped" || bad "did not detect the busy engine"
# DIAGNOSTIC ON FAILURE, added 2026-08-17: "launched a session anyway" is a bare count and says nothing about
# WHY the lock stopped being respected — whether it was removed, aged out, or never seen. Printing the log and
# the lock's fate turns a rerun-and-squint into one reading.
if [ "$(nsessions "$L")" = 0 ]; then
  ok "…and no session was launched behind it"
else
  bad "launched a session anyway ($(nsessions "$L")) — lock $([ -f "$STATE/engine.lock" ] && echo STILL PRESENT || echo GONE) at assert time"
  sed 's/^/        /' "$L"
fi
reset_state; touch "$STATE/engine.lock"; touch -t 202601010000 "$STATE/engine.lock"
P=$(launch 0); sleep 5; stop "$P"; L="$STATE/daemon.log"
grep -q "stale lock" "$L" && ok "stale lock -> taken over" || bad "did not take over a stale lock"

# ================= STATUS digest =========================================================================
echo "[13] STATUS.md is written every cycle and refreshed on park"
echo "1:no" > "$CTRL"; reset_repo; dfset 999999
L=$(run_daemon 0 6)
grep -q 'STATUS-DIGEST-OK' "$STATE/STATUS.md" 2>/dev/null && ok "STATUS.md written mid-run" || bad "STATUS.md missing or empty"
reset_repo; dfset 999999
L=$(run_daemon 5 22)
grep -q 'parked=no progress' "$STATE/STATUS.md" 2>/dev/null && ok "refreshed on park, with the park reason" \
  || bad "park flag not passed to the digest ($(tr -d '\n' < "$STATE/STATUS.md" 2>/dev/null))"

# ================= alerting ==============================================================================
echo "[14] ALERTING — silent when unconfigured, and the credential NEVER reaches the session env"
echo "1:no" > "$CTRL"; reset_repo; dfset 999999
L=$(run_daemon 5 22)                                  # no alert.env, no $STATE/env
grep -q 'PARKED' "$L" && ok "parks fine with no ALERT_URL" || bad "park broke when unconfigured"
[ -s "$CURLLOG" ] && bad "curl invoked despite no ALERT_URL" || ok "no curl at all (clean no-op)"
grep -q 'alert FAILED' "$L" && bad "logged a spurious alert failure" || ok "no spurious failure logged"

reset_repo; dfset 999999; reset_state
printf 'ALERT_URL="https://example.invalid/SECRETTOKEN123"\n' > "$STATE/alert.env"
P=$(launch 5); sleep 22; stop "$P"; L="$STATE/daemon.log"
grep -q 'SECRETTOKEN123' "$CURLLOG" && ok "the park alert reached the configured endpoint" || bad "no alert POSTed"
grep -q 'alert sent' "$L" && ok "logged as sent" || bad "alert not logged as sent"
grep -q 'SECRETTOKEN123' "$L" && bad "SECRET LEAKED into daemon.log" || ok "the endpoint/token never reaches the log"
# An EMPTY $CHILDENV would make the leak assertion pass without proving anything, so establish first that a
# session env was actually captured.
[ -s "$CHILDENV" ] && ok "captured a real session environment to inspect" || bad "no session env captured — the leak assertion would be vacuous"
grep -q 'SECRETTOKEN123' "$CHILDENV" && bad "SECRET LEAKED into the session env via alert.env" || ok "alert.env stays daemon-only — child env clean"

reset_repo; dfset 999999; reset_state
printf 'ALERT_URL="https://example.invalid/MISPLACED456"\n' > "$STATE/env"   # the operator's mistake
P=$(launch 5); sleep 22; stop "$P"; L="$STATE/daemon.log"
grep -q 'MISPLACED456' "$CHILDENV" && bad "a misplaced ALERT_URL in \$STATE/env LEAKED to the child" \
  || ok "misplaced ALERT_* un-exported before the spawn (defence in depth)"
grep -q 'MISPLACED456' "$CURLLOG" && ok "…while notify() kept the value (export -n, not unset)" || bad "export -n destroyed the value too"
rm -f "$STATE/env"

# ================= source guard ==========================================================================
echo "[15] SOURCE GUARD — sourcing loads config and starts NOTHING"
: > "$T/caffeinate.log"; : > "$STATE/daemon.log"
SRC=$(VISIONOCR_REPO="$REPO" VISIONOCR_STATE="$STATE" VISIONOCR_RUN="$RUN" VISIONOCR_QUEUE="$QUEUE" \
      BASH_ENV="$T/preload.sh" bash -c '
        . "$1"; echo "SOURCE_RC=$?"
        echo "DENY0=${DENY[0]:-none} ALLOWN=${#ALLOW[@]}"
        echo "TRAPS=[$(trap -p | tr "\n" ";")]"' _ "$DAEMON" 2>&1)
printf '%s\n' "$SRC" | grep -q 'sourced, not executed' && ok "says it was sourced, not executed" || bad "no source-guard message: $SRC"
printf '%s\n' "$SRC" | grep -q 'DENY0=Bash(sudo:\*)' && ok "config loaded (DENY/ALLOW arrays present)" || bad "config not loaded: $SRC"
printf '%s\n' "$SRC" | grep -q 'TRAPS=\[\]' && ok "installed no traps in the caller's shell" || bad "installed traps: $SRC"
[ -s "$T/caffeinate.log" ] && bad "sourcing spawned caffeinate" || ok "spawned no caffeinate"
grep -q 'daemon up' "$STATE/daemon.log" && bad "sourcing started the loop" || ok "started no loop (no 'daemon up')"

# ⚠️ AND IT MUST NOT TOUCH STATE — the half of "starts NOTHING" this section used to miss entirely.
# The assertions above check traps, caffeinate and the loop, all of which were already correct. The startup
# counter-clear was NOT checked, and it sat at module scope ABOVE the source guard, so a source ran it.
#
# Measured 2026-08-16 21:2x, by hitting it: sourcing the daemon to verify this very section's behaviour —
# with $VISIONOCR_STATE unset, so $STATE fell back to the REAL ~/.local/state/visionocr-autonomous — deleted
# the live run's `idle.since` while a session was 70 minutes into its work. `nocomplete.count` (the attempt
# cap) and `gate-timeouts` (a park trigger) go with it, so one keystroke silently resets two counters whose
# entire purpose is stopping a runaway. A section that reported "starts NOTHING" in green over a file that
# deleted three state files is precisely what this project means by a check that could not fail.
#
# Planted VALUES, not just presence: a clear that ran and then recreated the files would pass an existence
# check. The converse — that a REAL start still wipes them — is already asserted by §[7], which is why it is
# not repeated here; between them, moving the clear below the guard cannot go too far in either direction.
: > "$STATE/daemon.log"
echo 4242 > "$STATE/idle.since"; echo 3 > "$STATE/nocomplete.count"; echo 1 > "$STATE/gate-timeouts"
VISIONOCR_REPO="$REPO" VISIONOCR_STATE="$STATE" VISIONOCR_RUN="$RUN" VISIONOCR_QUEUE="$QUEUE" \
  BASH_ENV="$T/preload.sh" bash -c '. "$1"' _ "$DAEMON" >/dev/null 2>&1
survived=0
[ "$(cat "$STATE/idle.since" 2>/dev/null)"       = 4242 ] && survived=$((survived+1))
[ "$(cat "$STATE/nocomplete.count" 2>/dev/null)" = 3    ] && survived=$((survived+1))
[ "$(cat "$STATE/gate-timeouts" 2>/dev/null)"    = 1    ] && survived=$((survived+1))
[ "$survived" = 3 ] \
  && ok "sourcing left idle.since / nocomplete.count / gate-timeouts untouched" \
  || bad "sourcing destroyed run state — $((3 - survived)) of 3 counters cleared (the clear must live BELOW the source guard)"
rm -f "$STATE/idle.since" "$STATE/nocomplete.count" "$STATE/gate-timeouts"

# ================= a stop must not orphan the session's tree ============================================
# REGRESSION TEST FOR THE 2026-08-17 07:55 ORPHAN (README §Defects D1/D4). The daemon's TERM/INT/HUP traps
# were `exit 0`: they LOGGED "session-in-flight=YES … may leave it stale" and did nothing, so a bootout,
# logout or lid close killed `claude` and left its whole subtree running at ppid 1. Measured: a
# `test-lock.sh -> mutate.py -> run_tests.sh -> build/tests` chain alive 40+ minutes later at 98% of a core,
# still holding the suite lock, with nothing left to read its result.
#
# ⚠️ THE GRANDCHILD IS THE WHOLE POINT. Killing `claude` was never the broken part — every earlier version of
# this harness would have passed a test that only checked the session pid. What was broken is the process
# TWO levels down, which is where every expensive thing in this repo actually runs (the suite, the build,
# swiftc, mutate.py). So the stub spawns a grandchild with a unique argv and the assertion is about THAT.
echo "[16] A TRAPPED STOP TEARS DOWN THE WHOLE SESSION TREE (not just \`claude\`)"
cat > "$T/claude-spawner" <<'SPAWN'
#!/usr/bin/env bash
# Stand-in for a session that has started a suite: a grandchild the daemon must reach, then a long wait.
sleep 987321 &
sleep 987322
SPAWN
chmod +x "$T/claude-spawner"
echo "0:no:no" > "$CTRL"; reset_repo; dfset 999999; reset_state
pkill -f 'sleep 98732' >/dev/null 2>&1; sleep 0.3
CLAUDE_STUB="$T/claude-spawner"; P=$(launch 0)
# Wait for the grandchild to exist, so a pass cannot come from it never having started (a vacuous green).
gc=""; for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  gc="$(pgrep -f 'sleep 987321' 2>/dev/null | head -1)"; [ -n "$gc" ] && break; sleep 1
done
if [ -z "$gc" ]; then
  bad "the stub's grandchild never started — section [16] would have been vacuous"
else
  ok "the session's grandchild is running (pid $gc), so the assertions below are not vacuous"
  [ -f "$STATE/engine.lock" ] && ok "engine.lock present while the session is in flight" \
                              || bad "no engine.lock during a live session (premise broken)"
  kill -TERM "$P" 2>/dev/null; wait "$P" 2>/dev/null
  # The trap TERMs the tree and schedules a detached KILL 8s later; allow for both.
  gone=0; for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
    kill -0 "$gc" 2>/dev/null || { gone=1; break; }; sleep 1
  done
  [ "$gone" = 1 ] && ok "the grandchild died with the daemon — the tree was torn down, not orphaned" \
                  || bad "GRANDCHILD $gc SURVIVED THE STOP — this is the 2026-08-17 orphan (D1)"
  [ -f "$STATE/engine.lock" ] && bad "engine.lock left behind — a restart idles until it goes stale (D4)" \
                              || ok "engine.lock cleared by the stop (no \$STALE wait on restart)"
  grep -q 'session-in-flight=YES — TERMed' "$STATE/daemon.log" \
    && ok "the down line reports what it actually did, not just that a session existed" \
    || bad "the down line still only NAMES the hazard: $(grep -o 'session-in-flight=.*' "$STATE/daemon.log" | tail -1)"
fi
pkill -f 'sleep 98732' >/dev/null 2>&1
unset CLAUDE_STUB          # every later section must go back to the normal stub

# ================= orphaned work is SAVED, not just reported ============================================
# REGRESSION TEST FOR README §Defects D8. The orphan detector's closing line read "nothing is lost until that
# worktree is removed" — true of `git worktree remove`, false of the directory those worktrees live in. Every
# session works in /private/tmp/vo-<stamp>, which macOS clears on reboot, so the daemon's own answer to "is
# this work safe?" rested on a volatile filesystem holding the ONLY copy.
echo "[17] AN ORPHANED WORKTREE'S WORK IS SNAPSHOTTED TO \$STATE/rescue"
echo "0:no:no" > "$CTRL"; reset_repo; dfset 999999; reset_state
rm -rf "$STATE/rescue"
# ⚠️ THE SANDBOX REPO NEEDS run-state-lib.sh, and without it this section is not merely weak but INVERTED.
# The daemon sources the lib from "$REPO/ops/autonomous/run-state-lib.sh" and falls back to
# `orphaned_work() { return 1; }` when it is absent — a deliberate degrade-don't-die guard for an old
# checkout. $REPO here is the throwaway repo, which has no ops/ tree, so the detector was hard-wired off and
# the section reported "NO PATCH SAVED" as a daemon defect when the daemon had never been asked. Measured:
# it failed identically against the FIXED daemon. Copy the real lib in, and SKIP loudly if it cannot be
# found rather than emitting a red that means nothing.
mkdir -p "$REPO/ops/autonomous"
if cp "$(cd "$(dirname "$DAEMON")" && pwd)/run-state-lib.sh" "$REPO/ops/autonomous/run-state-lib.sh" 2>/dev/null; then
  ok "run-state-lib.sh is present in the sandbox repo, so the real orphan detector is live"
else
  skip "run-state-lib.sh not found beside $DAEMON — the orphan detector cannot be exercised here"
fi
OW="$T/orphan-wt"; rm -rf "$OW"
git -C "$REPO" worktree add -q -b auto/orphan-test "$OW" >/dev/null 2>&1
printf 'unique-rescue-payload-%s\n' "$$" > "$OW/rescued.txt"
git -C "$OW" add rescued.txt >/dev/null 2>&1          # tracked+staged: a died-in-the-hook commit looks like this
# ⛔ AND AN UNTRACKED FILE BESIDE IT, because the staged one above is why this section could not catch the
# 2026-08-22 defect. `git diff HEAD` — what the rescue used to run — cannot see an untracked path, so a
# fixture whose whole payload is STAGED agrees with the broken implementation: the patch came out complete
# because everything in it was tracked. Measured on the real machine that day: a strand's saved patch held
# 5 tracked files at 90,263 B while a 10,465 B untracked `.tsv`, the only copy in existence, was named in
# the `.status` beside it and in no patch at all. A measurement sweep is exactly this shape — one new file
# and nothing else — and `orphaned_work` did not even count it until the same commit widened it.
# The ignored file is the other half of the assertion: the rescue must stay a few-KB patch, not a copy of
# a worktree's build output, so `add -A` honouring .gitignore is load-bearing and is pinned below.
printf 'untracked-payload-%s\n' "$$" > "$OW/new-measurement.tsv"
mkdir -p "$OW/build" && printf 'ignored-noise-%s\n' "$$" > "$OW/build/artifact.o"
# ⚠️ THE .gitignore GOES IN THE ORPHAN WORKTREE, NOT IN $REPO. A linked worktree has its OWN working tree,
# so an uncommitted `$REPO/.gitignore` is simply not present in `$OW` and ignores nothing there — the first
# version of this fixture put it in $REPO and the assertion below went red because `add -A` correctly
# swallowed a build artefact that nothing had told it to ignore. It does not need to be tracked: git reads
# .gitignore out of the working tree whether or not it is in the index.
printf 'build/\n' > "$OW/.gitignore"
# ⛔ AND A GITIGNORED ARTEFACT THAT IS EVIDENCE — the THIRD class, and the one no test over the patch and
# the `.status` could ever have caught, because a gitignored path is absent from BOTH by construction:
# `add -A` honours .gitignore (pinned above, load-bearing) and `status --porcelain` cannot see one at all.
# Measured 2026-08-29 on `vo-20260828-060044-25839`: its
# `Tools/mutation-out/logic_R25-depth-aware-prune.log` (103,159 B) was the ONLY evidence for the 280 s suite
# row that strand's adoption published, and this loop had logged "COMPLETE — tracked and untracked" while
# holding neither. The fix is a narrow copy ALLOWLIST plus a banner that names what it covers.
# ⚠️ THE NON-MATCHING SIBLING IS HALF THE FIXTURE: without it every assertion below is satisfied by
# "copy the whole ignored tree", which is the copy-not-a-patch regression the `build/` row exists to refuse.
mkdir -p "$OW/Tools/mutation-out"
printf 'mutation-evidence-%s\n' "$$" > "$OW/Tools/mutation-out/logic_probe.log"
printf 'not-allowlisted-%s\n'   "$$" > "$OW/Tools/mutation-out/logic_probe.txt"
printf 'Tools/mutation-out/\n' >> "$OW/.gitignore"
# Prove the PREMISE before asserting on the response: if the detector does not see this worktree, a missing
# patch says nothing about the rescue code.
seen_orph="$(VISIONOCR_REPO="$REPO" bash -c '. "$1"; REPO="$2" orphaned_work' _ \
             "$REPO/ops/autonomous/run-state-lib.sh" "$REPO" 2>/dev/null)"
case "$seen_orph" in
  *"$OW"*) ok "orphaned_work sees the dirty worktree (the premise holds)" ;;
  *) bad "orphaned_work does not see $OW — fix the fixture, not the daemon (got: '$seen_orph')" ;;
esac
L=$(run_daemon 0 6)
if [ -f "$STATE/rescue/orphan-wt.patch" ]; then
  ok "a patch was written for the dirty auto/* worktree"
  grep -q "unique-rescue-payload-$$" "$STATE/rescue/orphan-wt.patch" \
    && ok "…and it actually contains the stranded content (not an empty diff)" \
    || bad "the patch exists but does not hold the work — a backup that restores nothing"
  [ -s "$STATE/rescue/orphan-wt.base" ] \
    && ok "…and records the base sha it applies to" \
    || bad "no base sha recorded — a patch with no base is guesswork to restore"
  grep -q 'rescued:' "$L" && ok "the log tells the owner where the durable copy is" \
                          || bad "the rescue is silent, so nobody knows it happened"
  # The three assertions the staged-only fixture could never make.
  grep -q "untracked-payload-$$" "$STATE/rescue/orphan-wt.patch" \
    && ok "…and it holds the UNTRACKED file too (git diff HEAD cannot see one — add -A into a scratch index can)" \
    || bad "the patch MISSES the untracked payload — a partial backup advertising itself as complete (2026-08-22)"
  grep -q "ignored-noise-$$" "$STATE/rescue/orphan-wt.patch" \
    && bad "the patch swallowed a GITIGNORED build artefact — add -A must honour .gitignore or this stops being a patch" \
    || ok "…and it excludes gitignored build output, so it stays a patch rather than a copy"
  [ -f "$STATE/rescue/orphan-wt.complete" ] \
    && ok "…and it is marked COMPLETE, which is what stops a later run re-snapshotting it" \
    || bad "no .complete marker — every future cycle will re-snapshot this worktree"
  grep -q 'PARTIAL rescue' "$L" \
    && bad "reported PARTIAL on a snapshot that captured everything — inverted, or add -A really failed" \
    || ok "…and it does not cry PARTIAL over a complete snapshot"
  # ---- the GITIGNORED class: five separate claims, not five phrasings of one -----------------------------
  # ⛔ NEGATIVE CONTROL FIRST. ⚠️ Its stated reason was wrong in the first draft of this block — "what makes
  # the four below capable of failing" — and the review of that diff refuted it: the log check and the banner
  # `case` assert about `$L` and do not depend on the patch at all, so only the COPY check does. What this row
  # genuinely buys, and nothing else in the section does, is that the fixture's APPENDED `.gitignore` line took
  # effect: if `Tools/mutation-out/` were not ignored inside `$OW` (a linked worktree has its own working tree
  # — see the note above, which the first version of this fixture got wrong in $REPO) then `add -A` would
  # swallow the log and this row goes red. The ignore rule is asserted by nothing else.
  grep -q "mutation-evidence-$$" "$STATE/rescue/orphan-wt.patch" \
    && bad "NEGATIVE CONTROL FAILED: the patch holds the GITIGNORED log, so the allowlist checks below cannot fail" \
    || ok "negative control: the patch cannot hold the gitignored log, so only an explicit copy can"
  _ign="$STATE/rescue/orphan-wt.ignored-Tools-mutation-out-logic_probe.log"
  { [ -f "$_ign" ] && grep -q "mutation-evidence-$$" "$_ign"; } \
    && ok "…and the ALLOWLISTED gitignored artefact is copied out beside the trio (a mutation run's log is the only evidence it leaves — 2026-08-29)" \
    || bad "the allowlisted gitignored artefact was NOT copied out: no patch can hold it and no .status can name it, so /private/tmp is its only copy"
  ls "$STATE/rescue" 2>/dev/null | grep -q 'logic_probe\.txt' \
    && bad "the copy allowlist took a NON-matching ignored file — it is a filter, or build/ is next and this stops being a patch" \
    || ok "…and it leaves the non-matching ignored sibling alone, so the allowlist is a filter and not a tree copy"
  grep -q 'gitignored artefact' "$L" \
    && ok "…and the log names the gitignored copies, so a triaging session knows they exist" \
    || bad "the gitignored copies are silent in the log — an omission nobody can see is the whole defect"
  # ⛔ AND THE BANNER ITSELF, which is what the queue item calls the defect: "COMPLETE — tracked and
  # untracked" reads as "everything" over a snapshot that covers neither ignored paths nor the artefact a
  # mutation run leaves. The predicate is that the line NAMES the class it cannot hold.
  case "$(grep -m1 'rescued: ' "$L" 2>/dev/null)" in
    *gitignored*) ok "…and the COMPLETE banner names the one class a patch cannot hold, so it no longer reads as 'everything'" ;;
    *) bad "the COMPLETE banner still claims tracked-and-untracked without naming the gitignored gap (2026-08-29)" ;;
  esac
  # ⚠️ NEGATIVE CONTROL, mandatory here: every assertion above is satisfied by a patch that happens to be
  # complete for the wrong reason, so prove the coverage check can FAIL. Run the PRE-FIX command on the same
  # worktree and assert it comes out short — if this ever passes, the fixture stopped exercising the bug and
  # the four checks above are decoration. This is the eleventh-check-that-could-not-fail discipline applied
  # to the check being added, not to the code.
  git -C "$OW" diff HEAD > "$T/prefix-rescue.patch" 2>/dev/null || true
  if grep -q "untracked-payload-$$" "$T/prefix-rescue.patch" 2>/dev/null; then
    bad "NEGATIVE CONTROL FAILED: 'git diff HEAD' also captured the untracked file, so this section cannot fail"
  else
    ok "negative control: the pre-fix 'git diff HEAD' misses that payload, so these checks can fail"
  fi
else
  bad "NO PATCH SAVED for a worktree holding uncommitted work — /private/tmp is the only copy (D8)"
fi
# The assignment is the point: a snapshot makes the work safe, an assignment makes it MOVE.
if [ -f "$STATE/triage/orphan-wt.md" ]; then
  ok "a triage assignment was written, so the strand is a session's job and not the owner's"
  grep -q "$OW" "$STATE/triage/orphan-wt.md" \
    && ok "…and it names the worktree the session has to go and look at" \
    || bad "the assignment does not name the worktree — a task nobody can act on"
  grep -q 'assigned:' "$L" && ok "…and the log says it was assigned rather than escalated" \
                           || bad "the assignment is silent in the log"
  # ⛔ THE ADOPTION PATH MUST END BY REMOVING THE STRAND, and until 2026-08-22 it did not. Step 3 stopped
  # at "commit, push", so an adopting session landed the content, deleted its triage `.md` — which is what
  # marks a strand resolved, and therefore what makes it ELIGIBLE AGAIN — and left the worktree dirty on
  # disk. `housekeeping()` never reaps a dirty worktree, so the next cycle re-assigned the same strand.
  # MEASURED: `f5bdbea` adopted `vo-20260822-073825-10384` at 14:05:36 and the daemon re-assigned it at
  # 14:09:59, four minutes later. That is a LOOP, not a one-off: every following session spends its one
  # item re-proving content that is already on main. The two checks below read the step-3 paragraph out of
  # the assignment the daemon actually wrote, so they pin the instruction rather than the prose around it.
  # ⚠️ THE PREDICATE IS THE REMOVAL'S TWO ENDPOINTS — the restore it starts with and the branch deletion it
  # ends with — and NOT the string `worktree remove`. Measured: the first draft grepped for that string, and
  # when step 3 was rewritten to REFERENCE step 2's block rather than repeat it, the check went red over a
  # correct document. Worse, before the rewrite the same grep had gone GREEN on `worktree remove --force`,
  # the denied form. One token, wrong in both directions. These two survive either shape, because a step 3
  # that inlines the block names them and a step 3 that cites it names them as the block's bounds.
  _step3="$(awk '/^3\. If it holds UNIQUE work/,/^4\. If it is TRIVIAL/' "$STATE/triage/orphan-wt.md")"
  if printf '%s\n' "$_step3" | grep -q 'checkout HEAD' && printf '%s\n' "$_step3" | grep -q 'branch -d'; then
    ok "…and the ADOPTION path itself carries the removal through to the end, so an adopted strand is not re-assigned next cycle"
  else
    bad "step 3 stops before removing the source strand — it stays dirty on disk and the daemon re-assigns it every cycle (measured 2026-08-22: f5bdbea, re-assigned 4 min later)"
  fi
  # …and under the right NAME. `SUPERSEDED-by-` is step 2's word and it is the wrong one here: an adopting
  # session did not replace the work with different work, it landed that same work. The rescue directory
  # already carries both conventions (five `LANDED-as-*` sets and five `SUPERSEDED-by-*`, counted
  # 2026-08-22), and the session that adopted this strand picked `LANDED-as-` correctly with the template
  # telling it nothing.
  printf '%s\n' "$_step3" | grep -q 'LANDED-as-' \
    && ok "…and files the rescue trio as LANDED-as-<sha>, which is what the adoption path did by convention while the template said only SUPERSEDED-by-" \
    || bad "step 3 does not name the LANDED-as- filing, so an adopting session either invents a name or reuses step 2's wrong one"
  # ⚠️ NEGATIVE CONTROL for both: the awk range must have SELECTED something. An empty $step3 makes the two
  # greps fail for a reason that has nothing to do with the instruction — a renamed step heading would then
  # read as the defect, and after the fix a broken range would read as a pass on the whole assignment text.
  [ "$(printf '%s\n' "$_step3" | wc -l | tr -d ' ')" -ge 3 ] \
    && ok "negative control: the step-3 range actually matched a paragraph, so the two checks above are reading step 3 and not an empty string" \
    || bad "the step-3 awk range selected nothing — those two checks cannot fail for the right reason"
  # ⚠️ AND STEP 2 MUST OFFER THE NO-FORCE ROUTE, because MEASURED 2026-08-22 the force was never needed and
  # a session cannot use it: `git worktree remove --force` is DENIED at the tool layer. Once the three
  # preconditions hold the dirty files are redundant twice over — on main and in the rescue patch — so
  # `checkout --` makes the worktree clean, after which plain `remove` and `branch -d` both succeed (a
  # strand 0 ahead of origin/main is an ancestor, which is exactly what lower-case `-d` accepts). An
  # instruction whose only route is a denied command sends every session to a dead end.
  _step2="$(awk '/^2\. If SUPERSEDED/,/^3\. If it holds UNIQUE work/' "$STATE/triage/orphan-wt.md")"
  printf '%s\n' "$_step2" | grep -q 'branch -d' \
    && ok "…and step 2 offers the no-force route (restore, plain remove, branch -d), which is the one a session can actually run" \
    || bad "step 2's only route is 'remove --force' / 'branch -D', and --force is denied at the tool layer — the instruction is a dead end (measured 2026-08-22)"
  # ⛔ AND THE ROUTE HAS TO ACTUALLY COMPLETE. `branch -d` checks the branch's UPSTREAM, or HEAD if none is
  # set — never `origin/main`. A strand has no upstream by default, so from the primary checkout `-d` is
  # checked against local `main`, which NOTHING in this daemon fast-forwards (`housekeeping()` only reads
  # `origin/main`). MEASURED 2026-08-22, on the commit that first published the removal block, by running
  # it: local `main` 3078fb0, `origin/main` ddedec6, the branch a verified ancestor of `origin/main` — and
  # `-d` refused with "not fully merged" and hinted at the DENIED `-D`. So the block must point the upstream
  # at `origin/main` first, which both clears the refusal and makes `-d` check the ref (c) is actually about.
  printf '%s\n' "$_step2" | grep -q 'set-upstream-to=origin/main' \
    && ok "…and it points the branch's upstream at origin/main first, without which that final 'branch -d' refuses from the primary checkout and hints at the denied -D" \
    || bad "step 2 ends at 'branch -d' with no upstream set — measured 2026-08-22, that REFUSES from the primary checkout whose local main is behind origin/main, so the route dead-ends one command from the finish"
  [ "$(printf '%s\n' "$_step2" | wc -l | tr -d ' ')" -ge 3 ] \
    && ok "negative control: the step-2 range matched a paragraph too" \
    || bad "the step-2 awk range selected nothing — the check above cannot fail for the right reason"
  # ⛔ AND THE ONE CHECK THAT WOULD HAVE CAUGHT THE FIRST DRAFT OF THIS FIX. Every check above is a PRESENCE
  # test, and a presence test is green over a document that ALSO says the wrong thing. Measured: the first
  # draft of D17 added the cleanup clause to step 3 and ended it with `remove --force` / `branch -D` — so
  # `grep 'worktree remove'` matched, on the forbidden command, and the assertion printed PASS over exactly
  # the defect the entry was opened for. The adversarial review of that diff found it; this check is what
  # makes the machine find it next time. It reads the WHOLE assignment, not one step, because the denied
  # form must not appear as an instruction anywhere in it.
  # ⚠️ Two exemptions, and they are why this greps for the COMMAND rather than the word "force": the
  # assignment legitimately explains that `--force` is denied, and that explanation must survive. So the
  # pattern is the imperative form — a backtick-quoted command — and prose about it is allowed.
  if grep -qE '`git worktree remove (--force|-f)|`git branch -D' "$STATE/triage/orphan-wt.md"; then
    bad "the assignment still gives a DENIED command as an instruction (remove --force / branch -D are in this daemon's own DENY array) — a session following it gets 'Permission … denied' and the strand comes back next cycle"
  else
    ok "…and no step hands a session a command the daemon's own denylist forbids, which is the check the first draft of this fix failed"
  fi
  # ⚠️ NEGATIVE CONTROL for that one: prove the pattern can MATCH, or a typo in the regex reads as a pass
  # over any document at all. Run it against the pre-fix instruction text this fix removed.
  printf '%s\n' '   `git worktree remove --force <worktree>` and `git branch -D <branch>`.' > "$T/denied-form.txt"
  grep -qE '`git worktree remove (--force|-f)|`git branch -D' "$T/denied-form.txt" \
    && ok "negative control: that pattern does match the pre-fix instruction line, so the check above can fail" \
    || bad "the denied-command pattern matches nothing even on the literal pre-fix line — the check above asserts nothing"
  # ---- and the ASSIGNMENT must repeat neither the overclaim nor the omission ------------------------------
  # ⛔ THIS IS THE COPY THAT MATTERS, because resume-prompt.txt tells a session the assignment file is the one
  # to follow — "generated from the daemon and cannot drift from it". Precondition (b) reads it and grants a
  # removal on it, so a `(COMPLETE — tracked and untracked)` line here is the sentence that gets a gitignored
  # artefact deleted. Three claims: it names the class no patch holds, it names the copies that DO exist, and
  # it says so in a strand-specific way rather than as boilerplate that could be printed over anything.
  grep -q 'GITIGNORED' "$STATE/triage/orphan-wt.md" \
    && ok "…and the assignment names the gitignored class, so precondition (b) is not read as 'the backup is whole'" \
    || bad "the assignment's COMPLETE line is unqualified — a session removes a strand on it and takes the only copy of a gitignored artefact with it"
  grep -q 'orphan-wt.ignored-Tools-mutation-out-logic_probe.log' "$STATE/triage/orphan-wt.md" \
    && ok "…and it names the ignored copies by path, so they are filed with the trio rather than found by luck" \
    || bad "the assignment does not name the ignored copies, so a session filing the trio leaves them behind as litter"
  # ⚠️ AND THE FILING INSTRUCTION HAS TO CARRY THEM, or the copies become exactly the stray `.base`/`.status`
  # litter the orphan lister already has to special-case. Step 2 is where the trio is named.
  printf '%s\n' "$_step2" | grep -q 'ignored-' \
    && ok "…and step 2's filing list includes the .ignored-* copies alongside the trio and the .complete marker" \
    || bad "step 2 files the trio and not the .ignored-* copies — they stay in \$STATE/rescue unattached to any decision"
else
  bad "NO TRIAGE ASSIGNMENT for a stranded worktree — it stays 'needs owner' forever, which is the 2026-08-22 complaint"
fi
git -C "$REPO" worktree remove --force "$OW" >/dev/null 2>&1

# ---- [17b] THE FALLBACK: `add -A` FAILING MUST NOT LOSE WHAT THE OLD CODE SAVED --------------------------
# ⛔ THE COMPLETE SNAPSHOT IS ALL-OR-NOTHING AND THE COMMAND IT REPLACED WAS NOT, which made the first
# version of the 2026-08-22 fix a REGRESSION on the one function whose job is never to lose work. Measured:
# a worktree holding real work in a modified tracked file plus ONE unreadable untracked file (`chmod 000`)
# gives `git add -A` rc=128 — "unable to index file" — so the `&&` chain aborted, the else branch deleted the
# patch, and NOTHING was saved, where the old `git diff HEAD` still produced a patch containing the work.
# An unreadable DIRECTORY is only a warning; an unreadable FILE is fatal. So: try complete, fall back to
# tracked-only, and SAY which one happened. This section is the only thing pinning that fallback.
echo "[17b] a failed 'add -A' falls back to a tracked-only patch instead of saving nothing"
echo "0:no:no" > "$CTRL"; reset_repo; dfset 999999; reset_state
rm -rf "$STATE/rescue" "$STATE/triage"
mkdir -p "$REPO/ops/autonomous"
cp "$(cd "$(dirname "$DAEMON")" && pwd)/run-state-lib.sh" "$REPO/ops/autonomous/run-state-lib.sh" 2>/dev/null
OW2="$T/orphan-wt2"; rm -rf "$OW2"
git -C "$REPO" worktree add -q -b auto/orphan-fallback "$OW2" >/dev/null 2>&1
printf 'fallback-tracked-payload-%s\n' "$$" > "$OW2/f.txt"      # real work, in a TRACKED file
git -C "$OW2" add f.txt >/dev/null 2>&1
printf 'unreadable-%s\n' "$$" > "$OW2/poison.bin"               # the thing that makes add -A rc=128
chmod 000 "$OW2/poison.bin"
# Prove the premise: add -A must actually fail here, or this section asserts nothing.
rm -f "$T/probe.idx"
GIT_INDEX_FILE="$T/probe.idx" git -C "$OW2" read-tree HEAD >/dev/null 2>&1
if GIT_INDEX_FILE="$T/probe.idx" git -C "$OW2" add -A >/dev/null 2>&1; then
  skip "add -A succeeded despite an unreadable file (running as root?) — the fallback cannot be exercised"
else
  ok "the premise holds: 'add -A' fails on an unreadable file, so the fallback is reachable"
  L=$(run_daemon 0 6)
  if [ -f "$STATE/rescue/orphan-wt2.patch" ]; then
    ok "a patch was still written — the fallback saved something rather than nothing"
    grep -q "fallback-tracked-payload-$$" "$STATE/rescue/orphan-wt2.patch" \
      && ok "…and it holds the TRACKED work, which is exactly what the old command would have saved" \
      || bad "the fallback patch does not contain the tracked work — strictly worse than the code it replaced"
  else
    bad "NO PATCH AT ALL because add -A failed — this is the regression: the old 'git diff HEAD' saved this work"
  fi
  [ -f "$STATE/rescue/orphan-wt2.complete" ] \
    && bad "a tracked-only fallback was marked COMPLETE — a session may force-remove on it" \
    || ok "…and it is NOT marked complete, so nothing treats it as a full backup"
  grep -q 'PARTIAL rescue' "$L" \
    && ok "…and the log says PARTIAL rather than reporting success" \
    || bad "the fallback is silent about being partial — the 2026-08-22 defect in a new place"
  grep -q 'poison.bin' "$L" \
    && ok "…and it NAMES the untracked file it could not hold, so it can be copied by hand" \
    || bad "the partial rescue does not say WHAT is missing"
fi
chmod 644 "$OW2/poison.bin" 2>/dev/null
git -C "$REPO" worktree remove --force "$OW2" >/dev/null 2>&1
git -C "$REPO" branch -D auto/orphan-fallback >/dev/null 2>&1
git -C "$REPO" branch -D auto/orphan-test >/dev/null 2>&1

# ================= the rescue must not depend on the PROGRESS VERDICT ===================================
# REGRESSION TEST FOR README §Defects D12. [17] above proves the rescue WORKS; it does not prove it RUNS,
# because it drives the daemon with "0:no" — a session that moves nothing — so the run takes the
# no-progress branch, which is the only branch the orphan block was reachable from. The two questions
# "did the fingerprint move" and "is a worktree holding uncommitted work" are independent, and one value
# was answering both.
#
# Measured 2026-08-20: the OWNER landed a commit at 14:40 while a session ran 14:29-16:36. The fingerprint
# moved — correctly, per work_fingerprint()'s own note that an outside push means "the decision surface
# moved, retry now" — so tick() took the progress branch and logged "committed but no item completed".
# That skipped the orphan naming AND the snapshot over 481 uncommitted insertions across 9 files,
# including Sources/Flattener.swift and Tests/main.swift. $STATE/rescue held nothing for it; the only copy
# was in /private/tmp, and the owner wrote the patch by hand.
echo "[18] AN ORPHAN IS RESCUED EVEN WHEN THE FINGERPRINT MOVED (progress branch)"
# ⚠️ THE SEQUENCE IS THE TEST. Two traps, both hit while writing this:
#   (a) the progress line at daemon.sh:422 is guarded by `[ "$BACKOFF" != "$INTERVAL" ]`, so a run that
#       commits on its FIRST cycle logs no "progress" line at all — hence the idle phase first, the same
#       shape [3] uses.
#   (b) if the orphan exists DURING that idle phase, the no-progress branch rescues it and the assertion
#       below passes for the wrong reason — it would be measuring [17] again. So the worktree is created
#       AFTER the idle phase and immediately before the switch to committing, which means any patch found
#       can only have been written by a cycle that read as progress.
echo "0:no" > "$CTRL"; reset_repo; dfset 999999; reset_state
rm -rf "$STATE/rescue"
mkdir -p "$REPO/ops/autonomous"
cp "$(cd "$(dirname "$DAEMON")" && pwd)/run-state-lib.sh" "$REPO/ops/autonomous/run-state-lib.sh" 2>/dev/null \
  || skip "run-state-lib.sh not found beside $DAEMON — the detector cannot be exercised"
OW2="$T/orphan-wt-progress"; rm -rf "$OW2"
P=$(launch 0); sleep 12                      # idle phase: backoff rises, and NO orphan exists yet
git -C "$REPO" worktree add -q -b auto/orphan-progress "$OW2" >/dev/null 2>&1
printf 'progress-branch-payload-%s\n' "$$" > "$OW2/stranded.txt"
git -C "$OW2" add stranded.txt >/dev/null 2>&1
echo "0:yes" > "$CTRL"; sleep 10; stop "$P"; L="$STATE/daemon.log"
# THE PREMISE FIRST, or the assertion after it means nothing.
if grep -q "progress $EM backoff reset" "$L"; then
  ok "a cycle read as PROGRESS after the orphan appeared (the premise holds)"
else
  bad "no progress cycle in the log — fixture broken, so the assertion below is vacuous"
  tail -6 "$L" | sed 's/^/      /'
fi
if [ -f "$STATE/rescue/orphan-wt-progress.patch" ]; then
  ok "a patch was written even though the fingerprint moved"
  grep -q "progress-branch-payload-$$" "$STATE/rescue/orphan-wt-progress.patch" \
    && ok "…and it holds the stranded content" \
    || bad "the patch exists but does not hold the work"
  grep -q 'orphaned:' "$L" && ok "…and the orphan was NAMED, so the owner learns it exists" \
                           || bad "rescued silently — the owner is never told which worktree"
else
  bad "NO PATCH SAVED because the fingerprint moved — an owner commit during a session disables the rescue (D12)"
  tail -6 "$L" | sed 's/^/      /'
fi
git -C "$REPO" worktree remove --force "$OW2" >/dev/null 2>&1
git -C "$REPO" branch -D auto/orphan-progress >/dev/null 2>&1

echo
echo "=================== $PASS passed, $FAIL failed, $SKIP skipped ==================="
[ "$FAIL" = 0 ]
