#!/usr/bin/env bash
# precheck hook: can the project run at all? The refusals ops/autonomous/daemon.sh makes at start, read-only:
# the claude CLI (outside ~/Desktop: a launchd bash cannot exec anything under it), the resume prompt, RUN.md in
# the state folder, QUEUE.md and its resolver, a queue the resolver finds drained (exit 3) or cannot parse
# (exit 2), and a RUN STATUS that says COMPLETE (matched as daemon.sh matches it). Exit 1 with the reason to
# refuse, else 0. What daemon.sh only warns about (all items blocked, core.hooksPath, a busy suite lock) is not a
# refusal and is not repeated here.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CLAUDE="${AGENT_CLAUDE:-$HOME/.local/bin/claude}"
NEXT="$SCRIPTS/next-item.sh"
refuse() { echo "$*"; exit 1; }
[ -x "$CLAUDE" ] || refuse "claude CLI not executable at $CLAUDE (it must live outside ~/Desktop for launchd)"
[ -f "$REPO/ops/autonomous/resume-prompt.txt" ] || refuse "resume prompt missing: $REPO/ops/autonomous/resume-prompt.txt"
[ -f "$RUN" ] || refuse "no run-state file at $RUN; copy ops/autonomous/RUN.md.template there and edit its ## FOCUS"
[ -f "$QUEUE" ] || refuse "queue missing: $QUEUE"
[ -x "$NEXT" ] || refuse "queue resolver missing or not executable: $NEXT"
"$NEXT" "$REPO" >/dev/null 2>&1; nrc=$?
case "$nrc" in
  3) refuse "the queue is drained: every item in $QUEUE is [x]; add work or set RUN STATUS: COMPLETE" ;;
  2) refuse "$NEXT could not parse $QUEUE (exit 2): a malformed queue, not an empty one" ;;
esac
if grep -m1 '^RUN STATUS:' "$RUN" 2>/dev/null | cut -c1-90 | grep -q 'COMPLETE'; then
  refuse "RUN STATUS is COMPLETE in $RUN; set it to IN_PROGRESS to run again"
fi
exit 0
