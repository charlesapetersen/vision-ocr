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

swiftc -o "$BIN" \
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
if ! swiftc -o "$HELPER" \
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
