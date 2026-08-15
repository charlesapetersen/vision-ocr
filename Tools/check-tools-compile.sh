#!/bin/bash
# Does every tool in Tools/ still build?
#
# Nothing asked that until BUGS.md C25, which found that
# `Tools/score-text-route.swift` had **never compiled in any commit** — it called
# a `Flattener` function that has never existed — while three documents cited its
# output as their evidence. C25 was closed by removing the bad line. This closes
# the door it came through: the suite compiles `Sources/` and `Helper/`, and until
# now the only thing that compiled a tool was somebody deciding to run one.
#
#   Tools/check-tools-compile.sh              # every tool
#   Tools/check-tools-compile.sh score-mrc    # one, by name or by path
#
# Swift tools are type-checked, not built. `swiftc -typecheck` is about 7 seconds
# a tool against 25 seconds for `-O`, and it catches the whole class C25 was in —
# a call to something that is not there. It does **not** catch a link failure, so
# a tool that has just grown a new dependency still wants one real build.
#
# Python tools get `py_compile`, which is **syntax only**: a body of
# `return no_such_function(1)` compiles clean. Shell tools get `bash -n`, which is
# the same bargain. Both are worth having and neither is a substitute for running
# the thing — `bash -n` is here because the first version of *this file* shipped a
# bug `bash -n` cannot catch either (see below), and its 24 Swift tools passed
# while it did.
#
# **The bug that taught this file to check itself.** It expanded `"${ARRAY[@]}"`
# under `set -u` on macOS's bash 3.2, where an *empty* array is a fatal "unbound
# variable" rather than nothing at all. A run naming only Python tools died on the
# Swift array and vice versa — so the pre-commit hook it feeds would have refused
# any commit whose staged tools were all of one kind, reporting "a staged tool does
# not build" with every tool green. Every array expansion below is guarded by a
# count for that reason, and the guards are not decoration.
#
# Each Swift tool is copied to its own `main.swift` because that is the only file
# name Swift allows top-level code in, and nearly every tool here is top-level
# code — which is also why they cannot be checked in one pass.
#
# Two shapes of tool, discovered by trying rather than by a list this file would
# have to keep in step:
#
#   - **standalone.** `probe-line-edges`, `probe-text-offset` and
#     `probe-line-coverage` import PDFKit and declare their own `Box`/`Obs`, and
#     compiling them *with* `Sources/` collides with `SettingsView`'s own `Box`.
#     So each tool is checked alone first and only retried against `Sources/` if
#     that fails. **Both attempts' errors are reported when both fail**, labelled,
#     because the first version overwrote one log with the other and then showed a
#     standalone tool a wall of errors in `SettingsView.swift` — the exact symptom
#     `Tools/README.md` warns is the signature of a missing source.
#   - **`@main`.** `probe-window-reopen` is a library with an entry point, built
#     `-parse-as-library` under its own module name; renaming it to `main.swift`
#     is what makes `@main` illegal, so it keeps its name.
set -uo pipefail
cd "$(dirname "$0")/.."

# A git hook and a GUI-launched shell both have almost no PATH.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "check-tools-compile: swiftc is not on PATH, cannot check anything." >&2
  exit 1
fi

