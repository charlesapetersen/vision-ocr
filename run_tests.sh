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
swiftc -O -o "$BIN" \
  -target "$(uname -m)-apple-macos13.0" \
  "${SOURCES[@]}" \
  Tests/main.swift

# The recognition helper (R40), built the same way build.sh builds it and handed
# to the suite by path. Without this the helper checks have nothing to run and
# would quietly pass over a helper that does not compile — the shape of failure
# the SOURCES glob above exists to prevent. Kept to Recogniser's own closure so
# a mismatch with build.sh's list is a compile error here first.
# Checked explicitly rather than left to `set -e`: aborting here used to make the
# pre-commit hook report "TESTS FAILED" over a suite that had never run, which
# names the wrong cause (R43). The refusal is right; the diagnosis was not.
HELPER="build/visionocr-recognise"
if ! swiftc -O -o "$HELPER" \
  -target "$(uname -m)-apple-macos13.0" \
  Sources/Prefs.swift Sources/Runner.swift Sources/Recogniser.swift \
  Sources/SearchableWriter.swift Sources/Flattener.swift Sources/JBIG2.swift \
  Helper/main.swift; then
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
PLATES="build/make-plate-fixtures"
cp Tools/make-plate-fixtures.swift build/make-plate-fixtures-main.swift
if ! swiftc -o "$PLATES" \
  -target "$(uname -m)-apple-macos13.0" \
  build/make-plate-fixtures-main.swift; then
  echo >&2
  echo "run_tests: Tools/make-plate-fixtures.swift did not compile." >&2
  echo "           The suite did NOT run — the R56/R57 routing checks would" >&2
  echo "           otherwise pass by having no fixtures to route." >&2
  exit 1
fi

VISIONOCR_HELPER="$PWD/$HELPER" VISIONOCR_PLATE_FIXTURES="$PWD/$PLATES" "./$BIN"
