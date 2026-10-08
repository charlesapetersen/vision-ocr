#!/usr/bin/env bash
# prove-run-tests.sh — run_tests.sh's locking and binary cache (Agent Manager EFFICIENCY-PLAN round
# 2), proved against the REAL run_tests.sh in scratch trees with a fake swiftc (lib-fake-suite.sh), so it
# compiles nothing, runs no suite and touches no real lock or cache:
#   [1] the machine-wide heavy lock wraps ./build/tests and not the three compiles; test.lock (through
#       test-lock.sh run) covers both; a suite queued for the heavy lock keeps test.lock fresh; the holder label
#       is the caller's; the ledger row says how the run went.
#   [2] the cache: a warm tree and a second tree compile nothing; every compiled input, the flags and every
#       toolchain part miss for exactly the binaries they feed; -O stays and -wmo/-Ounchecked never appear; a
#       failed compile, a source edited during a compile, a corrupted entry and an entry with no `ok` are
#       never used; VISIONOCR_TEST_CACHE=off and a cache inside the tree write nothing.
# Each section is then re-run against deliberately broken copies, each of which must turn it red; a copy
# whose anchor is missing or not unique, or that leaves the file unchanged, is a failure, not a pass.
# ~5 min. USAGE: ops/autonomous/tests/prove-run-tests.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OPS="$(cd "$HERE/.." && pwd)"
ROOT="$(cd "$OPS/../.." && pwd)"
RT_REAL="$ROOT/run_tests.sh"; TL_REAL="$OPS/test-lock.sh"; GATE_REAL="$OPS/health-gate.sh"
. "$HERE/lib-fake-suite.sh"
T="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOME="$T/home"; mkdir -p "$HOME"
export MAC_HEAVY_LOCK="$T/heavy/mac-heavy.lock" MAC_HEAVY_POLL=1 VISIONOCR_HEAVY_DELEGATE=""
export AGENT_MANAGER_STATE="$T/am-state" VISIONOCR_MAC_HEAVY="$OPS/mac-heavy-lock.sh"
unset MAC_HEAVY_HELD VISIONOCR_TEST_LOCK_HELD VISIONOCR_SUITE_NOTE VISIONOCR_TEST_LOCK_DIR VISIONOCR_SUITE_LABEL \
      VISIONOCR_TEST_CACHE VISIONOCR_SUITE_STAMPS VISIONOCR_SUITE_STAMP VISIONOCR_SUITE_FRESH VISIONOCR_SUITE_STAMP_TTL
FB="$T/fakebin"; fake_bin "$FB"
# test-lock.sh asks `pgrep -x tests` about the whole machine, where a real suite may be running; this says none.
# It also puts the system directories first on PATH, so the fakes are put back in front of them in every bash
# that starts below it, run_tests.sh included — else the real swiftc would compile the scratch tree.
printf 'pgrep() { return 1; }\nPATH="%s:$PATH"\n' "$FB" > "$T/preload.sh"
# fail MSG — report one failure. A broken copy needs only one, so under FIRST_ONLY the check stops at it.
fail() { echo "$*"; [ -n "${FIRST_ONLY:-}" ] && exit 0; return 0; }
waitfor() { local end=$(( $(date +%s) + $2 )); while [ "$(date +%s)" -lt "$end" ]; do eval "$1" && return 0; sleep 0.2; done; return 1; }

# Each check runs in its own scratch area $X, named by $1, against the run_tests.sh in $RT (and test-lock.sh in
# $TL, health-gate.sh in $GATE), and prints one line per failure — nothing when everything holds.
fresh() {   # $1 name: a scratch area with a tree, a state directory and a log
  X="$T/x-$1-$RANDOM"; mkdir -p "$X"
  fake_tree "$RT" "$X/tree"
  export FAKE_LOG="$X/log" VISIONOCR_STATE="$X/state" VISIONOCR_TEST_LOCK="$X/test.lock" \
         VISIONOCR_SUITE_TIMINGS="$X/timings.tsv"
  : > "$FAKE_LOG"
}
rt() { (cd "${TREE:-$X/tree}" && PATH="$FB:$PATH" ./run_tests.sh) > "$X/out" 2>&1; }   # rc is the suite's
tlrun() { (cd "$X/tree" && PATH="$FB:$PATH" BASH_ENV="$T/preload.sh" bash "$TL" run --label "$1" -- ./run_tests.sh) > "$X/out" 2>&1; }

