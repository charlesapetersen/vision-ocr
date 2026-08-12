#!/bin/bash
# Builds VisionOCR.app (Vision OCR).
#   ./build.sh            build into ./build
#   ./build.sh --install  build, then install to /Applications (or ~/Applications)
#   ./build.sh --run      build, install, and (re)launch
#   ./build.sh --dmg      build, then package build/Vision OCR.dmg for handing out
#   ./build.sh --universal  build for arm64 and x86_64 (implied by --dmg)
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="VisionOCR"
BUNDLE_ID="com.cp1.VisionOCR"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
ARCH="$(uname -m)"

INSTALL=0
RUN=0
DMG=0
UNIVERSAL=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --run) INSTALL=1; RUN=1 ;;
    --dmg) DMG=1 ;;
    --universal) UNIVERSAL=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# A disk image goes to Macs we know nothing about, so packaging implies a
# universal binary. Building for this machine only is the default because it is
# half the compile, and nobody testing a change needs the other slice.
[ "$DMG" = 1 ] && UNIVERSAL=1

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# -parse-as-library: the entry point is @main in App.swift, not top-level code.
BIN="$APP/Contents/MacOS/$APP_NAME"
if [ "$UNIVERSAL" = 1 ]; then
  echo "==> Compiling (universal: arm64 + x86_64)"
  SLICES=()
  for slice in arm64 x86_64; do
    echo "    $slice"
    swiftc -O \
      -parse-as-library \
      -target "$slice-apple-macos13.0" \
      -o "$BUILD_DIR/$APP_NAME.$slice" \
      Sources/*.swift
    SLICES+=("$BUILD_DIR/$APP_NAME.$slice")
  done
  lipo -create "${SLICES[@]}" -output "$BIN"
  rm -f "${SLICES[@]}"
  # Verify rather than assume. A single-slice binary handed to an Intel Mac does
  # not warn, it just refuses to open, and the person on the other end has no
  # way to tell that from a broken download.
  archs=$(lipo -archs "$BIN")
  for want in arm64 x86_64; do
    case " $archs " in *" $want "*) ;;
      *) echo "expected $want in the binary, got: $archs" >&2; exit 1 ;;
    esac
  done
  echo "    contains: $archs"
else
  echo "==> Compiling ($ARCH)"
  swiftc -O \
    -parse-as-library \
    -target "$ARCH-apple-macos13.0" \
    -o "$BIN" \
    Sources/*.swift
fi

cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Making icon"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
if swift Tools/make_icon.swift "$ICONSET" 2>/dev/null &&
   iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  rm -rf "$ICONSET"
else
  echo "    (skipped — app will use the generic icon)"
fi

# The recognition engine used to travel with the app: a 2.4 MB copy of mac-ocr
# in Contents/Resources, bundled precisely so that using this app did not mean
# installing Homebrew, then Node, then an npm package, in a Terminal.
#
# It is gone. Recognition calls Vision directly (Sources/Recogniser.swift), so
# there is nothing to bundle, nothing to find, and nothing to keep in step with
# a corpus baseline. The MIT licence still travels with the app because three of
# the request's options were got right by reading mac-ocr's source — see the
# credit in Recogniser.swift.
if [ -f "Resources/mac-ocr-LICENSE" ]; then
  cp "Resources/mac-ocr-LICENSE" "$APP/Contents/Resources/mac-ocr-LICENSE"
fi

# Optional in a way mac-ocr is not: without them the app writes Flate-compressed
# pages, which work identically and are about three times the size. Bundling
# them means "smaller files" stops being a thing you have to visit Homebrew for.
#
# Unlike mac-ocr these are NOT self-contained — jbig2 pulls in leptonica and its
# image codecs, qpdf pulls in libqpdf and OpenSSL — so the closure is copied and
# every install name rewritten to @loader_path. And unlike mac-ocr they are
# single-architecture, because Homebrew builds for the machine it is on: a disk
# image built on Apple Silicon carries arm64-only copies. Runner.bundledTool
# reads the Mach-O header and ignores a slice it cannot run, so an Intel Mac
# falls through to Homebrew exactly as before rather than failing at exec.
echo "==> Bundling the compression tools"
# Two different failures, two exit codes. 1 is "not installed on this machine",
# which is benign — the app looks on PATH and writes larger files. 3 is "the
# audit rejected what I copied", which is fatal: the copies are gone, but
# continuing would sign and ship an app whose bundled helpers are broken, and
# locateTool prefers the bundled copy over a working Homebrew one. One handler
# for both printed "not bundled" over exactly that (R31).
set +e
python3 Tools/bundle-libs.py "$APP" jbig2 qpdf
bundle_rc=$?
set -e
case "$bundle_rc" in
  0) ;;
  1) echo "    (not installed — the app will look for them on PATH)" ;;
  *) echo "bundling failed its own audit (exit $bundle_rc); refusing to build" >&2
     exit 1 ;;
esac

echo "==> Signing (ad hoc)"
# Inside out: a nested executable has to be signed before the bundle that
# contains it, or the outer signature is computed over an unsigned helper and
# the app is rejected as damaged.
# Dylibs before the executables that load them, executables before the bundle.
if [ -d "$APP/Contents/Resources/lib" ]; then
  find "$APP/Contents/Resources/lib" -name '*.dylib' -exec codesign --force --sign - {} \;
fi
for helper in jbig2 qpdf; do
  [ -f "$APP/Contents/Resources/$helper" ] && codesign --force --sign - "$APP/Contents/Resources/$helper"
done
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"

echo "==> Built $APP"

if [ "$INSTALL" = 1 ]; then
  DEST="/Applications"
  [ -w "$DEST" ] || DEST="$HOME/Applications"
  mkdir -p "$DEST"

  # Quit any running copy so the bundle can be replaced, and wait for it to
  # actually go rather than guessing at a sleep.
  pkill -x "$APP_NAME" 2>/dev/null || true
  for _ in $(seq 1 40); do
    pgrep -x "$APP_NAME" >/dev/null || break
    sleep 0.1
  done

  # Stage the copy first: a mid-copy failure must not be able to leave a
  # half-written bundle where the working install used to be.
  STAGE="$DEST/.$APP_NAME.app.staged"
  rm -rf "$STAGE"
  cp -R "$APP" "$STAGE"
  rm -rf "${DEST:?}/$APP_NAME.app"
  mv "$STAGE" "$DEST/$APP_NAME.app"
  echo "==> Installed to $DEST/$APP_NAME.app"

  if [ "$RUN" = 1 ]; then
    open "$DEST/$APP_NAME.app"
    echo "==> Running"
  fi
fi

if [ "$DMG" = 1 ]; then
  # A disk image is how this gets handed to someone who is not going to run
  # swiftc. The volume name is what they see mounted, so it is the display name
  # with a space, not the executable name.
  VOLUME="Vision OCR"
  DMG_PATH="$BUILD_DIR/$VOLUME.dmg"
  STAGE_DIR="$BUILD_DIR/dmg-stage"
  rm -rf "$STAGE_DIR" "$DMG_PATH"
  mkdir -p "$STAGE_DIR"
  cp -R "$APP" "$STAGE_DIR/"
  # The drag-to-install target. Without it people copy the app into the disk
  # image and wonder why their settings vanish on the next mount.
  ln -s /Applications "$STAGE_DIR/Applications"

  echo "==> Packaging $DMG_PATH"
  hdiutil create -quiet -srcfolder "$STAGE_DIR" -volname "$VOLUME" \
    -fs HFS+ -format UDZO -ov "$DMG_PATH"
  rm -rf "$STAGE_DIR"

  # Verify rather than assume: a truncated image mounts as far as the finder
  # icon and fails on copy, which is exactly the shape of failure this project
  # keeps meeting.
  hdiutil verify -quiet "$DMG_PATH"

  # The claim this image makes is "no Terminal needed". Check it: mount the
  # image and run the engine out of it with an empty environment, so neither
  # Homebrew nor node is on PATH. If that works here it works on a machine that
  # has never had either.
  MP="$(mktemp -d)"
  # A trap, not just tidy exits. The sibling sweep in CONTRIBUTING 4b asked who
  # else mounts without one: every failure between here and the detach below
  # leaks the mount, which is R32's leak reached by a different route. Idempotent
  # on purpose — the explicit detaches stay, for ordering, and running twice is
  # a no-op.
  release_mount() {
    [ -n "${MP:-}" ] || return 0
    hdiutil detach -quiet "$MP" 2>/dev/null || hdiutil detach -force -quiet "$MP" 2>/dev/null || true
    rmdir "$MP" 2>/dev/null || true
  }
  trap release_mount EXIT
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MP" "$DMG_PATH"
  RES="$MP/$APP_NAME.app/Contents/Resources"
  # Checked only if bundled, since a build on a machine without them is
  # legitimate — the app falls back to CoreGraphics' Flate.
  for tool in jbig2 qpdf; do
    [ -x "$RES/$tool" ] || continue
    # Retried, briefly. A freshly attached image is not always ready to exec
    # from the instant `hdiutil attach` returns, and one release build failed
    # here on a tool that ran fine three times immediately afterwards. A
    # verification step that fails intermittently teaches people to re-run
    # builds until they pass, which is the opposite of what it is for.
    VER=""; attempt=0
    while [ "$attempt" -lt 3 ]; do
      if VER=$(env -i PATH=/usr/bin:/bin "$RES/$tool" --version 2>&1 | head -1); then break; fi
      attempt=$((attempt+1)); sleep 1
    done
    if [ "$attempt" -lt 3 ]; then
      [ "$attempt" -gt 0 ] && echo "    ($tool needed $attempt retry/retries — the mount was not ready)"
      echo "==> $tool runs from the image with no PATH: $VER"
    else
      # Say why FIRST. Detach returns 16 when Disk Arbitration still holds a
      # freshly mounted volume, and under `set -e` that killed the script on
      # this line — losing the diagnostic that explains the whole failure (R32).
      echo "$tool did not run from the image with an empty PATH: $VER" >&2
      hdiutil detach -quiet "$MP" 2>/dev/null || hdiutil detach -force -quiet "$MP" 2>/dev/null || true
      rmdir "$MP" 2>/dev/null || true
      # And take the image with it: a disk image that failed its own
      # verification must not be left on disk looking shippable.
      rm -f "$DMG_PATH"
      exit 1
    fi
  done
  # Never leave the image attached: a leaked mount was found still holding
  # "Vision OCR.dmg" hours after a build (R32).
  hdiutil detach -quiet "$MP" 2>/dev/null || hdiutil detach -force -quiet "$MP" 2>/dev/null || true
  rmdir "$MP" 2>/dev/null || true

  echo "==> Built $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
fi
