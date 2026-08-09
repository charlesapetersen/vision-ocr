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

swiftc -o "$BIN" \
  -target "$(uname -m)-apple-macos13.0" \
  Sources/Prefs.swift Sources/Runner.swift Sources/Flattener.swift \
  Sources/SearchableWriter.swift Sources/JBIG2.swift Sources/Model.swift \
  Sources/ContentView.swift Sources/SettingsView.swift \
  Tests/main.swift

"./$BIN"