# Every source except App.swift, by glob — the same rule and the same reason as
# run_tests.sh: a hand-written list goes stale and the check then passes over code
# it has never seen. App.swift's @main collides with a tool's top-level code.
SOURCES=()
for f in Sources/*.swift; do
  [ "$(basename "$f")" = "App.swift" ] && continue
  SOURCES+=("$f")
done
if [ "${#SOURCES[@]}" -eq 0 ]; then
  echo "check-tools-compile: no Sources/*.swift found — wrong directory?" >&2
  exit 1
fi

TARGET="$(uname -m)-apple-macos13.0"
WORK=$(mktemp -d -t vrg-toolcheck)
trap 'rm -rf "$WORK"' EXIT

# Which tools. A bare name, a stem, or a path all resolve.
SWIFT_TOOLS=()
PY_TOOLS=()
SH_TOOLS=()
if [ "$#" -gt 0 ]; then
  for want in "$@"; do
    hit=""
    for candidate in "Tools/$want" "Tools/$want.swift" "Tools/$want.py" \
                     "Tools/$want.sh" "$want"; do
      [ -f "$candidate" ] && { hit="$candidate"; break; }
    done
    if [ -z "$hit" ]; then
      echo "check-tools-compile: no tool matches '$want'." >&2
      exit 1
    fi
    case "$hit" in
      *.swift) SWIFT_TOOLS+=("$hit") ;;
      *.py)    PY_TOOLS+=("$hit") ;;
      *.sh)    SH_TOOLS+=("$hit") ;;
      *) echo "check-tools-compile: '$hit' is not .swift, .py or .sh, skipping." >&2 ;;
    esac
  done
else
  for f in Tools/*.swift; do [ -f "$f" ] && SWIFT_TOOLS+=("$f"); done
  for f in Tools/*.py;    do [ -f "$f" ] && PY_TOOLS+=("$f"); done
  for f in Tools/*.sh;    do [ -f "$f" ] && SH_TOOLS+=("$f"); done
fi

# One job per two cores, capped: this is pure compilation with no shared state, so
# it is not the hazard CLAUDE.md warns about for two test suites — those collide
# over one preferences file, and nothing here runs.
#
# `wait -n` is **not available in bash 3.2**, and the first version used it: the
# `|| wait` fallback barriered on every child while the counter dropped by one, so
# after the first batch the run was serial while printing "6 at a time". This polls
# `jobs -pr` instead, which 3.2 does have.
JOBS=${JOBS:-$(( $(sysctl -n hw.ncpu 2>/dev/null || echo 4) / 2 ))}
[ "$JOBS" -lt 1 ] && JOBS=1

# Each job writes its own report and the parent prints them in order afterwards.
# Concurrent jobs writing to one stdout interleave, and a gate whose output is
# ordered differently on every run is a gate people stop reading.
check_swift() {
  local tool="$1" stem entry report
  stem=$(basename "$tool" .swift)
  report="$WORK/$stem.report"
  mkdir -p "$WORK/$stem"

  if grep -q '^@main' "$tool"; then
    # Its own name and -parse-as-library, which is the command its header
    # documents. Alone first, then with Sources/ if it needs them.
    cp "$tool" "$WORK/$stem/$stem.swift"
    entry="$WORK/$stem/$stem.swift"
    if swiftc -typecheck -parse-as-library -module-name "$stem" -target "$TARGET" \
        "$entry" >"$WORK/$stem.alone.log" 2>&1; then
      echo "ok   $tool" >"$report"; return
    fi
    if swiftc -typecheck -parse-as-library -module-name "$stem" -target "$TARGET" \
        "${SOURCES[@]}" "$entry" >"$WORK/$stem.sources.log" 2>&1; then
      echo "ok   $tool" >"$report"; return
    fi
  else
    cp "$tool" "$WORK/$stem/main.swift"
    entry="$WORK/$stem/main.swift"
    # Standalone first. A tool that needs Sources/ fails this in a second or two;
    # a tool that must NOT have them (its own `Box`) would fail *with* them.
    if swiftc -typecheck -target "$TARGET" "$entry" \
        >"$WORK/$stem.alone.log" 2>&1; then
      echo "ok   $tool" >"$report"; return
    fi
    if swiftc -typecheck -target "$TARGET" "${SOURCES[@]}" "$entry" \
        >"$WORK/$stem.sources.log" 2>&1; then
      echo "ok   $tool" >"$report"; return
    fi
  fi

  # Both configurations failed, so neither log is "the" answer and both are shown.
  {
    echo "FAIL $tool"
    echo "     — alone:"
    grep -E 'error:' "$WORK/$stem.alone.log" 2>/dev/null | head -3 | sed 's/^/       /'
    echo "     — with Sources/:"
    grep -E 'error:' "$WORK/$stem.sources.log" 2>/dev/null | head -3 | sed 's/^/       /'
  } >"$report"
  touch "$WORK/$stem.failed"
}

echo "check-tools-compile: ${#SWIFT_TOOLS[@]} Swift, ${#PY_TOOLS[@]} Python," \
     "${#SH_TOOLS[@]} shell, $JOBS at a time"

if [ "${#SWIFT_TOOLS[@]}" -gt 0 ]; then
  for tool in "${SWIFT_TOOLS[@]}"; do
    while [ "$(jobs -pr | wc -l)" -ge "$JOBS" ]; do sleep 0.2; done
    check_swift "$tool" &
  done
  wait
  for tool in "${SWIFT_TOOLS[@]}"; do
    stem=$(basename "$tool" .swift)
    [ -f "$WORK/$stem.report" ] && cat "$WORK/$stem.report" \
      || { echo "FAIL $tool"; echo "       the check produced no report at all";
           touch "$WORK/$stem.failed"; }
  done
fi

if [ "${#PY_TOOLS[@]}" -gt 0 ]; then
  for tool in "${PY_TOOLS[@]}"; do
    if python3 -m py_compile "$tool" 2>"$WORK/py.log"; then
      echo "ok   $tool"
    else
      echo "FAIL $tool"
      head -5 "$WORK/py.log" | sed 's/^/       /'
      touch "$WORK/$(basename "$tool").failed"
    fi
  done
fi

if [ "${#SH_TOOLS[@]}" -gt 0 ]; then
  for tool in "${SH_TOOLS[@]}"; do
    if bash -n "$tool" 2>"$WORK/sh.log"; then
      echo "ok   $tool"
    else
      echo "FAIL $tool"
      head -5 "$WORK/sh.log" | sed 's/^/       /'
      touch "$WORK/$(basename "$tool").failed"
    fi
  done
fi

failed=$(find "$WORK" -maxdepth 1 -name '*.failed' | wc -l | tr -d ' ')
if [ "$failed" -gt 0 ]; then
  echo
  echo "check-tools-compile: $failed tool(s) do not build." >&2
  exit 1
fi
echo "check-tools-compile: all clear."
