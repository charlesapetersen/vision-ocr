#!/bin/bash
# Runs the argument-construction and end-to-end OCR checks.
#
# Compiles the view sources too, even though nothing instantiates a view. They
# are excluded from nothing else, so a change that broke only SettingsView or
# ContentView used to pass a full green test run and fail at ./build.sh —
# which is exactly the wrong order to find out. App.swift stays out: its @main
# would collide with Tests/main.swift's top-level code.
set -euo pipefail

cd "$(dirname "$0")"

BIN="build/tests"
HELPER="build/visionocr-recognise"
PLATES="build/make-plate-fixtures"
mkdir -p build

# Every source except App.swift, by glob rather than by name. It used to be a
# hand-written list, so a new file compiled into the app (build.sh globs) and
# not into the suite — the checks would go green over code they had never seen.
# App.swift stays out because its @main collides with Tests/main.swift.
SOURCES=()
for f in Sources/*.swift; do
  [ "$(basename "$f")" = "App.swift" ] && continue
  SOURCES+=("$f")
done

# ⛔ `-O` IS LOAD-BEARING ON THIS BINARY AND ON $HELPER — DO NOT DROP IT. There was no optimization flag
# here until 2026-08-24, so the suite ran `Flattener`'s pixel loops at `-Onone` while the shipped app has
# always run them optimized (`build.sh` passes `-O` at :47/:68/:96/:104 — four lanes over two binaries,
# app and helper). Measured that day, same commit `8d00504`, same 1,247 checks, same machine, normal
# scheduling band: 709 s -> 225 s total, and the TEST PHASE alone 618 s -> 103 s = 6.0x. Compile grew
# 91 s -> 122 s (~24 s of that is this binary, ~7 s the helper), which is why the total is 3.15x and not
# 6x. Compile is now 54% of the run, so THE NEXT WIN HERE IS BUILD CACHING, NOT MORE OPTIMIZATION.
# $HELPER at `-O` also makes the suite test what actually ships, matching `build.sh:104`.
#
# ⛔ NEVER `-Ounchecked` — and NOT for the reason it looks like. The R24/A7.1 probe family at lines 15-22
# DISCARDS its results (`_ = Flattener.hasDigitalText(url)`, …) and the check at `Tests/main.swift:10895`
# is "the hostile conversions do not take the process down": these checks pin GUARDS THAT PREVENT a trap,
# they do not assert that one happens. So under `-Ounchecked` a regression that removed a guard would
# WRAP SILENTLY instead of trapping and that check would pass VACUOUSLY — the failure mode is a green
# suite, not a red one. `-Ounchecked` also deletes `Sources/JBIG2.swift:235`'s `precondition`.
# ⛔ AND NEVER `-wmo`, which is the obvious next "make it faster" step. `swiftc -O` here emits
# `-primary-file` per source (verified with `-driver-print-jobs`), i.e. NO whole-module optimization, and
# that is the only thing stopping `Tests/main.swift` from inlining `Sources/` bodies. Add `-wmo` and those
# discarded probe calls become dead-code-eliminable, so R24 could go green without running what it names.
# ⚠️ The one check `-O` could genuinely have broken is the R40 parity block (`Tests/main.swift:5609` and
# a second copy at :5697): it compares `confidence` and all four bounding-box components with EXACT float
# inequality between TWO SEPARATELY COMPILED binaries, whose inlining decisions differ. Verified safe
# rather than assumed: Swift enables no fast-math, and an FMA detector returns bit-identical results at
# `-Onone`, `-O` and `-Ounchecked` on Apple Swift 6.3.3. Suite was 1,247/1,247 with no skips under `-O`.
TARGET="$(uname -m)-apple-macos13.0"
TESTS_FLAGS=(-O -target "$TARGET")
HELPER_FLAGS=(-O -target "$TARGET")
PLATES_FLAGS=(-target "$TARGET")
# The recognition helper's sources: Recogniser's own closure, as build.sh builds it.
HELPER_SOURCES=(Sources/Prefs.swift Sources/Runner.swift Sources/Recogniser.swift
  Sources/SearchableWriter.swift Sources/Flattener.swift Sources/JBIG2.swift Helper/main.swift)

# ── The compiled-binary cache (Agent Manager EFFICIENCY-PLAN round 2) ─────────────────────────────────
# CACHE. Each of the three binaries is keyed by the sha-256 of everything that goes into compiling it: the
# file names and contents it compiles, its swiftc flags, `swiftc --version`, the SDK version and path, the
# architecture and the macOS build. A key that matches a finished entry is copied into build/ instead of
# compiled, so an unchanged tree in any worktree skips the ~2 minutes of swiftc. Entries live in the state
# directory, outside every tree, so nothing here can be staged. An entry is written under a temporary name
# and renamed, and its `ok` file (written last) records the binary's own sha-256, checked on every use. The
# key is computed again after the compile and the entry is not written if a source changed meanwhile.
# VISIONOCR_TEST_CACHE=off compiles every time and writes nothing.
STATE_DIR="${VISIONOCR_STATE:-$HOME/.local/state/visionocr-autonomous}"
CACHE="${VISIONOCR_TEST_CACHE:-$STATE_DIR/test-binary-cache}"
CACHE_ON=1; [ "$CACHE" = off ] && CACHE_ON=0
# A cache directory inside this tree could be staged; refuse it rather than write there.
case "$CACHE/" in "$PWD"/*) echo "run_tests: the binary cache $CACHE is inside the tree — not using it." >&2; CACHE_ON=0 ;; esac

# _note WORD — tell test-lock.sh how this run went (compiled / cache-hit), for its timing ledger.
_note() { [ -n "${VISIONOCR_SUITE_NOTE:-}" ] && printf '%s\n' "$1" > "$VISIONOCR_SUITE_NOTE" 2>/dev/null; return 0; }
_sha() { shasum -a 256 | cut -c1-64; }

# The toolchain, once. If any part cannot be read, the cache is off: a key missing a part
# could match across a change to that part.
TOOLCHAIN=""
_toolchain() {
  local v
  v="$(swiftc --version 2>&1)" || return 1;           printf 'swiftc --version: %s\n' "$v"
  v="$(xcrun --show-sdk-version 2>/dev/null)" && [ -n "$v" ] || return 1; printf 'sdk version: %s\n' "$v"
  v="$(xcrun --show-sdk-path 2>/dev/null)" && [ -n "$v" ] || return 1;    printf 'sdk path: %s\n' "$v"
  v="$(uname -m)" && [ -n "$v" ] || return 1;          printf 'arch: %s\n' "$v"
  v="$(sw_vers -buildVersion 2>/dev/null)" && [ -n "$v" ] || return 1;   printf 'macos build: %s\n' "$v"
}
if [ "$CACHE_ON" = 1 ]; then
  if ! TOOLCHAIN="$(_toolchain)"; then
    echo "run_tests: could not read the toolchain versions — compiling everything." >&2
    CACHE_ON=0
  fi
fi

# _key NAME FLAGS FILE... — the cache key of one binary.
_key() {
  local name="$1" flags="$2"; shift 2
  { printf 'format 1\nbinary %s\nswiftc %s\n' "$name" "$flags"; shasum -a 256 "$@"; printf '%s\n' "$TOOLCHAIN"; } | _sha
}
key_tests()  { _key tests  "${TESTS_FLAGS[*]}"  "${SOURCES[@]}" Tests/main.swift; }
key_helper() { _key helper "${HELPER_FLAGS[*]}" "${HELPER_SOURCES[@]}" Helper/*; }
key_plates() { _key plates "${PLATES_FLAGS[*]}" Tools/make-plate-fixtures.swift; }

# _build NAME KEYFN DEST CMD... — copy DEST from the cache, or run CMD and cache what it made.
BUILT=""
_build() {
  local name="$1" keyfn="$2" dest="$3" key="" d t sum; shift 3
  if [ "$CACHE_ON" = 1 ]; then
    key="$("$keyfn")"; d="$CACHE/$key"
    if [ -f "$d/ok" ] && [ -f "$d/$name" ]; then
      sum="$(sed -n 's/^sha256=//p' "$d/ok" | head -1)"
      t="$dest.cache.$$"
      if [ -n "$sum" ] && cp -p "$d/$name" "$t" 2>/dev/null && [ "$(_sha < "$t")" = "$sum" ] && mv -f "$t" "$dest"; then
        touch "$d/ok" 2>/dev/null || true
        BUILT="$BUILT $name:cached"; return 0
      fi
      rm -f "$t"
      echo "run_tests: the cached $name ($d) is unreadable or does not match its checksum — compiling." >&2
    fi
  fi
  "$@" || return 1
  BUILT="$BUILT $name:compiled"
  [ "$CACHE_ON" = 1 ] || return 0
  if [ "$("$keyfn")" != "$key" ]; then
    echo "run_tests: a $name input changed during the compile — not caching it." >&2; return 0
  fi
  t="$d/.$name.$$"
  if mkdir -p "$d" 2>/dev/null && cp -p "$dest" "$t" 2>/dev/null && mv -f "$t" "$d/$name" \
     && { printf 'sha256=%s\nwritten=%s\nworktree=%s\n' "$(_sha < "$d/$name")" "$(date '+%F %T')" "$PWD"; } > "$d/.ok.$$" \
     && mv -f "$d/.ok.$$" "$d/ok"; then
    # Keep the 30 most recently used entries.
    { ls -t "$CACHE"/*/ok 2>/dev/null | tail -n +31 | while IFS= read -r o; do rm -rf "${o%/ok}"; done; } || true
  else
    rm -f "$t" "$d/.ok.$$" 2>/dev/null
    echo "run_tests: could not write the binary cache at $d — continuing uncached." >&2
  fi
  return 0
}

