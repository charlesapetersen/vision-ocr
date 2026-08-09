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

# The recognition engine travels with the app.
#
# mac-ocr is a universal Mach-O linking only system frameworks, so it needs
# neither Homebrew nor node at runtime — verified with `env -i`. Bundling it is
# the difference between "download and drag" and "open Terminal, install
# Homebrew, install Node, install a package". MIT, Copyright (c) Hiroki Osame;
# the licence is copied in beside it.
#
# Taken from wherever this machine has it rather than vendored into the repo: a
# 2.4 MB binary in git costs every clone forever, and a --dmg build that cannot
# find it should fail loudly rather than quietly ship the old Terminal
# instructions.
echo "==> Bundling mac-ocr"
MACOCR=""
for candidate in \
  "/opt/homebrew/lib/node_modules/mac-ocr/bin/mac-ocr" \
  "/usr/local/lib/node_modules/mac-ocr/bin/mac-ocr" \
  "$(command -v mac-ocr 2>/dev/null || true)"; do
  [ -n "$candidate" ] && [ -x "$candidate" ] && { MACOCR="$candidate"; break; }
done

if [ -n "$MACOCR" ]; then
  # Resolve a symlink (npm's bin/ is one) so we copy the executable itself.
  MACOCR="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$MACOCR")"
  cp "$MACOCR" "$APP/Contents/Resources/mac-ocr"
  chmod +x "$APP/Contents/Resources/mac-ocr"
  LICENSE_SRC="$(dirname "$(dirname "$MACOCR")")/LICENSE"
  [ -f "$LICENSE_SRC" ] && cp "$LICENSE_SRC" "$APP/Contents/Resources/mac-ocr-LICENSE"
  echo "    $("$APP/Contents/Resources/mac-ocr" --version) from $MACOCR"
  echo "    $(lipo -archs "$APP/Contents/Resources/mac-ocr")"
elif [ "$DMG" = 1 ]; then
  echo "mac-ocr not found, and a disk image without it would send its user to" >&2
  echo "the Terminal. Install it (npm install -g mac-ocr) and build again." >&2
  exit 1
else
  echo "    (not found — this build will fall back to Homebrew or the login shell)"
fi

echo "==> Signing (ad hoc)"
# Inside out: a nested executable has to be signed before the bundle that
# contains it, or the outer signature is computed over an unsigned helper and
# the app is rejected as damaged.
if [ -f "$APP/Contents/Resources/mac-ocr" ]; then
  codesign --force --sign - "$APP/Contents/Resources/mac-ocr"
fi
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
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MP" "$DMG_PATH"
  ENGINE="$MP/$APP_NAME.app/Contents/Resources/mac-ocr"
  if [ -x "$ENGINE" ] && VER=$(env -i PATH=/usr/bin:/bin "$ENGINE" --version 2>&1); then
    echo "==> Engine in the image answers with no PATH: mac-ocr $VER"
  else
    hdiutil detach -quiet "$MP"; rmdir "$MP"
    echo "the bundled engine did not run from the image with an empty PATH" >&2
    exit 1
  fi
  hdiutil detach -quiet "$MP"; rmdir "$MP"

  echo "==> Built $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
fi
