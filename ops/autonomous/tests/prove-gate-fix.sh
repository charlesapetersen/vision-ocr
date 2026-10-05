#!/usr/bin/env bash
# prove-gate-fix.sh — a red health gate goes to a fix SESSION before the daemon may park (owner, 2026-10-05:
# "Daemon parked again. Set this up so I don't need to tell you this."). Ported from Archive Suite's harness.
#
# WHAT IT PROVES, against the real daemon with a stub gate and a stub claude:
#   [1] a red that survives the retry writes $STATE/gate-fix, does NOT park, and launches a session that finds
#       the request waiting, naming the step's own gate command and carrying the log's tail;
#   [2] the next GREEN gate retires the request and its attempt count;
#   [3] each fix session that commits and leaves the gate red counts an attempt, and the run parks only after
#       VISIONOCR_GATEFIX_MAX of them, with a park note that says so;
#   [4] a fix session that commits nothing does not burn an attempt, and the gate is not re-run over an
#       unchanged tree;
#   [5] a restart forgives the attempt count but keeps the request.
# Sandboxed like prove-daemon.sh (own HOME, STATE and git repo; host commands stubbed through BASH_ENV, because
# the daemon puts the system directories ahead of PATH). It never runs the suite, ./build.sh or the real gate.
# USAGE:  ops/autonomous/tests/prove-gate-fix.sh [path/to/vision-ocr-autonomous.sh]
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DAEMON="${1:-$HERE/../vision-ocr-autonomous.sh}"
[ -f "$DAEMON" ] || { echo "no daemon at $DAEMON"; exit 2; }
T="$(mktemp -d)"
reap() {
  [ -f "$T/daemon.pids" ] || return 0
  while read -r p; do case "$(ps -p "$p" -o command= 2>/dev/null)" in *"$DAEMON"*) kill -9 "$p" 2>/dev/null ;; esac; done < "$T/daemon.pids"
}
trap 'reap; rm -rf "$T"' EXIT
trap 'reap; rm -rf "$T"; exit 143' TERM INT HUP
PASS=0; FAIL=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
EM="$(printf '\xe2\x80\x94')"

export HOME="$T/home"; mkdir -p "$HOME/Desktop"
PARKNOTE="$HOME/Desktop/VISION-OCR-RUN-PARKED.txt"
BIN="$T/bin"; mkdir -p "$BIN"
for c in osascript launchctl caffeinate security curl; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/%s.log"\ncat >/dev/null 2>&1 </dev/null\nexit 0\n' "$c" "$T" "$c" > "$BIN/$c"; chmod +x "$BIN/$c"
done
cat > "$BIN/df" <<'STUB'
#!/bin/sh
echo "Filesystem 1M-blocks Used Available Capacity iused ifree %iused Mounted on"
echo "/dev/disk1 1000000 1000 999999 1% 1 1 0% /"
STUB
chmod +x "$BIN/df"
export PATH="$BIN:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cat > "$T/preload.sh" <<PRE
df()         { "$BIN/df" "\$@"; }
curl()       { "$BIN/curl" "\$@"; }
osascript()  { "$BIN/osascript" "\$@"; }
launchctl()  { "$BIN/launchctl" "\$@"; }
caffeinate() { "$BIN/caffeinate" "\$@"; }
security()   { "$BIN/security" "\$@"; }
PRE

REPO="$T/repo with space"; mkdir -p "$REPO/ops/autonomous"
git -C "$REPO" init -q -b main; git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
QUEUE="$REPO/ops/autonomous/QUEUE.md"
printf '# Autonomous work queue\n\n- [ ] **item-one** %s stub item\n' "$EM" > "$QUEUE"
echo seed > "$REPO/f"; git -C "$REPO" add -A; git -C "$REPO" commit -qm seed
git -C "$REPO" update-ref refs/remotes/origin/main HEAD
RUN="$T/RUN.md"; printf 'RUN STATUS: IN_PROGRESS %s prove-gate-fix\n\n## SESSION LOG\n' "$EM" > "$RUN"
STATE="$T/state"; mkdir -p "$STATE"
printf 'STUB PROMPT %s this harness never runs a real session.\n' "$EM" > "$STATE/resume-prompt.txt"
printf '#!/bin/sh\necho STATUS-OK\n' > "$T/status-stub.sh"; chmod +x "$T/status-stub.sh"