# ── [1] which lock covers which phase ─────────────────────────────────────────────────────────────────
check_locks() {
  local n hp tp age
  fresh locks
  export VISIONOCR_TEST_CACHE=off VISIONOCR_SUITE_STAMP=off
  tlrun probe; n=$?
  [ "$n" = 0 ] || fail "test-lock.sh run exited $n: $(tail -2 "$X/out" | tr '\n' ' ')"
  [ "$(grep -c '^compile .* heavy=no testlock=yes' "$FAKE_LOG")" = 3 ] \
    || fail "the three compiles were not all outside the heavy lock and inside test.lock: $(grep '^compile' "$FAKE_LOG" | cut -c1-60 | tr '\n' ';')"
  grep -q '^run tests build=[0-9]* heavy=yes label=probe$' "$FAKE_LOG" \
    || fail "./build/tests did not run inside the heavy lock under the caller's label: $(grep '^run' "$FAKE_LOG")"
  grep -q "	probe \[compiled\]	" "$VISIONOCR_SUITE_TIMINGS" || fail "the ledger row does not say [compiled]: $(tail -1 "$VISIONOCR_SUITE_TIMINGS")"
  : > "$FAKE_LOG"; rt
  grep -q '^run tests build=[0-9]* heavy=yes label=suite$' "$FAKE_LOG" || fail "a hand-run ./run_tests.sh ran its suite outside the heavy lock: $(grep '^run' "$FAKE_LOG")"
  # Queued behind another project's holder: test.lock is held and kept fresh while the suite waits.
  : > "$FAKE_LOG"
  MAC_HEAVY_PROJECT=archive-suite "$OPS/mac-heavy-lock.sh" run --label other -- sleep 6 & hp=$!
  waitfor '[ -s "$MAC_HEAVY_LOCK/owner" ]' 5
  tlrun queued & tp=$!
  if waitfor '[ "$(grep -c ^compile "$FAKE_LOG")" = 3 ]' 10; then
    sleep 0.5; touch -t 202001010000 "$VISIONOCR_TEST_LOCK" 2>/dev/null; sleep 2.5
    age=$(( $(date +%s) - $(stat -f %m "$VISIONOCR_TEST_LOCK" 2>/dev/null || echo 0) ))
    [ "$age" -lt 3 ] || fail "test.lock was not kept fresh while the suite waited for the heavy lock (${age}s old)"
    grep -q '^run' "$FAKE_LOG" && fail "the suite ran while another project held the heavy lock"
  else
    fail "the compiles did not finish while another project held the heavy lock (they waited for it?)"
  fi
  wait "$hp"; wait "$tp"
  grep -q '^run tests .*heavy=yes label=queued$' "$FAKE_LOG" || fail "the queued suite never ran: $(tail -3 "$X/out" | tr '\n' ' ')"
  unset VISIONOCR_TEST_CACHE VISIONOCR_SUITE_STAMP
}

