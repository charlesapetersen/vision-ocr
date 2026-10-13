#!/usr/bin/env bash
# prove-concurrent-suites.sh — two full suites at once, from two trees, and neither touches the other's files.
#
# concurrent-suites (cs-paths). Copies the given tree (default: the one this script is in) twice, tracked and
# untracked-but-not-ignored files as they are on disk, and starts ./run_tests.sh in both at the same moment,
# bypassing test.lock and the machine-wide heavy lock so the two run phases really overlap. Then it checks:
#   * both suites pass;
#   * their preferences domains, temporary directories and run-report directories are disjoint (each suite
#     prints them on its `suite paths:` line);
#   * neither wrote ~/Library/Logs/VisionOCR or ~/Library/Preferences/tests.plist, the shared paths of old;
#   * while both run, ops/ocrlab/run-guarded.sh refuses (exit 75, "a test suite is running"), and test-lock.sh
#     status reads them as two isolated suites; and run-guarded still refuses while only one runs.
#
# HEAVY: two suites at once, about 6-10 minutes. Run it under the heavy lock, since it bypasses the one inside
# run_tests.sh:
#   ops/autonomous/mac-heavy-lock.sh run --label prove-concurrent -- ops/autonomous/tests/prove-concurrent-suites.sh
# Do not run it beside another suite.
#
# MUTANT=shared-reports points both copies' report directory at one fixed path, the shape before cs-paths;
# the harness must then fail. EXPECTED RESULT: 11 passed, 0 failed (one skip arm, which the stagger makes rare:
# if both suites end within the same poll, the one-suite run-guarded check is a SKIP).
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "${1:-$HERE/../../..}" && pwd)"
[ -x "$SRC/run_tests.sh" ] || { echo "no run_tests.sh in $SRC"; exit 2; }
T="$(mktemp -d /private/tmp/prove-concurrent.XXXXXX)"
A="$T/a"; B="$T/b"
PIDS=""
# Each copy runs in a process group of its own (set -m), so a cleanup kills run_tests.sh and its `tests`
# too, not only the subshell, before the trees they run in are deleted.
set -m
_cleanup() { for p in $PIDS; do kill -TERM -- "-$p" 2>/dev/null; done; sleep 1; for p in $PIDS; do kill -KILL -- "-$p" 2>/dev/null; done; rm -rf "$T"; [ -n "${MUTANT:-}" ] && rm -rf /private/tmp/visionocr-shared-reports; }
trap _cleanup EXIT
trap '_cleanup; exit 130' INT
trap '_cleanup; exit 143' TERM

PASS=0; FAIL=0; SKIP=0
ok()   { printf '  PASS %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  SKIP %s\n' "$1"; SKIP=$((SKIP+1)); }

if pgrep -x tests >/dev/null 2>&1; then
  echo "a suite is already running (pgrep -x tests: $(pgrep -x tests | tr '\n' ' ')); not adding two more"; exit 2
fi

for d in "$A" "$B"; do
  mkdir -p "$d"
  ( cd "$SRC" && git ls-files -z --cached --others --exclude-standard | xargs -0 tar -cf - 2>/dev/null ) \
    | ( cd "$d" && tar -xf - ) || { echo "could not copy $SRC to $d"; exit 2; }
done
case "${MUTANT:-}" in
  '') ;;
  shared-reports)
    for d in "$A" "$B"; do
      sed -i '' 's|^RunReport.directory = tmp.appendingPathComponent("run-reports", isDirectory: true)$|RunReport.directory = URL(fileURLWithPath: "/private/tmp/visionocr-shared-reports", isDirectory: true)|' \
        "$d/Tests/main.swift"
      grep -q 'visionocr-shared-reports' "$d/Tests/main.swift" || { echo "mutant did not apply in $d"; exit 2; }
    done ;;
  *) echo "unknown MUTANT '$MUTANT'"; exit 2 ;;
esac

LOGS="$HOME/Library/Logs/VisionOCR"
SHARED_PLIST="$HOME/Library/Preferences/tests.plist"
logs_before="$(ls -la "$LOGS" 2>/dev/null)"
plist_before="$(shasum -a 256 "$SHARED_PLIST" 2>/dev/null)"

# Both at once. The stamp is off so neither can skip, and VISIONOCR_MAC_HEAVY names nothing so neither waits on
# the heavy lock; the binary cache stays on, as it is for every real run.
for d in "$A" "$B"; do
  ( cd "$d" && VISIONOCR_SUITE_FRESH=1 VISIONOCR_SUITE_STAMP=off VISIONOCR_MAC_HEAVY=/nonexistent \
      ./run_tests.sh > "$d.log" 2>&1; echo $? > "$d.rc" ) &
  PIDS="$PIDS $!"
  # B starts STAGGER seconds after A, so A ends first and run-guarded can be asked about one suite alone;
  # the two run phases still overlap for nearly all of their length.
  [ "$d" = "$A" ] && sleep "${STAGGER:-30}"
