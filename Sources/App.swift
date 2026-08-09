import AppKit
import SwiftUI

/// Stops the OCR children on the way out.
///
/// A child of a process that exits is reparented to launchd rather than killed,
/// so quitting mid-run left mac-ocr, jbig2 and qpdf running invisibly — on a
/// large book, for minutes. Cancelling first also means the scratch directory
/// gets cleaned up by the run's own `defer` instead of being abandoned in
/// `NSTemporaryDirectory()`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard RunControl.isAnyRunning else { return .terminateNow }

        // Ask, rather than silently discarding work. A batch over a few hundred
        // archival pages is long enough that quitting is usually a mistake.
        let alert = NSAlert()
        alert.messageText = "OCR is still running."
        alert.informativeText = "Quitting now stops it. Files already finished keep "
            + "their output; the one in progress is discarded rather than left "
            + "half-written."
        alert.addButton(withTitle: "Quit and Stop")
        alert.addButton(withTitle: "Keep Running")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }

        RunControl.cancelAll()

        // Give the children a moment to actually die and the workers a moment to
        // unwind, so each run's `defer` removes its scratch directory. Bounded,
        // because a quit that hangs is worse than a stray temporary file — and
        // `NSTemporaryDirectory()` is swept by the OS regardless.
        let deadline = Date().addingTimeInterval(2)
        while RunControl.isAnyRunning, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return .terminateNow
    }

    /// Closing the window quits — but only when there is nothing running.
    ///
    /// Returning an unconditional true meant closing the window mid-run started a
    /// termination, and choosing "Keep Running" at the prompt left a windowless
    /// app with an invisible batch that could no longer be cancelled or even
    /// observed. While a run is live the app stays up instead, and
    /// `applicationShouldHandleReopen` brings the window back so it remains
    /// reachable.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !RunControl.isAnyRunning
    }

    /// Clicking the Dock icon with no window open restores one, which is how the
    /// user gets back to a batch they closed the window on.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { Self.showMainWindow() }
        return true
    }

    /// Brings the main window back, whether it is merely hidden or has been
    /// closed outright.
    ///
    /// **This used to filter on `canBecomeMain`, and that made it a no-op.** A
    /// closed `WindowGroup` window survives in `NSApp.windows` but reports
    /// `canBecomeMain == false` until it is ordered front again, so the lookup
    /// found nothing, nothing was restored, and a batch the user had closed the
    /// window on was unreachable for the rest of its run — exactly the failure
    /// U3 was supposed to have fixed. Measured with
    /// `Tools/probe-window-reopen.swift`: before the close the window reports
    /// `visible=true canBecomeMain=true`; after it, `visible=false
    /// canBecomeMain=false`; ordering it front unfiltered brings it back to
    /// `visible=true canBecomeMain=true`.
    ///
    /// Prefer a main-capable window when there is one (the common case: the
    /// window is open but buried), and otherwise take the first window that is
    /// not a panel — sheets and alerts are panels, and ordering one of those
    /// front would leave the batch just as invisible.
    static func showMainWindow() {
        let window = NSApp.windows.first { $0.canBecomeMain }
            ?? NSApp.windows.first { !($0 is NSPanel) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Files dropped on the Dock icon, or opened with "Open With".
    ///
    /// `Info.plist` advertises PDFs and images as document types, so Finder
    /// highlights the Dock icon and lists the app under "Open With" — and both
    /// gestures used to do nothing at all, because nothing implemented this.
    func application(_ application: NSApplication, open urls: [URL]) {
        NotificationCenter.default.post(name: .visionOCROpenFiles,
                                        object: nil, userInfo: ["urls": urls])
    }
}

@main
struct VisionOCRApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// The batch, owned by the app rather than by the window.
    ///
    /// It used to be a `@StateObject` inside `ContentView`, which made the
    /// running batch a property of a *window*. Two consequences, both measured
    /// in the VM:
    ///
    /// 1. Every window had its own `OCRModel`, so two windows could each Start a
    ///    batch over the same files. `uniqueOutputs` only de-conflicts within one
    ///    batch, so both would claim `scan.ocr.pdf` and race to write it — the
    ///    C8/R18 class of defect, reachable by dropping files twice.
    /// 2. Closing the window mid-run destroyed the model. The batch survived
    ///    (the operations hold the `RunControl` strongly) but became
    ///    unobservable: `finish` never ran, so no log, no summary, and reopening
    ///    gave a blank window while the OCR ground on invisibly. That is the
    ///    failure U3 and U13 are both about, arriving by a third route.
    ///
    /// One model for the process, which is what the rest of the design already
    /// assumed — `RunControl`'s registry is global, File ▸ New Window is
    /// removed, and the quit prompt speaks for the app rather than a window.
    @StateObject private var model = OCRModel()

    init() { Prefs.register() }

    /// Identifier for the one window, so `openWindow` can bring it back.
    static let mainWindowID = "main"

    var body: some Scene {
        // `Window`, not `WindowGroup`. A WindowGroup is a *template*: macOS opens
        // a fresh instance of it for every document handed to the app, so
        // selecting three scans in Finder and choosing Open With produced four
        // windows — measured — on top of the delegate's own handling, which had
        // already added all three files to every window that existed. This app
        // has one window by design and now says so in the type.
        Window("Vision OCR", id: Self.mainWindowID) {
            ContentView(model: model)
        }
        .windowResizability(.contentMinSize)
        .commands {
            // Nothing useful under New/Open for a drop-box app.
            CommandGroup(replacing: .newItem) {}

            // The only route back to a closed window used to be a Dock click:
            // File ▸ New Window is removed above and there is no Settings
            // scene, so a keyboard-only user had none at all.
            //
            // `openWindow`, not the AppKit route the delegate uses: this has to
            // work when the window has been closed outright, and only SwiftUI
            // can rebuild a scene it destroyed. The delegate keeps
            // `showMainWindow` because an `NSApplicationDelegate` has no
            // environment to read `openWindow` from.
            CommandGroup(after: .windowArrangement) { ShowMainWindowCommand() }
        }
    }
}

/// Window ▸ Vision OCR Window (⌘0).
///
/// Its own type so it can hold `@Environment(\.openWindow)`, which is available
/// to a `Commands` body even when no window exists — which is exactly the case
/// it has to serve.
private struct ShowMainWindowCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Vision OCR Window") {
            openWindow(id: VisionOCRApp.mainWindowID)
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("0", modifiers: .command)
    }
}