c_t0=$(date +%s)
_build tests key_tests "$BIN" swiftc "${TESTS_FLAGS[@]}" -o "$BIN" "${SOURCES[@]}" Tests/main.swift || exit 1

# The recognition helper (R40), built the same way build.sh builds it and handed
# to the suite by path. Without this the helper checks have nothing to run and
# would quietly pass over a helper that does not compile — the shape of failure
# the SOURCES glob above exists to prevent. Kept to Recogniser's own closure so
# a mismatch with build.sh's list is a compile error here first.
# Checked explicitly rather than left to `set -e`: aborting here used to make the
# pre-commit hook report "TESTS FAILED" over a suite that had never run, which
# names the wrong cause (R43). The refusal is right; the diagnosis was not.
if ! _build visionocr-recognise key_helper "$HELPER" swiftc "${HELPER_FLAGS[@]}" -o "$HELPER" "${HELPER_SOURCES[@]}"; then
  echo >&2
  echo "run_tests: the recognition helper did not compile." >&2
  echo "           The suite did NOT run — the helper checks have nothing to test," >&2
  echo "           and the parity check is the only thing holding the helper and" >&2
  echo "           the app to the same observations. Fix Helper/main.swift." >&2
  exit 1
fi

# The six routing fixtures (R56, R57), built from the tool rather than copied into
# the suite. `Tools/make-plate-fixtures.swift` is where the pale drawing and the tonal
# plate are *defined* — luminance 200 on cream stock, a gradient with a dark subject —
# and a second copy of those numbers inside `Tests/main.swift` is a copy that goes
# stale silently, which is the shape of BUGS.md T15. The suite runs this binary and
# reads what it wrote, so the fixtures the acceptance checks route are the fixtures
# the register's measurements describe.
#
# Standalone: it imports AppKit and nothing from `Sources/`. About two seconds.
_plates() {
  cp Tools/make-plate-fixtures.swift build/make-plate-fixtures-main.swift &&
    swiftc "${PLATES_FLAGS[@]}" -o "$PLATES" build/make-plate-fixtures-main.swift
}
if ! _build make-plate-fixtures key_plates "$PLATES" _plates; then
  echo >&2
  echo "run_tests: Tools/make-plate-fixtures.swift did not compile." >&2
  echo "           The suite did NOT run — the R56/R57 routing checks would" >&2
  echo "           otherwise pass by having no fixtures to route." >&2
  exit 1