done

# The suite's pid, from its `suite paths:` line (tmp=…/mac-ocr-gui-tests-<pid>).
suite_pid() { sed -n 's/^suite paths: .*mac-ocr-gui-tests-\([0-9][0-9]*\) .*/\1/p' "$1.log" | head -1; }
PA=""; PB=""; w=0
while [ "$w" -lt 600 ]; do
  PA="$(suite_pid "$A")"; PB="$(suite_pid "$B")"
  [ -n "$PA" ] && [ -n "$PB" ] && break
  [ -f "$A.rc" ] && [ -f "$B.rc" ] && break
  sleep 2; w=$(( w + 2 ))
done
echo "suites: a=${PA:-none} b=${PB:-none}"

if [ -n "$PA" ] && [ -n "$PB" ] && kill -0 "$PA" 2>/dev/null && kill -0 "$PB" 2>/dev/null; then
  ok "both suites are in their run phase at the same time (pids $PA $PB)"
  OUT="$("$SRC/ops/ocrlab/run-guarded.sh" -- /usr/bin/true 2>&1)"; RC=$?
  [ "$RC" = 75 ] && printf '%s' "$OUT" | grep -q 'a test suite is running' \
    && ok "run-guarded refuses while both run (75)" || bad "run-guarded with two suites: rc=$RC '$OUT'"
  OUT="$(bash "$SRC/ops/autonomous/test-lock.sh" status 2>&1)"
  printf '%s' "$OUT" | grep -q '2 isolated suites at once' \
    && ok "test-lock.sh reads them as two isolated suites" || bad "test-lock status: '$(printf '%s' "$OUT" | grep '^suite')'"
else
  bad "the two suites never ran at the same time (a=${PA:-none} b=${PB:-none})"
  bad "run-guarded not checked with two suites"
  bad "test-lock status not checked with two suites"
fi

# One left: run-guarded must still refuse.
while kill -0 "$PA" 2>/dev/null && kill -0 "$PB" 2>/dev/null; do sleep 1; done
if kill -0 "$PA" 2>/dev/null || kill -0 "$PB" 2>/dev/null; then
  OUT="$("$SRC/ops/ocrlab/run-guarded.sh" -- /usr/bin/true 2>&1)"; RC=$?
  if kill -0 "$PA" 2>/dev/null || kill -0 "$PB" 2>/dev/null; then
    [ "$RC" = 75 ] && ok "run-guarded refuses while one of them still runs (75)" || bad "run-guarded with one suite: rc=$RC '$OUT'"
  else
    skip "the second suite ended during the run-guarded check"
  fi
else
  skip "both suites ended within the same second; run-guarded with one suite not checked"
fi
wait

for d in "$A" "$B"; do
  n="$(basename "$d")"
  rc="$(cat "$d.rc" 2>/dev/null)"
  line="$(grep -E '^[0-9]+/[0-9]+ passed$' "$d.log" | tail -1)"
  if [ "$rc" = 0 ] && [ -n "$line" ] && [ "${line%%/*}" = "$(echo "$line" | sed 's|^[0-9]*/\([0-9]*\) passed$|\1|')" ]; then
    ok "suite $n passed: $line"
  else
    bad "suite $n: rc=${rc:-?} '${line:-no pass line}' (log tail: $(grep -E 'FAIL' "$d.log" | head -5 | tr '\n' '|'))"
  fi
done

# domain= and tmp= carry the pid, so they differ by construction; reports= is what the mutant moves. The checks
# on ~/Library below are the behavioural ones, and the mutant also turns each suite's own report check red.
field() { sed -n "s/^suite paths: .*$2=\([^ ]*\).*/\1/p" "$1.log" | head -1; }
for f in domain tmp reports; do
  va="$(field "$A" "$f")"; vb="$(field "$B" "$f")"
  [ -n "$va" ] && [ -n "$vb" ] && [ "$va" != "$vb" ] \
    && ok "$f differs: $va | $vb" || bad "$f is shared or missing: '$va' | '$vb'"
done
ra="$(field "$A" reports)"; rb="$(field "$B" reports)"
case "$ra$rb" in *"/Library/Logs/"*) bad "a report directory is under ~/Library/Logs" ;; *) : ;; esac
[ "$(ls -la "$LOGS" 2>/dev/null)" = "$logs_before" ] \
  && ok "~/Library/Logs/VisionOCR is untouched" || bad "~/Library/Logs/VisionOCR changed during the runs"
[ "$(shasum -a 256 "$SHARED_PLIST" 2>/dev/null)" = "$plist_before" ] \
  && ok "~/Library/Preferences/tests.plist is untouched" || bad "tests.plist changed during the runs"

echo
echo "=================== $PASS passed, $FAIL failed, $SKIP skipped ==================="
[ "$FAIL" = 0 ]
