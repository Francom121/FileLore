import Cocoa
import FinderSync
import TetherCore

/// Finder Sync extension: badges files that carry a Tether note and adds an
/// "Add/Edit Tether Note" context menu item that opens the note in the main app.
///
/// Badge decisions come from `badge-registry.json` (mirrored into this
/// sandbox's container by the main app and matched by inode via
/// `BadgeRegistryReader`) because sandboxed xattr reads fail; a direct
/// `NoteStore.hasNote` read remains as a last-resort fallback.
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
        DebugLog.log("init: \(BadgeRegistryReader.shared.statusDescription)")

        FinderSync.subscribeToBadgeChanges()
    }

    // MARK: - Badge change notification

    /// The main app posts this Darwin notification after each registry bridge
    /// write; reload the registry so the next badge request sees fresh data.
    private static func subscribeToBadgeChanges() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    DebugLog.log("darwin notification: com.tether.app.badgesChanged — reloading registry")
                    BadgeRegistryReader.shared.reload(reason: "Darwin notification")
                }
            },
            "com.tether.app.badgesChanged" as CFString,
            nil,
            .deliverImmediately
        )
    }

    // MARK: - Badges

    /// Finder only asks for badges in icon view (⌘1) and list view (⌘2) —
    /// macOS never renders Finder Sync badges in column view (⌘3) or gallery
    /// view, so silence here while browsing in column view is expected.
    ///
    /// Lookup order: (dev, ino) in the badge registry → sandboxed xattr read
    /// as a last-resort fallback (it fails for most paths but may work for
    /// Finder-handed URLs) → clear badge.
    override func requestBadgeIdentifier(for url: URL) {
        let path = url.path(percentEncoded: false)
        DebugLog.log("badge request: \(url.lastPathComponent) — \(BadgeRegistryReader.shared.statusDescription)")

        var hasNote = false
        var decision = "no note"

        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let dev = (attributes?[.systemNumber] as? NSNumber)?.uint64Value
        let ino = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
        if let dev, let ino {
            if BadgeRegistryReader.shared.contains(dev: dev, ino: ino) {
                hasNote = true
                decision = "registry match (dev=\(dev) ino=\(ino))"
                DebugLog.log("badge request: \(url.lastPathComponent) — \(decision)")
            } else {
                DebugLog.log("badge request: \(url.lastPathComponent) — stat dev=\(dev) ino=\(ino), no registry match; trying xattr fallback")
                hasNote = NoteStore.hasNote(url: url)
                decision = hasNote ? "xattr fallback hit" : "xattr fallback miss — clearing badge"
                DebugLog.log("badge request: \(url.lastPathComponent) — \(decision)")
            }
        } else {
            DebugLog.log("badge request: \(url.lastPathComponent) — stat failed for \(path); trying xattr fallback")
            hasNote = NoteStore.hasNote(url: url)
            decision = hasNote ? "xattr fallback hit" : "xattr fallback miss — clearing badge"
            DebugLog.log("badge request: \(url.lastPathComponent) — \(decision)")
        }

        NSLog("TetherFinderSync badge request for %@ — %@",
              url.lastPathComponent,
              decision)
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
