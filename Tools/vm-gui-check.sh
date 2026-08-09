#!/bin/bash
# Run the interface checks that only a running app can answer — off-screen.
#
# Three properties cannot be settled by reading or by run_tests.sh: whether the
# window comes back after being closed mid-run (U13), whether Settings fits a
# short display (U15), and whether one window stays one window when Finder hands
# the app several files (U17). All three were regressions or live bugs at some
# point, and all three were found by doing this by hand. This is that by-hand
# pass, written down so it can be repeated.
#
#   Tools/vm-gui-check.sh [windows|reopen|settings|all]      (default: all)
#
# It uses the Archive Suite's Tart VM, which has its own virtual display, so
# nothing appears on your screen. Input goes in over VNC because VNC-injected
# events bypass the guest's TCC entirely — in-VM cliclick would need an
# Accessibility grant that is awkward to seed.
#
# Requirements, each checked loudly:
#   brew install cirruslabs/cli/tart
#   a VM named $VM (default archive-gui-runner) with mac-ocr installed
#   vncdotool at ~/.tart-mirror/vncenv/bin/vncdotool
#
# EXIT: 0 all checks passed · 1 a check failed · 3 could not run (skipped)
#
# --- three instruments that lied while this was being written, and the guards ---
#
#  1. A window probe filtered kCGWindowOwnerName on a prefix of the app's name.
#     The bundle name has a SPACE in it — "Vision Reader GUI" then, "Vision OCR"
#     now — so the match failed and it reported ZERO windows while the app had
#     four; the first reading of U13 was "the fix does nothing". => the probe
#     below filters by pid, which the rename cannot break either.
#  2. The guest's virtiofs --dir mount served a 90-minute-old App.swift, so the
#     build under test was not the code under test and the fix measured as
#     ineffective. => sources go over `tart exec -i`, never the share.
#  3. A TCC prompt sat on the VM's screen eating every keystroke, producing a
#     clean and entirely fictitious tab-order result. => dismiss_prompts runs
#     before any check, and state is read from the window list rather than from
#     screenshots, which also go stale over VNC.
set -uo pipefail

VM="${VM:-archive-gui-runner}"
TART="${TART:-/opt/homebrew/bin/tart}"
VNCDOTOOL="${VNCDOTOOL:-$HOME/.tart-mirror/vncenv/bin/vncdotool}"
BUNDLE_ID="com.cp1.VisionOCR"
LANE="${1:-all}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
STARTED_VM=0
PASS=0
FAIL=0

log()  { printf '\n=== %s\n' "$*"; }
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$*"; }
skip() { printf 'vm-gui-check: SKIPPED — %s\n' "$*" >&2; exit 3; }

