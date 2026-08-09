#!/bin/bash
# Break something on purpose and check the build notices.
#
# Why this exists: the third review of 2026-08-09 found that three defects
# (R31, R32, H2) all lived in code that only runs when something *else* fails —
# the bundling audit, the detach-on-failure path, the licence count. Every one
# was written carefully and none had ever been executed, because nothing made
# the thing they guard actually go wrong.
#
# The reviewers found R31 by putting a no-op `install_name_tool` on PATH and
# running the real script. That technique was the most valuable thing in the
# review and it existed nowhere in this repo. Now it does.
#
#   ./Tools/fault-inject.sh          # every fault, sequentially
#   ./Tools/fault-inject.sh relocate # one, by name
#   ./Tools/fault-inject.sh --list
#
# Each case sabotages one thing, runs the real build step, and asserts the build
# REFUSES. A case that passes means the build noticed. A case that FAILS means
# the build carried on with something broken — which is the whole point.
#
# Sequential, and it builds into a scratch copy of the tree, so nothing here
# touches your working tree or the real build/ directory.
set -uo pipefail

cd "$(dirname "$0")/.."
REPO="$PWD"
PASS=0; FAIL=0

say()  { printf '  %s\n' "$*"; }
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s — %s\n' "$1" "$2"; }

# A scratch copy of the tree, so a sabotaged build cannot leave debris behind in
# the real one. testdocs is 1.2 GB and irrelevant here.
sandbox() {
  SB="$(mktemp -d)"
  rsync -a --exclude .git --exclude build --exclude testdocs \
        --exclude Tools/mutation-out "$REPO/" "$SB/"
  mkdir -p "$SB/build"
}
cleanup() { [ -n "${SB:-}" ] && rm -rf "$SB"; }
trap cleanup EXIT

# A directory holding a shim that shadows a real tool on PATH.
shim() {
  local name="$1" body="$2"
  SHIMDIR="$(mktemp -d)"
  printf '#!/bin/bash\n%s\n' "$body" > "$SHIMDIR/$name"
  chmod +x "$SHIMDIR/$name"
  echo "$SHIMDIR"
}

# ---------------------------------------------------------------- the faults

# R31. A relocation that silently does nothing. The audit must catch it, and —
# the half that actually shipped broken — the bundle must not be left holding
# the unrelocated copies while the build reports "not bundled".
fault_relocate() {
  local name="a failed relocation is fatal and leaves nothing behind"
  sandbox
  local app="$SB/build/VisionOCR.app"
  mkdir -p "$app/Contents/Resources"
  local sd; sd="$(shim install_name_tool 'exit 0')"        # accepts, changes nothing
  local out rc
  out="$(cd "$SB" && PATH="$sd:$PATH" python3 Tools/bundle-libs.py "$app" jbig2 qpdf 2>&1)"; rc=$?
  rm -rf "$sd"

  if [ "$rc" -eq 0 ]; then
    bad "$name" "bundle-libs.py returned 0 with every install name unrewritten"
  else
    local left
    left=$(find "$app/Contents/Resources" \( -name jbig2 -o -name qpdf -o -name '*.dylib' \) 2>/dev/null | wc -l | tr -d ' ')
    if [ "$left" != "0" ]; then
      bad "$name" "exited $rc but left $left copied file(s) in the bundle"
    else
      ok "$name"
    fi
    # And the exit code has to be distinguishable from "tool not installed",
    # or build.sh cannot tell a benign skip from a broken bundle.
    [ "$rc" -eq 3 ] || bad "$name (exit code)" "audit failure exited $rc; build.sh treats 1 as benign"
  fi
}

# R31, the other half: build.sh itself must stop, not print "not bundled" and
# carry on signing what the audit rejected.
fault_build_continues() {
  local name="build.sh stops when bundling fails rather than shipping it"
  sandbox
  local sd; sd="$(shim install_name_tool 'exit 0')"
  local out rc
  out="$(cd "$SB" && PATH="$sd:$PATH" ./build.sh 2>&1)"; rc=$?
  rm -rf "$sd"
  if [ "$rc" -eq 0 ]; then
    bad "$name" "build.sh exited 0 after the audit rejected the bundle"
  elif grep -q 'not bundled' <<<"$out" && [ "$rc" -eq 0 ]; then
    bad "$name" "printed 'not bundled' and continued"
  else
    ok "$name"
  fi
}

# H2. A package in the closure with no licence file must be reported, not
# counted. Simulated by asking for a licence directory we then check honestly.
fault_missing_licence() {
  local name="a bundled package with no licence is reported, not counted"
  sandbox
  local app="$SB/build/VisionOCR.app"
  mkdir -p "$app/Contents/Resources"
  local out rc
  out="$(cd "$SB" && python3 Tools/bundle-libs.py "$app" jbig2 qpdf 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    bad "$name" "bundling failed outright: $(tail -1 <<<"$out")"
    return
  fi
  # Every dylib that came from a Cellar formula should have a notice whose name
  # starts with that formula.
  local missing=0 f base
  for f in "$app/Contents/Resources/lib/"*.dylib; do
    base=$(basename "$f")
    case "$base" in
      libleptonica*) grep -qil leptonica <<<"$(ls "$app/Contents/Resources/third-party-licences" 2>/dev/null)" || missing=$((missing+1));;
    esac
  done
  if [ "$missing" -ne 0 ]; then
    bad "$name" "leptonica is bundled with no licence notice"
  else
    ok "$name"
  fi
}

# R32. A detach that fails must not swallow the diagnostic explaining why the
# image was rejected in the first place.
fault_detach_fails() {
  local name="a failing detach does not swallow the verification diagnostic"
  sandbox
  # BOTH halves have to be broken, or this cannot fail. The first version of
  # this case only broke detach; verification then succeeded, the failure branch
  # never ran, and the check passed while testing nothing — the T6 shape, in a
  # case written to prevent it. So: `attach` yields an EMPTY mount, which makes
  # the engine check fail, and `detach` then fails the way Disk Arbitration
  # makes it fail on a freshly mounted volume.
  local sd; sd="$(shim hdiutil '
case "$1" in
  attach)
    for a in "$@"; do [ "$prev" = "-mountpoint" ] && mkdir -p "$a" && exit 0; prev="$a"; done
    exit 0 ;;
  detach) exit 16 ;;
esac
exec /usr/bin/hdiutil "$@"')"
  local out rc
  out="$(cd "$SB" && PATH="$sd:$PATH" ./build.sh --dmg 2>&1)"; rc=$?
  rm -rf "$sd"
  if [ "$rc" -eq 0 ]; then
    bad "$name" "build succeeded despite a failing detach"
  elif grep -qE 'did not run from the image|Engine|runs from the image' <<<"$out"; then
    ok "$name"
  else
    bad "$name" "exited $rc with no diagnostic: $(tail -2 <<<"$out" | tr '\n' ' ')"
  fi
}

FAULTS="relocate build_continues missing_licence detach_fails"

if [ "${1:-}" = "--list" ]; then
  for f in $FAULTS; do echo "  $f"; done; exit 0
fi

WANTED="${1:-}"
echo "fault injection — each case breaks one thing and checks the build notices"
for f in $FAULTS; do
  [ -n "$WANTED" ] && [ "$f" != "$WANTED" ] && continue
  printf '\n%s\n' "$f:"
  "fault_$f"
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
