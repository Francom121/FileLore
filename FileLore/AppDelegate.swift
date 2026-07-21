import AppKit
import TetherCore

/// Central app delegate: global hotkey (default ⌥T), Services menu handler,
/// and robust incoming-URL routing (Finder Sync `filelore://` links, Dock-icon drops).
///
/// All "open the note editor" paths funnel through `WindowRouter`, so they
/// work no matter which windows currently exist.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// The currently bound global shortcut, for user-facing messages.
    private var shortcutDisplay: String { GlobalShortcutStore.load().displayString }

    /// Set once the launch-time drop-zone decision has been made (0.5s after
    /// didFinishLaunching). Open requests only matter to that decision while
    /// the launch is still settling.
    private var launchSettled = false
    /// An open request (file/URL open or Services invocation) arrived while
    /// this launch was still settling: the launch exists to open something,
    /// so the launch-time logic must not also show the drop zone.
    private var openRequestArrivedDuringLaunch = false

    /// Records an incoming open request for the launch-time drop-zone logic.
    private func noteOpenRequest() {
        if !launchSettled {
            openRequestArrivedDuringLaunch = true
        }
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Rename migration: move the Tether-era App Support directory before
        // anything touches it (KnownFilesRegistry/BadgeRegistryBridge).
        Self.migrateApplicationSupportFromTetherIfNeeded()

        HotKeyManager.shared.onHotKey = { [weak self] in
            self?.openNoteForFinderSelection()
        }
        HotKeyManager.shared.onSearchHotKey = {
            WindowRouter.shared.openSearch()
        }
        HotKeyManager.shared.register()
        NSApp.servicesProvider = self
        // Publish the badge registry to the Finder Sync extension (also the
        // retry point for when its container didn't exist on earlier runs).
        BadgeRegistryBridge.refresh()

        // The drop zone is opened explicitly, here: plain cold launch
        // (Dock / Finder / login item) shows exactly one drop zone — by
        // design the app's landing window, also alongside any restored
        // editor windows. A launch that arrived carrying an open request
        // (see `openRequestArrivedDuringLaunch`) skips it: that launch
        // shows only the requested editor. Deferred briefly (not one
        // runloop turn) because a Services invocation can land slightly
        // after didFinishLaunching; 0.5s is imperceptible for a landing
        // window. openMainWindow is single-instance, so this can never
        // create a second drop zone.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.launchSettled = true
            guard !self.openRequestArrivedDuringLaunch else {
                return
            }
            WindowRouter.shared.openMainWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregister()
    }

    /// Clicking the Dock icon with no windows open reopens the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Double-window fix: this delegate call also fires *during launch*
            // (Dock-icon launches), before SwiftUI has materialized the
            // WindowGroup's first window — hasVisibleWindows is false even
            // though a window is about to appear. Opening the main window
            // right here would race SwiftUI and produce a second window.
            // Defer one runloop turn and re-check for any visible non-panel
            // window; only then open. Also skip when this launch/reopen is
            // delivering an open request — that path shows only the editor.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.openRequestArrivedDuringLaunch else {
                    return
                }
                let hasVisibleWindow = NSApp.windows.contains { window in
                    window.isVisible && !(window is NSPanel)
                }
                if !hasVisibleWindow {
                    WindowRouter.shared.openMainWindow()
                }
            }
        }
        return true
    }

    // MARK: - Rename migration (Tether → FileLore)

    /// One-time migration of `~/Library/Application Support/Tether` to
    /// `~/Library/Application Support/FileLore`. A plain move when the new
    /// directory doesn't exist yet; otherwise the known files are merged in
    /// (never overwriting a newer FileLore copy) and the legacy directory is
    /// left in place for the user to inspect/delete.
    private static func migrateApplicationSupportFromTetherIfNeeded() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacyURL = appSupport.appendingPathComponent("Tether", isDirectory: true)
        let currentURL = appSupport.appendingPathComponent("FileLore", isDirectory: true)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: legacyURL.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue else { return }

        if !fileManager.fileExists(atPath: currentURL.path(percentEncoded: false)) {
            do {
                try fileManager.moveItem(at: legacyURL, to: currentURL)
                NSLog("FileLore: migrated App Support directory from Tether")
            } catch {
                NSLog("FileLore: failed to migrate App Support directory: \(error.localizedDescription)")
            }
            return
        }

        // Both exist: merge-copy the registries, preferring the FileLore copy.
        for name in ["known-files.json", "badge-registry.json"] {
            let source = legacyURL.appendingPathComponent(name, isDirectory: false)
            let destination = currentURL.appendingPathComponent(name, isDirectory: false)
            guard fileManager.fileExists(atPath: source.path(percentEncoded: false)),
                  !fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else { continue }
            do {
                try fileManager.copyItem(at: source, to: destination)
                NSLog("FileLore: merge-copied \(name) from the Tether App Support directory")
            } catch {
                NSLog("FileLore: failed to merge-copy \(name): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Incoming URLs (Bug 4: robust when the main window is closed)

    /// Receives `filelore://open?path=...` / `filelore://batch?ref=...` links
    /// (Finder Sync context menu) and file URLs (Dock-icon drops,
    /// `open -a FileLore file`). Delivered by the system whether or not any
    /// window exists, unlike scene-level `onOpenURL`.
    func application(_ application: NSApplication, open urls: [URL]) {
        // Stamp first, before any deferral: the launch-time drop-zone logic
        // reads this to learn the launch exists to open something.
        if !urls.isEmpty {
            noteOpenRequest()
        }
        // Deferred one runloop turn so SwiftUI scenes have a chance to register
        // their openWindow action with WindowRouter first (launch-time case).
        DispatchQueue.main.async {
            // Dropping several files at once (or `open -a FileLore a b c`) opens
            // one batch editor instead of N single editors.
            if case .batch(let batchURLs) = IntakeRouter.decide(urls: urls.filter(\.isFileURL)) {
                WindowRouter.shared.openBatchEditor(for: batchURLs)
                return
            }
            for url in urls {
                if url.scheme == "filelore", let batchURLs = BatchRequestLoader.fileURLs(from: url) {
                    WindowRouter.shared.openBatchEditor(for: batchURLs)
                } else if url.scheme == "filelore", let fileURL = FileLoreURLRouter.fileURL(from: url) {
                    WindowRouter.shared.openNoteEditor(for: fileURL)
                } else if url.isFileURL {
                    WindowRouter.shared.openNoteEditor(for: url)
                } else if url.scheme == "filelore" {
                    // Unknown filelore:// link: never drop it silently. This is
                    // typically app/extension version skew during development
                    // (an older process received a newer link format).
                    NSLog("FileLore: unrecognized filelore URL: %@", url.absoluteString)
                    self.showAlert(
                        title: "FileLore Doesn't Understand That Link",
                        message: "This FileLore version doesn't understand that link. If you just rebuilt, relaunch the app (⌘R) and try again."
                    )
                }
            }
        }
    }

    // MARK: - Services menu ("Open FileLore Note")

    /// Handles the "Open FileLore Note" service from Finder's right-click →
    /// Services / Quick Actions menu (and any app that sends filenames).
    /// A multi-file selection opens the batch editor (same note + tags applied
    /// to every file) instead of only the first file's editor.
    @objc func openFileLoreNoteService(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let urls = Self.fileURLs(from: pboard)
        guard !urls.isEmpty else {
            error.pointee = "No file was provided to the Open FileLore Note service." as NSString
            return
        }
        // Stamp like any other open request: when the Service launched the
        // app, the launch-time drop-zone logic must stay out of the way.
        noteOpenRequest()
        switch IntakeRouter.decide(urls: urls) {
        case .batch(let batchURLs):
            WindowRouter.shared.openBatchEditor(for: batchURLs)
        case .single(let fileURL):
            WindowRouter.shared.openNoteEditor(for: fileURL)
        case .none:
            break // Unreachable: urls is non-empty, so the decision can't be .none.
        }
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

    // MARK: - Hotkey → note editor for the current Finder selection

    private enum FinderSelectionError: LocalizedError {
        case automationDenied
        case scriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .automationDenied:
                return "FileLore is not allowed to control Finder. Grant access in " +
                    "System Settings → Privacy & Security → Automation, then press " +
                    "\(GlobalShortcutStore.load().displayString) again."
            case .scriptFailed(let message):
                return message
            }
        }
    }

    /// Hotkey handler: reads Finder's current selection via AppleScript and opens
    /// the note editor for it — a multi-file selection opens the batch editor
    /// (same note + tags applied to every selected file).
    func openNoteForFinderSelection() {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").isEmpty else {
            WindowRouter.shared.openMainWindow()
            showAlert(
                title: "Finder Isn't Running",
                message: "FileLore reads the selected file from Finder. Open Finder, select a file, and press \(shortcutDisplay) again."
            )
            return
        }

        Self.fetchFinderSelection { [weak self] result in
            switch result {
            case .success(let paths):
                switch IntakeRouter.decide(paths: paths) {
                case .single(let fileURL):
                    WindowRouter.shared.openNoteEditor(for: fileURL)
                case .batch(let batchURLs):
                    WindowRouter.shared.openBatchEditor(for: batchURLs)
                case .none:
                    WindowRouter.shared.openMainWindow()
                    self?.showAlert(
                        title: "No File Selected in Finder",
                        message: "Select a file in a Finder window, then press \(self?.shortcutDisplay ?? "the FileLore shortcut") to open its FileLore note."
                    )
                }
            case .failure(let error):
                self?.showAlert(title: "FileLore Can't Access Finder", message: error.localizedDescription)
            }
        }
    }

    /// Returns the POSIX paths of Finder's current selection (may be empty).
    /// Runs off the main thread: the first execution may block on the one-time
    /// "FileLore wants to control Finder" permission dialog.
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
