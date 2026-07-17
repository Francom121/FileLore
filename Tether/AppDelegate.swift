import AppKit

/// Central app delegate: global ⌥T hotkey, Services menu handler, and robust
/// incoming-URL routing (Finder Sync `tether://` links, Dock-icon drops).
///
/// All "open the note editor" paths funnel through `WindowRouter`, so they
/// work no matter which windows currently exist.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKeyManager.shared.onHotKey = { [weak self] in
            self?.openNoteForFinderSelection()
        }
        HotKeyManager.shared.register()
        NSApp.servicesProvider = self
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregister()
    }

    /// Clicking the Dock icon with no windows open reopens the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WindowRouter.shared.openMainWindow()
        }
        return true
    }

    // MARK: - Incoming URLs (Bug 4: robust when the main window is closed)

    /// Receives `tether://open?path=...` links (Finder Sync context menu) and
    /// file URLs (Dock-icon drops, `open -a Tether file`). Delivered by the
    /// system whether or not any window exists, unlike scene-level `onOpenURL`.
    func application(_ application: NSApplication, open urls: [URL]) {
        // Deferred one runloop turn so SwiftUI scenes have a chance to register
        // their openWindow action with WindowRouter first (launch-time case).
        DispatchQueue.main.async {
            for url in urls {
                if url.scheme == "tether", let fileURL = TetherURLRouter.fileURL(from: url) {
                    WindowRouter.shared.openNoteEditor(for: fileURL)
                } else if url.isFileURL {
                    WindowRouter.shared.openNoteEditor(for: url)
                }
            }
        }
    }

    // MARK: - Services menu ("Open Tether Note")

    /// Handles the "Open Tether Note" service from Finder's right-click →
    /// Services / Quick Actions menu (and any app that sends filenames).
    @objc func openTetherNoteService(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let urls = Self.fileURLs(from: pboard)
        guard let first = urls.first else {
            error.pointee = "No file was provided to the Open Tether Note service." as NSString
            return
        }
        WindowRouter.shared.openNoteEditor(for: first)
    }

    private static func fileURLs(from pboard: NSPasteboard) -> [URL] {
        if let filenames = pboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String],
           !filenames.isEmpty {
            return filenames.map { URL(fileURLWithPath: $0) }
        }
        if let urls = pboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            return urls
        }
        return []
    }

    // MARK: - ⌥T → note editor for the current Finder selection

    private enum FinderSelectionError: LocalizedError {
        case automationDenied
        case scriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .automationDenied:
                return "Tether is not allowed to control Finder. Grant access in " +
                    "System Settings → Privacy & Security → Automation, then press ⌥T again."
            case .scriptFailed(let message):
                return message
            }
        }
    }

    /// ⌥T handler: reads Finder's current selection via AppleScript and opens
    /// the note editor for the first selected file.
    func openNoteForFinderSelection() {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").isEmpty else {
            WindowRouter.shared.openMainWindow()
            showAlert(
                title: "Finder Isn't Running",
                message: "Tether reads the selected file from Finder. Open Finder, select a file, and press ⌥T again."
            )
            return
        }

        Self.fetchFinderSelection { [weak self] result in
            switch result {
            case .success(let paths):
                if let path = paths.first {
                    WindowRouter.shared.openNoteEditor(for: URL(fileURLWithPath: path))
                } else {
                    WindowRouter.shared.openMainWindow()
                    self?.showAlert(
                        title: "No File Selected in Finder",
                        message: "Select a file in a Finder window, then press ⌥T to open its Tether note."
                    )
                }
            case .failure(let error):
                self?.showAlert(title: "Tether Can't Access Finder", message: error.localizedDescription)
            }
        }
    }

    /// Returns the POSIX paths of Finder's current selection (may be empty).
    /// Runs off the main thread: the first execution may block on the one-time
    /// "Tether wants to control Finder" permission dialog.
    private static func fetchFinderSelection(
        completion: @escaping @MainActor (Result<[String], Error>) -> Void
    ) {
        let source = """
        tell application "Finder"
            try
                set selItems to selection as alias list
            on error
                return ""
            end try
            set outPaths to {}
            repeat with selItem in selItems
                set end of outPaths to POSIX path of selItem
            end repeat
            set AppleScript's text item delimiters to linefeed
            return outPaths as string
        end tell
        """

        DispatchQueue.global(qos: .userInitiated).async {
            func finish(_ result: Result<[String], Error>) {
                DispatchQueue.main.async { completion(result) }
            }
            guard let script = NSAppleScript(source: source) else {
                finish(.failure(FinderSelectionError.scriptFailed("Could not compile the Finder selection script.")))
                return
            }
            var errorDict: NSDictionary?
            let output = script.executeAndReturnError(&errorDict)
            if let errorDict {
                let code = (errorDict[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
                let message = (errorDict[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error (\(code))."
                finish(.failure(code == -1743
                    ? FinderSelectionError.automationDenied
                    : FinderSelectionError.scriptFailed(message)))
                return
            }
            let paths = (output.stringValue ?? "")
                .split(separator: "\n")
                .map { String($0) }
                .filter { !$0.isEmpty }
            finish(.success(paths))
        }
    }

    // MARK: - Alerts

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }
}