# The stub gate: $GATECTL holds "red" or "green"; every run is counted in $GATERUNS. Its red names a step whose
# `step` line is in this very file, so the request can quote the step's command the way it does the real gate's.
GATECTL="$T/gatectl"; GATERUNS="$T/gate.runs"; GATE="$T/health-gate.sh"
cat > "$GATE" <<STUB
#!/bin/bash
git -C "$REPO" rev-parse HEAD >> "$GATERUNS"     # which tree this gate run would have tested
if [ "\$(cat "$GATECTL")" = red ]; then echo "── tools-compile ──"; echo "  ✗ tools-compile (rc=1)"; echo "HEALTH GATE: RED $EM tools-compile"; exit 1; fi
echo "HEALTH GATE: GREEN"; exit 0
step tools-compile Tools/check-tools-compile.sh
STUB
chmod +x "$GATE"

# The stub claude: records whether the request was waiting, and pushes a commit when $SESSCTL says so (the way
# a real session lands work: origin/main moves, the primary checkout's HEAD does not).
SESSCTL="$T/sessctl"; SEEN="$T/seen"
cat > "$T/claude" <<STUB
#!/usr/bin/env bash
[ -f "$STATE/gate-fix" ] && { echo "saw \$VISIONOCR_HEAD_ITEM" >> "$SEEN"; cp "$STATE/gate-fix" "$T/request.copy"; }
if [ "\$(cat "$SESSCTL")" = commit ]; then
  _c=\$(git -C "$REPO" commit-tree "\$(git -C "$REPO" rev-parse 'HEAD^{tree}')" -p "\$(git -C "$REPO" rev-parse refs/remotes/origin/main)" -m "fix \$\$.\$RANDOM")
  git -C "$REPO" update-ref refs/remotes/origin/main "\$_c"
fi
exit 0
STUB
chmod +x "$T/claude"

launch() {
  VISIONOCR_LABEL=provegatefix VISIONOCR_REPO="$REPO" VISIONOCR_STATE="$STATE" \
  VISIONOCR_RUN="$RUN" VISIONOCR_QUEUE="$QUEUE" VISIONOCR_CLAUDE="$T/claude" \
  VISIONOCR_INTERVAL=1 VISIONOCR_MAXBACKOFF=2 VISIONOCR_IDLE_STOP=0 VISIONOCR_HB_POLL=1 \
  VISIONOCR_MAXRUN=60 VISIONOCR_BUDGET=1 VISIONOCR_MINFREE_MB=10 VISIONOCR_MAX_NOCOMPLETE=0 \
  VISIONOCR_GATE_EVERY=1 VISIONOCR_GATE_CMD="$GATE" VISIONOCR_GATE_MAXRUN=30 \
  VISIONOCR_GATEFIX_MAX="${GFMAX:-3}" VISIONOCR_GATEFIX_IDLE_MAX="${GFIDLE:-99}" \
  VISIONOCR_STATUS_CMD="$T/status-stub.sh" \
  VISIONOCR_COMPACTOR="$T/none" VISIONOCR_TEST_LOCK="$STATE/test.lock" BASH_ENV="$T/preload.sh" \
    bash "$DAEMON" >> "$T/daemon.out" 2>&1 &
  local pid=$!; echo "$pid" >> "$T/daemon.pids"; echo "$pid"
}
stop() { kill -TERM "$1" 2>/dev/null; wait "$1" 2>/dev/null; sleep 1; rm -f "$STATE/engine.lock"; }   # a killed daemon leaves its lock
# Poll for a condition rather than sleep a fixed time, so a loaded machine (this runs inside the real gate) is
# slower but not red. $1 = a shell condition, $2 = deadline in seconds.
waitfor() { local end=$(( $(date +%s) + $2 )); while [ "$(date +%s)" -lt "$end" ]; do eval "$1" && return 0; sleep 0.5; done; return 1; }
reset() {
  : > "$STATE/daemon.log"; : > "$GATERUNS"
  rm -f "$STATE"/gate-fix* "$STATE/last-gate" "$STATE/last-gate.log" "$STATE/idle.since" "$STATE/engine.lock" \
        "$STATE/nocomplete.count" "$SEEN" "$T/request.copy" "$PARKNOTE"
  git -C "$REPO" merge --ff-only -q refs/remotes/origin/main >/dev/null 2>&1
  git -C "$REPO" update-ref refs/remotes/origin/main HEAD
}
L="$STATE/daemon.log"
runs() { wc -l < "$GATERUNS" | tr -d ' '; }
nseen() { grep -c 'saw gate-fix' "$SEEN" 2>/dev/null || echo 0; }

