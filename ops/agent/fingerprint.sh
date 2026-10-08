#!/usr/bin/env bash
# fingerprint hook: what counts as progress state, printed for the engine to hash. The first four parts are
# work_fingerprint() in ops/autonomous/vision-ocr-autonomous.sh, in its order (HEAD, the origin/main tip, the
# RUN STATUS line of $STATE/RUN.md, the QUEUE.md checkbox lines). The fifth is new: RUN.md's `## FOCUS` section,
# which the README says wakes the daemon and the daemon's fingerprint never covered (scoping survey,
# 2026-10-08). Read-only. Test: ops/agent/tests/test_hooks.py checks the first four against the daemon function.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
git -C "$REPO" rev-parse HEAD 2>/dev/null || echo no-head
git -C "$REPO" rev-parse --verify --quiet refs/remotes/origin/main 2>/dev/null || echo no-remote-tip
grep -m1 '^RUN STATUS:' "$RUN" 2>/dev/null || echo no-status
grep -E '^[[:space:]]*[-*][[:space:]]+\[[ xX]\]' "$QUEUE" 2>/dev/null || echo no-queue
echo "--- FOCUS"
awk '/^## FOCUS/{f=1;next} f && /^## /{exit} f' "$RUN" 2>/dev/null
exit 0
