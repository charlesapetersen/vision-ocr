#!/usr/bin/env bash
# completed hook: one integer, the items finished so far, for the engine's no-completion streak. The count of
# completed_items() in ops/autonomous/vision-ocr-autonomous.sh: ticked QUEUE.md boxes plus closed BUGS.md
# register entries (a `### ` heading ending in FIXED, WONTFIX or NO DEFECT), so a session whose whole output was
# closing an entry still counts. Read-only. Test: ops/agent/tests/test_hooks.py compares it with the daemon.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
re='^[[:space:]]*[-*][[:space:]]+\[[xX]\]'
q=$(grep -cE "$re" "$QUEUE" 2>/dev/null)
b=$(grep -cE '^###[[:space:]].*—[[:space:]]*\*?\*?(FIXED|WONTFIX|NO DEFECT)' "$REPO/BUGS.md" 2>/dev/null)
case "$q" in ''|*[!0-9]*) q=0 ;; esac
case "$b" in ''|*[!0-9]*) b=0 ;; esac
echo $(( q + b ))