echo "[1] a red that survives the retry goes to a fix session, not a park"
reset; echo red > "$GATECTL"; echo none > "$SESSCTL"; P=$(launch); waitfor '[ -s "$SEEN" ]' 30; stop "$P"
grep -q 'gate fix: handed the failing gate step(s) (tools-compile)' "$L" && ok "handed to a session" || bad "not handed: $(grep -E 'gate|PARK' "$L" | tail -3)"
grep -q 'PARKED' "$L" && bad "parked on the first red" || ok "did not park"
grep -q 'saw gate-fix' "$SEEN" 2>/dev/null && ok "the session found the request, with gate-fix as its head item" \
  || bad "the session never saw the request: $(cat "$SEEN" 2>/dev/null)"
grep -q 'tools-compile: step tools-compile Tools/check-tools-compile.sh' "$T/request.copy" 2>/dev/null \
  && ok "the request names the step's own command" || bad "request lacks the step command: $(head -5 "$T/request.copy" 2>/dev/null)"
grep -q "HEALTH GATE: RED $EM tools-compile" "$T/request.copy" 2>/dev/null && ok "the request carries the log's tail" || bad "no log tail in the request"

echo "[2] the next GREEN gate retires the request"
echo green > "$GATECTL"; P=$(launch); waitfor 'grep -q "fix request is retired" "$L"' 30; stop "$P"
grep -q "gate fix: the gate is GREEN $EM the fix request is retired" "$L" && ok "retired on green" || bad "not retired: $(tail -4 "$L")"
[ ! -f "$STATE/gate-fix" ] && [ ! -f "$STATE/gate-fix-tries" ] && ok "request and count removed" || bad "request or count left behind"

echo "[3] committed fixes that leave it red count, and the run parks after GATEFIX_MAX of them"
reset; echo red > "$GATECTL"; echo commit > "$SESSCTL"; P=$(GFMAX=2 launch); waitfor 'grep -q PARKED "$L"' 90; stop "$P"
grep -q 'attempt 1/2' "$L" && grep -q 'attempt 2/2' "$L" && ok "two attempts handed over" || bad "attempts: $(grep -o 'attempt [0-9]/[0-9]' "$L" | tr '\n' ' ')"
grep -q 'PARKED' "$L" && ok "parked after the attempts were spent" || bad "never parked: $(grep -E 'gate fix|PARK' "$L" | tail -3)"
grep -q 'attempt 3/2' "$L" && bad "handed over a third attempt past the limit" || ok "no attempt past the limit"
grep -q 'fix sessions committed changes and the gate is still red' "$PARKNOTE" 2>/dev/null \
  && ok "the park note says fix sessions were tried" || bad "park note does not say so"
[ "$(tail -1 "$GATERUNS")" = "$(git -C "$REPO" rev-parse refs/remotes/origin/main)" ] \
  && ok "the gate tested the pushed fix: the primary was fast-forwarded to origin/main first" \
  || bad "the last gate ran on $(tail -1 "$GATERUNS" | cut -c1-7), not on the pushed fix $(git -C "$REPO" rev-parse --short refs/remotes/origin/main)"
[ ! -f "$STATE/gate-fix" ] && ok "the park removed the request" || bad "the request outlived the park"

