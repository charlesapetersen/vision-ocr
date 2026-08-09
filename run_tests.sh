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

"./$BIN"