fi
case "$BUILT" in *compiled*) _note compiled ;; *) _note cache-hit ;; esac
echo "run_tests: binaries ready in $(( $(date +%s) - c_t0 ))s ($BUILT )"

# THE RUN, and only the run, under the machine-wide heavy lock shared with Archive Suite (mac-heavy-lock.sh):
# the compiles above are outside it, so another project's job waits on this suite's ~4 minutes of OCR and not
# on its swiftc. test-lock.sh, which callers wrap this script in, still holds test.lock over both; it passes
# its lock directory (touched while this waits, so test.lock is not broken as stale) and its label.
HEAVY="${VISIONOCR_MAC_HEAVY:-ops/autonomous/mac-heavy-lock.sh}"
RUN=(env VISIONOCR_HELPER="$PWD/$HELPER" VISIONOCR_PLATE_FIXTURES="$PWD/$PLATES" "./$BIN")
rc=0
if [ -x "$HEAVY" ]; then
  MAC_HEAVY_TOUCH="${VISIONOCR_TEST_LOCK_DIR:-}" "$HEAVY" run --label "${VISIONOCR_SUITE_LABEL:-suite}" -- "${RUN[@]}" || rc=$?
else
  echo "run_tests: $HEAVY is missing — running WITHOUT the machine-wide heavy lock." >&2
  "${RUN[@]}" || rc=$?
fi
exit "$rc"