echo "[4] a fix session that commits nothing does not burn an attempt, and the gate is not re-run"
reset; echo red > "$GATECTL"; echo none > "$SESSCTL"; P=$(GFMAX=1 launch); waitfor '[ "$(nseen)" -ge 3 ]' 40; stop "$P"
grep -q 'no commit since it was written' "$L" && ok "an empty session goes straight back to a fix session" || bad "not reported: $(grep 'gate fix' "$L" | tail -2)"
[ "$(runs)" = 2 ] && ok "the gate ran twice (first try and retry) and not again over the same tree" || bad "gate ran $(runs) times"
[ "$(nseen)" -ge 3 ] && ok "fix sessions kept being launched ($(nseen))" || bad "fix sessions: $(nseen)"
grep -q 'PARKED' "$L" && bad "parked although no fix was attempted" || ok "no park without a committed attempt"

echo "[5] a restart forgives the attempt count but keeps the request"
[ -f "$STATE/gate-fix" ] || bad "no request left by [4] — this section is vacuous"
# The gate is made not due (last-gate = HEAD), so no red can write a fresh request: a session sees one only if
# the restart left the old one in place. Without this a deleted request was rewritten before anything looked.
: > "$L"; : > "$GATERUNS"; rm -f "$SEEN"; git -C "$REPO" rev-parse HEAD > "$STATE/last-gate"
P=$(GFMAX=1 launch); waitfor '[ -s "$SEEN" ]' 30; stop "$P"
[ "$(nseen)" -ge 1 ] && [ "$(runs)" = 0 ] && ok "the request survived the restart: a session took it with no gate run to rewrite it" \
  || bad "the restart deleted the request (sessions that saw it: $(nseen), gate runs: $(runs))"
rm -f "$STATE/last-gate"
: > "$L"; echo 2 > "$STATE/gate-fix-tries"; P=$(GFMAX=1 launch); waitfor 'grep -q "attempt [0-9]/1" "$L"' 30; stop "$P"
grep -q 'attempt 1/1' "$L" && ok "the count started again from one" || bad "count not forgiven: $(tail -6 "$L")"

echo "[6] fix sessions that keep committing nothing park the run after VISIONOCR_GATEFIX_IDLE_MAX of them"
reset; echo red > "$GATECTL"; echo none > "$SESSCTL"; P=$(GFIDLE=2 launch); waitfor 'grep -q PARKED "$L"' 60; stop "$P"
grep -q 'PARKED (health gate RED .* 2 fix sessions committed nothing' "$L" && ok "parked, saying the fix sessions committed nothing" \
  || bad "no idle park: $(grep -E 'gate fix|PARK' "$L" | tail -3)"
[ "$(nseen)" = 2 ] && ok "two fix sessions ran, both without a commit, then it parked" || bad "fix sessions: $(nseen)"
[ ! -f "$STATE/gate-fix" ] && ok "the park removed the request" || bad "the request outlived the park"

echo "[7] a primary checkout with uncommitted changes is never moved"
reset; echo "owner's edit" > "$REPO/f"; echo red > "$GATECTL"; echo commit > "$SESSCTL"
P=$(GFMAX=2 launch); waitfor 'grep -q "not a clean main behind origin/main" "$L"' 40; stop "$P"
grep -q 'not a clean main behind origin/main' "$L" && ok "it said it was gating the checkout as it stands" || bad "no word about the dirty checkout: $(grep 'gate fix' "$L" | tail -2)"
[ "$(cat "$REPO/f")" = "owner's edit" ] && ok "the uncommitted edit is untouched" || bad "the edit was lost: $(cat "$REPO/f")"
[ "$(git -C "$REPO" rev-parse HEAD)" != "$(git -C "$REPO" rev-parse refs/remotes/origin/main)" ] && ok "HEAD was not moved" || bad "HEAD was fast-forwarded over a dirty tree"
git -C "$REPO" checkout -q -- f

echo ""
echo "=================== $PASS passed, $FAIL failed ==================="
[ "$FAIL" = 0 ]
