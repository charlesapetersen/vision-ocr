#!/usr/bin/env bash
# upkeep hook: between sessions, never while a session of this project runs. What the daemon does at each cycle's
# tail: ops/autonomous/compact-runlog.sh keeps RUN.md's SESSION LOG bounded (archiving the tail beside it).
# Exit nonzero only when the compactor truly aborted (its own contract: a legitimate no-op is 0). Writes:
# $STATE/RUN.md and RUN-SESSION-ARCHIVE.md.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
[ -x "$SCRIPTS/compact-runlog.sh" ] || { echo "upkeep: no compactor at $SCRIPTS/compact-runlog.sh"; exit 0; }
[ -f "$RUN" ] || { echo "upkeep: no $RUN; nothing to compact"; exit 0; }
"$SCRIPTS/compact-runlog.sh" "$RUN" || { rc=$?; echo "upkeep: compact-runlog ABORTED (rc=$rc); $RUN is not being kept bounded"; exit "$rc"; }
exit 0
