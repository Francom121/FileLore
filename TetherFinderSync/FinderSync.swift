import Cocoa
import FinderSync
import TetherCore

/// Finder Sync extension: badges files that carry a Tether note and adds an
/// "Add/Edit Tether Note" context menu item that opens the note in the main app.
final class FinderSync: FIFinderSync {

    private static let badgeIdentifier = "TetherNote"

    /// Directories Finder should observe for badges and context menus.
    ///
    /// The extension is sandboxed, so `homeDirectoryForCurrentUser` /
    /// `NSHomeDirectory()` return the sandbox container, not the real home —
    /// derive the real home from the logged-in username instead. iCloud Drive's
    /// "Desktop & Documents Folders" sync keeps the real files under
    /// `~/Library/Mobile Documents/com~apple~CloudDocs`, which Finder displays
    /// by that path, so those folders are monitored explicitly when present.
    private static func monitoredDirectoryURLs() -> [URL] {
        let fileManager = FileManager.default

        let userName = NSUserName()
        let realHome: URL
        if !userName.isEmpty,
           fileManager.fileExists(atPath: "/Users/\(userName)") {
            realHome = URL(fileURLWithPath: "/Users/\(userName)", isDirectory: true)
        } else {
            realHome = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        }

        var urls = [realHome]

        let cloudDocs = realHome.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        for folder in ["Documents", "Desktop"] {
            let url = cloudDocs.appendingPathComponent(folder, isDirectory: true)
            if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
                urls.append(url)
            }
        }

        NSLog("TetherFinderSync monitoring %@",
              urls.map { $0.path(percentEncoded: false) }.joined(separator: ", "))
        return urls
    }

    override init() {
        super.init()
        NSLog("TetherFinderSync launched from %@", Bundle.main.bundlePath as NSString)

        let monitored = FinderSync.monitoredDirectoryURLs()
        FIFinderSyncController.default().directoryURLs = Set(monitored)

        let image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Tether Note")
            ?? NSImage(named: NSImage.actionTemplateName)!
        FIFinderSyncController.default().setBadgeImage(
            image,
            label: "Tether Note",
            forBadgeIdentifier: FinderSync.badgeIdentifier
        )

        DebugLog.log("init: log file = \(DebugLog.fileURL.path(percentEncoded: false))")
        DebugLog.log("init: monitoring = [\(monitored.map { $0.path(percentEncoded: false) }.joined(separator: ", "))]")
        DebugLog.log("init: isExtensionEnabled = \(FIFinderSyncController.isExtensionEnabled)")
        DebugLog.log("init: badge image valid = \(image.isValid), size = \(NSStringFromSize(image.size))")

        FinderSync.runForcedBadgeProbe()
    }

    // MARK: - TEMPORARY forced-badge diagnostic (remove once the badge pipeline is understood)

    /// Probes a hardcoded known-noted file and sets the badge on it directly,
    /// without waiting for Finder to call `requestBadgeIdentifier(for:)`.
    /// Distinguishes "Finder never asks for a badge" from "badge is set but
    /// doesn't render".
    private static func runForcedBadgeProbe() {
        let url = URL(fileURLWithPath: "/Users/fm/Documents/TagPanda/Social Media/tagpanda promo1.mp4")
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            DebugLog.log("init: forced-badge probe — file missing: \(url.path(percentEncoded: false))")
            return
        }
        let hasNote = NoteStore.hasNote(url: url)
        DebugLog.log("init: forced-badge probe — \(url.lastPathComponent) exists, hasNote = \(hasNote)")
        if hasNote {
            FIFinderSyncController.default().setBadgeIdentifier(FinderSync.badgeIdentifier, for: url)
            DebugLog.log("init: forced badge set for \(url.lastPathComponent)")
        }
    }

    // MARK: - Badges

    /// Finder only asks for badges in icon view (⌘1) and list view (⌘2) —
    /// macOS never renders Finder Sync badges in column view (⌘3) or gallery
    /// view, so silence here while browsing in column view is expected.
    override func requestBadgeIdentifier(for url: URL) {
        // Read directly (rather than via `hasNote`) so the log can tell
        // "no note on this file" apart from "note read failed".
        let hasNote: Bool
        do {
            if try NoteStore.read(url: url) != nil {
                hasNote = true
                DebugLog.log("badge request: \(url.lastPathComponent) — note found")
            } else {
                hasNote = false
                DebugLog.log("badge request: \(url.lastPathComponent) — read returned nil (no note)")
            }
        } catch {
            hasNote = false
            DebugLog.log("badge request: \(url.lastPathComponent) — read threw: \(error.localizedDescription)")
        }
        NSLog("TetherFinderSync badge request for %@ — note found: %@",
              url.lastPathComponent,
              hasNote ? "yes" : "no")
        FIFinderSyncController.default().setBadgeIdentifier(
            hasNote ? FinderSync.badgeIdentifier : "",
            for: url
        )
    }

    // MARK: - Toolbar item

    override var toolbarItemName: String { "Tether" }

    override var toolbarItemToolTip: String { "Tether: add or edit the sticky note for this file" }

    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "note.text", accessibilityDescription: "Tether") ?? NSImage()
    }

    // MARK: - Context menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        DebugLog.log("menu requested: kind = \(menuKind.rawValue) (\(FinderSync.describe(menuKind)))")
        let menu = NSMenu(title: "")
        let item = NSMenuItem(
            title: "Add/Edit Tether Note",
            action: #selector(openTetherNote(_:)),
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)
        return menu
    }

    /// Human-readable `FIMenuKind` for the debug log.
    private static func describe(_ kind: FIMenuKind) -> String {
        switch kind {
        case .contextualMenuForItems: return "contextualMenuForItems"
        case .contextualMenuForContainer: return "contextualMenuForContainer"
        case .contextualMenuForSidebar: return "contextualMenuForSidebar"
        case .toolbarItemMenu: return "toolbarItemMenu"
        @unknown default: return "unknown"
        }
    }

    @IBAction func openTetherNote(_ sender: AnyObject?) {
        let controller = FIFinderSyncController.default()
        var urls = controller.selectedItemURLs() ?? []
        if urls.isEmpty, let target = controller.targetedURL() {
            urls = [target]
        }
        guard let fileURL = urls.first else { return }

        var components = URLComponents()
        components.scheme = "tether"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: fileURL.path(percentEncoded: false))]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }
}