# ── [2] the binary cache ──────────────────────────────────────────────────────────────────────────────
check_cache() {
  local l got want base what
  fresh cache; export VISIONOCR_SUITE_STAMP=off
  rt || fail "the cold run failed: $(tail -2 "$X/out" | tr '\n' ' ')"
  [ "$(compiles_since 0)" = "make-plate-fixtures tests visionocr-recognise" ] || fail "cold run compiled: $(compiles_since 0)"
  [ "$(ls "$VISIONOCR_STATE"/test-binary-cache/*/ok 2>/dev/null | wc -l | tr -d ' ')" = 3 ] || fail "the cold run did not leave three cache entries"
  grep '^compile tests ' "$FAKE_LOG" | grep -qE -- '(=| )-O ' || fail "the tests binary is not compiled with -O"
  grep '^compile visionocr-recognise ' "$FAKE_LOG" | grep -qE -- '(=| )-O ' || fail "the helper is not compiled with -O"
  grep -qE -- '-wmo|-whole-module|-Ounchecked' "$FAKE_LOG" && fail "a compile used -wmo or -Ounchecked"
  l=$(log_lines); rt
  [ -z "$(compiles_since "$l")" ] || fail "a warm run compiled: $(compiles_since "$l")"
  tail -n +"$((l+1))" "$FAKE_LOG" | grep -q '^run tests build=1 ' || fail "the warm run did not run the cached binary: $(tail -1 "$FAKE_LOG")"
  base="$X/tree"; cp -R "$base" "$X/base"
  l=$(log_lines); fake_tree "$RT" "$X/other"; TREE="$X/other" rt; TREE=""
  [ -z "$(compiles_since "$l")" ] || fail "a second tree with the same inputs compiled: $(compiles_since "$l")"
  # $1 what · $2 the binaries that must be compiled · rest: a command run in a fresh copy of the base tree
  miss() {
    local what="$1" want="$2" l; shift 2
    rm -rf "$X/v"; cp -R "$X/base" "$X/v"
    ( cd "$X/v" && eval "$@" )
    l=$(log_lines); TREE="$X/v" rt; TREE=""
    [ "$(compiles_since "$l")" = "$want" ] || fail "$what: compiled '$(compiles_since "$l")', wanted '$want'"
  }
  miss "Sources/Model.swift (not in the helper)" "tests" 'echo x >> Sources/Model.swift'
  miss "Sources/Prefs.swift (in the helper)" "tests visionocr-recognise" 'echo x >> Sources/Prefs.swift'
  miss "a new Sources file" "tests" 'echo x > Sources/New.swift'
  miss "Sources/App.swift (compiled into neither)" "" 'echo x >> Sources/App.swift'
  miss "Tests/main.swift" "tests" 'echo x >> Tests/main.swift'
  miss "Helper/main.swift" "visionocr-recognise" 'echo x >> Helper/main.swift'
  miss "a new file in Helper/" "visionocr-recognise" 'echo x > Helper/notes.txt'
  miss "Tools/make-plate-fixtures.swift" "make-plate-fixtures" 'echo x >> Tools/make-plate-fixtures.swift'
  miss "the tests binary's swiftc flags" "tests" \
    "sed -i '' 's/^TESTS_FLAGS=(-O -target/TESTS_FLAGS=(-O -DPROBE -target/' run_tests.sh"
  miss "the plate tool's swiftc flags" "make-plate-fixtures" \
    "sed -i '' 's/^PLATES_FLAGS=(-target/PLATES_FLAGS=(-DPROBE -target/' run_tests.sh"
  for what in FAKE_SWIFT_VERSION=2 FAKE_SDK=28.0 FAKE_SDKPATH=/other.sdk FAKE_BUILD=25H1 FAKE_ARCH=x86_64; do
    l=$(log_lines); env "$what" bash -c 'cd "$1" && PATH="$2:$PATH" ./run_tests.sh' _ "$X/tree" "$FB" >/dev/null 2>&1
    [ "$(compiles_since "$l")" = "make-plate-fixtures tests visionocr-recognise" ] || fail "$what: compiled '$(compiles_since "$l")', wanted all three"
  done
  # Never used: a failed compile, an input edited during the compile, a corrupted entry, an entry with no `ok`.
  export VISIONOCR_TEST_CACHE="$X/c-fail"
  FAKE_FAIL=visionocr-recognise rt && fail "a failed helper compile did not fail the run"
  [ "$(ls "$X"/c-fail/*/ok 2>/dev/null | wc -l | tr -d ' ')" = 1 ] || fail "a failed compile left an entry (or the tests entry is missing): $(ls "$X"/c-fail 2>/dev/null | wc -l | tr -d ' ') entries"
  export VISIONOCR_TEST_CACHE="$X/c-edit"
  FAKE_EDIT_DURING="$X/tree/Tests/main.swift" rt
  ls "$X"/c-edit/*/tests >/dev/null 2>&1 && fail "a tests binary whose sources changed during its compile was cached"
  grep -q 'input changed during the compile' "$X/out" || fail "an input edited during the compile was not reported"
  export VISIONOCR_TEST_CACHE="$X/c-bad"
  rt; for got in "$X"/c-bad/*/tests; do printf 'garbage\n' > "$got"; done
  l=$(log_lines); rt
  [ "$(compiles_since "$l")" = "tests" ] || fail "a corrupted cached binary was used (compiled '$(compiles_since "$l")')"
  grep -q 'does not match its checksum' "$X/out" || fail "a corrupted cached binary was not reported"
  rm -f "$X"/c-bad/*/ok
  l=$(log_lines); rt
  [ "$(compiles_since "$l")" = "make-plate-fixtures tests visionocr-recognise" ] || fail "an entry with no ok file was used (compiled '$(compiles_since "$l")')"
  export VISIONOCR_TEST_CACHE=off
  l=$(log_lines); rt
  [ "$(compiles_since "$l")" = "make-plate-fixtures tests visionocr-recognise" ] || fail "VISIONOCR_TEST_CACHE=off still used the cache"
  export VISIONOCR_TEST_CACHE="$X/tree/cache-inside"
  l=$(log_lines); rt
  [ -e "$X/tree/cache-inside" ] && fail "a cache directory inside the tree was written"
  grep -q 'is inside the tree' "$X/out" || fail "a cache inside the tree was not refused aloud"
  unset VISIONOCR_TEST_CACHE VISIONOCR_SUITE_STAMP
}

# ── run each section on the real files, then on broken copies ─────────────────────────────────────────
RT="$RT_REAL"; TL="$TL_REAL"; GATE="$GATE_REAL"
section() {   # $1 title · $2 check function
  local out; echo "$1"
  out="$("$2")"
  [ -z "$out" ] && ok "every check holds on the real files" || { bad "on the real files:"; echo "$out" | sed 's/^/        /'; }
}
# mutant SECTION-FN FILE-VAR NAME ANCHOR REPLACEMENT — break FILE-VAR's file at a unique anchor; the section must go red.
mutant() {
  local fn="$1" var="$2" name="$3" from="$4" to="$5" src m c out
  src="${!var}"; m="$T/mut-$name"
  c="$(/usr/bin/python3 -c 'import sys; print(open(sys.argv[1]).read().count(sys.argv[2]))' "$src" "$from")"
  [ "$c" = 1 ] || { bad "mutant $name: its anchor occurs $c times, not once — not applied"; return; }
  /usr/bin/python3 -c 'import sys; s=open(sys.argv[1]).read(); open(sys.argv[2],"w").write(s.replace(sys.argv[3],sys.argv[4],1))' "$src" "$m" "$from" "$to"
  chmod +x "$m"
  cmp -s "$src" "$m" && { bad "mutant $name: the file did not change — not applied"; return; }
  out="$(eval "$var=\"\$m\""; FIRST_ONLY=1 "$fn")"
  [ -n "$out" ] && ok "mutant $name is caught ($(echo "$out" | head -1 | cut -c1-90))" || bad "mutant $name SURVIVED"
}

# The heavy-around-everything mutant runs test-lock.sh from $T, so its "$(dirname "$0")" helper must be beside it.
cp "$OPS/mac-heavy-lock.sh" "$T/mac-heavy-lock.sh"
section "[1] the heavy lock wraps the run, not the compiles; test.lock covers both" check_locks
mutant check_locks RT run-unlocked 'if [ -x "$HEAVY" ]; then' 'if false; then'
mutant check_locks TL heavy-around-everything 'VISIONOCR_TEST_LOCK_HELD=1 VISIONOCR_SUITE_NOTE="$_tl_note" "$@"' \
  'VISIONOCR_TEST_LOCK_HELD=1 VISIONOCR_SUITE_NOTE="$_tl_note" "$(dirname "$0")/mac-heavy-lock.sh" run -- "$@"'
mutant check_locks RT no-touch 'MAC_HEAVY_TOUCH="${VISIONOCR_TEST_LOCK_DIR:-}" "$HEAVY"' 'MAC_HEAVY_TOUCH= "$HEAVY"'
mutant check_locks TL no-label 'VISIONOCR_SUITE_LABEL="${LABEL:-suite}"' 'VISIONOCR_SUITE_LABEL=suite'

section "[2] the binary cache" check_cache
mutant check_cache RT key-without-tests-main '"${SOURCES[@]}" Tests/main.swift; }' '"${SOURCES[@]}"; }'
mutant check_cache RT key-without-helper-dir '"${HELPER_SOURCES[@]}" Helper/*; }' '"${HELPER_SOURCES[@]}"; }'
mutant check_cache RT key-without-flags "printf 'format 1\\nbinary %s\\nswiftc %s\\n' \"\$name\" \"\$flags\"" "printf 'format 1\\nbinary %s\\n' \"\$name\""
mutant check_cache RT key-without-swiftc-version "printf 'swiftc --version: %s\\n' \"\$v\"" ':'
mutant check_cache RT key-without-sdk-version "printf 'sdk version: %s\\n' \"\$v\"" ':'
mutant check_cache RT key-without-sdk-path "printf 'sdk path: %s\\n' \"\$v\"" ':'
mutant check_cache RT key-without-macos-build "printf 'macos build: %s\\n' \"\$v\"" ':'
mutant check_cache RT no-checksum '&& [ "$(_sha < "$t")" = "$sum" ] ' ''
mutant check_cache RT no-recheck-after-compile 'if [ "$("$keyfn")" != "$key" ]; then' 'if false; then'
mutant check_cache RT no-inside-tree-guard 'case "$CACHE/" in "$PWD"/*)' 'case "$CACHE/" in /nonexistent/*)'
mutant check_cache RT Ounchecked 'TESTS_FLAGS=(-O -target' 'TESTS_FLAGS=(-Ounchecked -target'
# Not mutated, and why: the architecture line of the toolchain is also inside every binary's -target flag,
# so dropping it is an equivalent mutant (FAKE_ARCH still misses through the flags).

echo ""
echo "=================== $PASS passed, $FAIL failed ==================="
[ "$FAIL" = 0 ]
