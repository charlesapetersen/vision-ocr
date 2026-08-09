// Can the window be got back after it is closed mid-run?
//
// This sat in TODO.md as the one genuinely unverified thing in the project,
// because it cannot be settled by reading: it depends on what AppKit does to a
// SwiftUI `WindowGroup` window after `performClose`. It is settled now, and the
// answer was that the shipped code did nothing at all.
//
//   BEFORE close  visible=true  canBecomeMain=true
//   AFTER  close  visible=false canBecomeMain=false      <-- the filter's target
//   after ordering it front, unfiltered:
//                 visible=true  canBecomeMain=true
//
// `applicationShouldHandleReopen` filtered candidates on `canBecomeMain`, which
// is false for exactly the window it needed to find, so a Dock click restored
// nothing and a batch the user had closed the window on was unreachable for the
// rest of its run. `AppDelegate.showMainWindow` drops the filter.
//
// Unlike the rest of Tools/, this does not compile against Sources/ — App.swift
// carries the app's own @main. The restore body below is a copy, and has to be
// kept in step with `AppDelegate.showMainWindow`.
//
//   swiftc -parse-as-library -module-name reopenprobe -o /tmp/reopen \
//     -target "$(uname -m)-apple-macos13.0" Tools/probe-window-reopen.swift
//   /tmp/reopen            # exit 0 = recoverable, 1 = not
//
// Output goes to stderr: stdout is block-buffered and `exit` swallows it.
import AppKit
import SwiftUI

func say(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

@discardableResult
func report(_ tag: String) -> Bool {
    say("\(tag): \(NSApp.windows.count) known, \(NSApp.windows.filter(\.isVisible).count) visible")
    for w in NSApp.windows {
        say("    \(type(of: w)) visible=\(w.isVisible) canBecomeMain=\(w.canBecomeMain)")
    }
    return NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
}

final class ProbeDelegate: NSObject, NSApplicationDelegate {
    /// What the app does mid-run: closing the last window must not quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }

    /// A copy of `AppDelegate.showMainWindow`.
    static func showMainWindow() {
        let window = NSApp.windows.first { $0.canBecomeMain }
            ?? NSApp.windows.first { !($0 is NSPanel) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The old body, kept so the difference stays visible.
    static func showMainWindowTheOldWay() {
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.close() }
    }

    func close() {
        report("BEFORE close")
        NSApp.windows.first { $0.canBecomeMain }?.performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.tryOld() }
    }

    func tryOld() {
        report("AFTER close")
        say("\n== the old reopen body: filtered on canBecomeMain ==")
        Self.showMainWindowTheOldWay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            say(report("after the old body")
                ? "  the old body worked"
                : "  the old body did nothing — nothing matched the filter")
            self.tryNew()
        }
    }

    func tryNew() {
        say("\n== showMainWindow ==")
        Self.showMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let back = report("after showMainWindow")
            say(back
                ? "\nRESULT: RECOVERABLE — a main-capable window is visible again"
                : "\nRESULT: NOT RECOVERABLE — a running batch would be unreachable")
            exit(back ? 0 : 1)
        }
    }
}

@main
struct ProbeApp: App {
    @NSApplicationDelegateAdaptor(ProbeDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup { Text("reopen probe").frame(width: 320, height: 200).padding() }
            .windowResizability(.contentMinSize)
    }
}