cleanup() {
  guest 'pkill -x VisionOCR; pkill -x mac-ocr' >/dev/null 2>&1
  [ "$STARTED_VM" = 1 ] && "$TART" stop "$VM" >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

guest() { "$TART" exec "$VM" bash -lc "$1" 2>&1; }
vnc()   { "$VNCDOTOOL" -s "$VNC_HOST::$VNC_PORT" -p "$VNC_PASS" "$@" 2>/dev/null; }

# --- preconditions ----------------------------------------------------------
[ -x "$TART" ] || command -v tart >/dev/null 2>&1 || skip \
  "tart is not installed — brew install cirruslabs/cli/tart"
command -v "$TART" >/dev/null 2>&1 || TART=tart
"$TART" list 2>/dev/null | grep -q "[[:space:]]$VM[[:space:]]" || skip \
  "no VM called '$VM' — see Tools/README.md"
[ -x "$VNCDOTOOL" ] || skip \
  "vncdotool not at $VNCDOTOOL — python3 -m venv ~/.tart-mirror/vncenv &&
   ~/.tart-mirror/vncenv/bin/pip install vncdotool"

# --- boot -------------------------------------------------------------------
# --no-graphics AND --vnc-experimental. The second alone is not headless: tart
# opens Screen Sharing.app at the endpoint and a window appears on your display.
# Together, tart still prints the endpoint and opens no viewer.
if "$TART" list 2>/dev/null | grep -E "[[:space:]]$VM[[:space:]]" | grep -q running; then
  skip "'$VM' is already running and this script did not start it, so there is
   no VNC endpoint and the mounts may be wrong. Stop it first: tart stop $VM"
fi
log "booting $VM headless"
"$TART" run "$VM" --no-graphics --vnc-experimental >"$WORK/runlog" 2>&1 &
STARTED_VM=1
for _ in $(seq 1 90); do grep -q 'vnc://' "$WORK/runlog" && break; sleep 1; done
URL="$(grep -o 'vnc://[^ ]*' "$WORK/runlog" | head -1)"
[ -n "$URL" ] || skip "the VM reported no VNC endpoint — see $WORK/runlog"
VNC_PASS="$(printf '%s' "$URL" | sed -E 's#vnc://:([^@]+)@.*#\1#')"
HOSTPORT="$(printf '%s' "$URL" | sed -E 's#vnc://:[^@]+@##')"
VNC_HOST="${HOSTPORT%%:*}"; VNC_PORT="${HOSTPORT##*:}"

# `tart ip --wait` returns when the guest has NETWORKING; `tart exec` talks over
# a separate vsock socket served by the guest agent, which comes up later. Every
# exec before that fails, and callers that `|| true` their execs then run nothing
# at all while reporting success. Poll for the agent.
waited=0
until "$TART" exec "$VM" true >/dev/null 2>&1; do
  [ "$waited" -ge 240 ] && skip "the guest agent never answered"
  sleep 5; waited=$((waited + 5))
done
echo "  guest agent ready after ${waited}s, VNC on $VNC_PORT"

# --- push the sources and build ---------------------------------------------
log "pushing sources and building in the guest"
tar czf "$WORK/src.tgz" -C "$REPO" Sources Resources build.sh
base64 -i "$WORK/src.tgz" | tr -d '\n' > "$WORK/src.b64"
split -b 60000 "$WORK/src.b64" "$WORK/part-"
guest 'rm -rf ~/xfer && mkdir -p ~/xfer' >/dev/null
for f in "$WORK"/part-*; do
  "$TART" exec -i "$VM" bash -lc 'cat >> ~/xfer/src.b64' < "$f" || skip "transfer failed"
done
guest 'cd ~/xfer && base64 -D -i src.b64 -o src.tgz &&
       rm -rf ~/vision-ocr-src && mkdir -p ~/vision-ocr-src && tar xzf src.tgz -C ~/vision-ocr-src &&
       mkdir -p ~/vision-ocr && rsync -a --delete ~/vision-ocr-src/Sources/ ~/vision-ocr/Sources/ &&
       rsync -a ~/vision-ocr-src/Resources/ ~/vision-ocr/Resources/ && cp ~/vision-ocr-src/build.sh ~/vision-ocr/' >/dev/null
guest 'cd ~/vision-ocr && ./build.sh' | tail -1
guest "test -d ~/vision-ocr/build/VisionOCR.app" >/dev/null || skip "the app did not build"
guest 'command -v mac-ocr >/dev/null' >/dev/null || skip \
  "mac-ocr is not installed in the guest — tart exec $VM bash -lc 'npm install -g mac-ocr'"

# --- the window probe, filtered by pid --------------------------------------
guest 'cat > ~/windows.swift <<'"'"'EOF'"'"'
import CoreGraphics
import Foundation
let want = Int(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "0") ?? 0
let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
var onscreen = 0
var heights: [Int] = []
var rects: [(Int, String)] = []
for w in info {
    guard let pid = w[kCGWindowOwnerPID as String] as? Int, pid == want else { continue }
    let visible = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
    let layer = w[kCGWindowLayer as String] as? Int ?? -999
    if visible && layer == 0 {
        onscreen += 1
        let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let h = Int((b["Height"] as? Double) ?? 0)
        heights.append(h)
        // Tallest first: the main window, not a sheet stacked over it.
        rects.append((h, "\(Int((b["X"] as? Double) ?? 0)) \(Int((b["Y"] as? Double) ?? 0)) "
                       + "\(Int((b["Width"] as? Double) ?? 0)) \(h)"))
    }
}
print("\(onscreen) \(heights.sorted().map(String.init).joined(separator: ","))")
// Second line: the geometry of the tallest window, so the caller can aim at
// controls instead of hard-coding screen coordinates that drift the moment the
// layout changes. Hard-coded ones silently missed every click once already.
print(rects.sorted { $0.0 > $1.0 }.first?.1 ?? "0 0 0 0")
EOF
swiftc -O -o ~/windows ~/windows.swift' >/dev/null
# "<count> <h1,h2,...>" for the app's on-screen, normal-layer windows.
windowinfo() { guest "P=\$(cat ~/vision-ocr-pid 2>/dev/null); ~/windows \${P:-0}" | tail -2; }
windows()    { windowinfo | head -1 | awk '{print $1}'; }
heights()    { windowinfo | head -1 | awk '{print $2}'; }
windowrect() { windowinfo | tail -1; }          # "x y w h" of the main window

# Click a control by its offset from the window, not by absolute coordinates.
# The script hard-coded screen positions until a layout change moved every
# control and three checks failed with "the batch never started" — the clicks
# had simply landed on empty desktop.
click_in_window() {   # click_in_window <dx-from-right|+dx-from-left> <dy-from-top|-dy-from-bottom>
  local rect x y w h cx cy
  rect="$(windowrect)"; read -r x y w h <<<"$rect"
  if [ "${w:-0}" -lt 100 ]; then bad "no window to click in (rect: $rect)"; return 1; fi
  case "$1" in +*) cx=$(( x + ${1#+} )) ;; *) cx=$(( x + w - $1 )) ;; esac
  case "$2" in -*) cy=$(( y + h - ${2#-} )) ;; *) cy=$(( y + $2 )) ;; esac
  vnc move "$cx" "$cy" click 1
}

# A modal from a previous run, or a TCC prompt, steals every event that follows.
dismiss_prompts() { vnc key esc; sleep 1; vnc key esc; sleep 1; }

fixtures() {
  guest 'mkdir -p ~/scans
    if [ ! -f ~/scans/vmcheck.pdf ]; then
      cat > ~/mk.swift <<'"'"'EOF'"'"'
import AppKit
let out = URL(fileURLWithPath: CommandLine.arguments[1])
var box = CGRect(x: 0, y: 0, width: 612, height: 792)
let pdf = CGContext(out as CFURL, mediaBox: &box, nil)!
for p in 1...30 {
    let w = 1224, h = 1584
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
    let a: [NSAttributedString.Key: Any] = [.font: NSFont(name: "Helvetica", size: 40)!,
                                            .foregroundColor: NSColor.black]
    var y = CGFloat(h - 160)
    for i in 1...15 {
        ("Page \(p) line \(i): the quick brown fox jumps over the lazy dog" as NSString)
            .draw(at: NSPoint(x: 120, y: y), withAttributes: a); y -= 90
    }
    NSGraphicsContext.current?.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
    pdf.beginPDFPage(nil); pdf.draw(rep.cgImage!, in: box); pdf.endPDFPage()
}
pdf.closePDF()
EOF
      swift ~/mk.swift ~/scans/vmcheck.pdf
      cp ~/scans/vmcheck.pdf ~/scans/vmcheck2.pdf
      cp ~/scans/vmcheck.pdf ~/scans/vmcheck3.pdf
    fi' >/dev/null
}

launch() {   # launch [files…]; leaves the pid in ~/vision-ocr-pid
  guest "pkill -x VisionOCR; sleep 2
    rm -rf ~/Library/'Saved Application State'/$BUNDLE_ID.savedState
    defaults write $BUNDLE_ID besideOriginal -bool true
    defaults write $BUNDLE_ID mode -string 'searchable-pdf'
    defaults write $BUNDLE_ID openWhenDone -bool false
    defaults write $BUNDLE_ID concurrency -int 1
    defaults write $BUNDLE_ID warnDigitalText -bool false
    sleep 1
    open -a \"\$HOME/vision-ocr/build/VisionOCR.app\" $1
    sleep 7; pgrep -x VisionOCR > ~/vision-ocr-pid; cat ~/vision-ocr-pid" >/dev/null
}

fixtures
dismiss_prompts

# --- U17: one window stays one window ---------------------------------------
if [ "$LANE" = all ] || [ "$LANE" = windows ]; then
  log "U17 — Finder handing the app several files must not open several windows"
  launch ""
  bare="$(windows)"
  [ "$bare" = 1 ] && ok "a bare launch opens one window" || bad "bare launch: $bare windows"
  guest 'open -a "$HOME/vision-ocr/build/VisionOCR.app" ~/scans/vmcheck.pdf \
         ~/scans/vmcheck2.pdf ~/scans/vmcheck3.pdf; sleep 6' >/dev/null
  after="$(windows)"
  [ "$after" = 1 ] && ok "opening three files still leaves one window" \
                   || bad "three files opened $after windows (a WindowGroup regression)"
fi

# --- U13: the window comes back, showing the live batch ----------------------
if [ "$LANE" = all ] || [ "$LANE" = reopen ]; then
  log "U13 — closing the window mid-run must not lose the batch"
  launch "~/scans/vmcheck.pdf"
  click_in_window 64 -28; sleep 20             # Start OCR, bottom-right
  running="$(guest 'pgrep -x mac-ocr >/dev/null && echo yes || echo no')"
  [ "$running" = yes ] && ok "the batch starts" || bad "the batch never started"
  click_in_window +16 16; sleep 5              # the red close button, mid-run
  alive="$(guest 'pgrep -x VisionOCR >/dev/null && echo yes || echo no')"
  still="$(guest 'pgrep -x mac-ocr >/dev/null && echo yes || echo no')"
  [ "$alive" = yes ] && ok "the app survives the close" || bad "the app quit mid-run"
  [ "$still" = yes ] && ok "the batch keeps running" || bad "the batch died with the window"
  [ "$(windows)" = 0 ] && ok "the window really is gone" || bad "the window did not close"
  guest 'open -a "$HOME/vision-ocr/build/VisionOCR.app"'; sleep 5
  [ "$(windows)" = 1 ] && ok "a Dock click brings it back" \
                       || bad "reopen restored nothing — the U13 regression"
fi

# --- U15: Settings on a short display ---------------------------------------
if [ "$LANE" = all ] || [ "$LANE" = settings ]; then
  log "U15 — the Settings sheet must fit a display shorter than its ideal height"
  guest 'cat > ~/display.swift <<'"'"'EOF'"'"'
import CoreGraphics
import Foundation
let id = CGMainDisplayID()
let modes = CGDisplayCopyAllDisplayModes(id, nil) as? [CGDisplayMode] ?? []
let p = CommandLine.arguments[1].split(separator: "x")
guard let m = modes.first(where: { $0.width == Int(p[0])! && $0.height == Int(p[1])! })
else { print("no such mode"); exit(1) }
var c: CGDisplayConfigRef?
CGBeginDisplayConfiguration(&c)
CGConfigureDisplayWithDisplayMode(c, id, m, nil)
CGCompleteDisplayConfiguration(c, .permanently)
usleep(600_000)
let now = CGDisplayCopyDisplayMode(id)
print("\(now?.width ?? 0)x\(now?.height ?? 0)")
EOF
    swift ~/display.swift 1024x640' | tail -1
  launch ""
  click_in_window +66 -28; sleep 4             # the Settings button, bottom-left
  n="$(windows)"; hs="$(heights)"
  if [ "$n" = 2 ]; then
    ok "the sheet opens on a 640 pt display (heights: $hs)"
    # The shorter of the two is the sheet. Its ideal is 660 pt; on a 640 pt
    # screen it has to come back smaller or the Done footer is off the bottom.
    sheet="$(printf '%s' "$hs" | tr ',' '\n' | sort -n | head -1)"
    if [ "${sheet:-9999}" -lt 660 ]; then
      ok "...and it shrank below its 660 pt ideal (${sheet} pt)"
    else
      bad "the sheet is ${sheet} pt on a 640 pt display - Done is off-screen (U15)"
    fi
  else
    bad "expected the window plus the sheet, saw $n on-screen window(s)"
  fi
  vnc key esc; sleep 1
  guest 'swift ~/display.swift 1920x1200' >/dev/null
fi

log "vm-gui-check: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
