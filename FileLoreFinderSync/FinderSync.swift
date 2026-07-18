import Cocoa
import FinderSync
import TetherCore

/// Finder Sync extension: badges files that carry a FileLore note and adds an
/// "Add/Edit FileLore Note" context menu item that opens the note in the main app.
///
/// Badge decisions come from `badge-registry.json` (mirrored into this
/// sandbox's container by the main app and matched by inode via
/// `BadgeRegistryReader`) because sandboxed xattr reads fail; a direct
/// `NoteStore.hasNote` read remains as a last-resort fallback.
final class FinderSync: FIFinderSync {

    private static let badgeIdentifier = "FileLoreNote"

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

        NSLog("FileLoreFinderSync monitoring %@",
              urls.map { $0.path(percentEncoded: false) }.joined(separator: ", "))
        return urls
    }

    override init() {
        super.init()
        NSLog("FileLoreFinderSync launched from %@", Bundle.main.bundlePath as NSString)

        let monitored = FinderSync.monitoredDirectoryURLs()
        FIFinderSyncController.default().directoryURLs = Set(monitored)

        let image = FinderSync.badgeImage()
        FIFinderSyncController.default().setBadgeImage(
            image,
            label: "FileLore Note",
            forBadgeIdentifier: FinderSync.badgeIdentifier
        )

        DebugLog.log("init: log file = \(DebugLog.fileURL.path(percentEncoded: false))")
        DebugLog.log("init: monitoring = [\(monitored.map { $0.path(percentEncoded: false) }.joined(separator: ", "))]")
        DebugLog.log("init: isExtensionEnabled = \(FIFinderSyncController.isExtensionEnabled)")
        DebugLog.log("init: badge image valid = \(image.isValid), size = \(NSStringFromSize(image.size))")
        DebugLog.log("init: \(BadgeRegistryReader.shared.statusDescription)")

        FinderSync.installProactiveBadgeApply()
        FinderSync.subscribeToBadgeChanges()
    }

    // MARK: - Proactive badge apply

    /// URLs this extension badged proactively this session — diffed against
    /// the registry on every (re)load so dropped entries get cleared.
    private static var proactivelyBadgedURLs: Set<URL> = []

    /// Finder only asks for badges (`requestBadgeIdentifier`) while a folder
    /// is being browsed and does NOT re-ask after a note is saved, so badges
    /// decided lazily would stay stale until the user re-browses. Instead,
    /// every registry (re)load — initial load, mtime change, Darwin
    /// notification — pushes badges proactively: every registry path gets the
    /// badge, and URLs badged earlier this session that dropped out of the
    /// registry get cleared. Registry paths live under the monitored home
    /// directory, so setting badges by URL is allowed.
    private static func installProactiveBadgeApply() {
        BadgeRegistryReader.shared.onReload = { entries in
            DispatchQueue.main.async {
                FinderSync.applyBadgesProactively(entries: entries)
            }
        }
        // The reader's initial load already ran on the first `.shared` access
        // above, before `onReload` could be installed — reload once so the
        // current registry is applied immediately.
        BadgeRegistryReader.shared.reload(reason: "extension init")
    }

    /// Pushes the registry's badges to Finder directly. Main thread only.
    private static func applyBadgesProactively(entries: [BadgeRegistryReader.Entry]) {
        let controller = FIFinderSyncController.default()
        var currentURLs = Set<URL>()
        for entry in entries {
            let url = URL(fileURLWithPath: entry.path)
            currentURLs.insert(url)
            controller.setBadgeIdentifier(FinderSync.badgeIdentifier, for: url)
        }
        let staleURLs = proactivelyBadgedURLs.subtracting(currentURLs)
        for url in staleURLs {
            controller.setBadgeIdentifier("", for: url)
        }
        proactivelyBadgedURLs = currentURLs
        if !currentURLs.isEmpty {
            DebugLog.log("proactive: badged \(currentURLs.count) files")
        }
        if !staleURLs.isEmpty {
            DebugLog.log("proactive: cleared \(staleURLs.count) files")
        }
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
                    DebugLog.log("darwin notification: com.filelore.app.badgesChanged — reloading registry")
                    BadgeRegistryReader.shared.reload(reason: "Darwin notification")
                }
            },
            "com.filelore.app.badgesChanged" as CFString,
            nil,
            .deliverImmediately
        )
    }

    // MARK: - Badges

    /// The badge glyph bundled with this extension (the FileLore quill mark,
    /// rendered with transparency around the glyph), sized for Finder's
    /// badge slot. Falls back to the SF Symbol when the resource is missing.
    private static func badgeImage() -> NSImage {
        if let bundled = NSImage(named: "FileLoreBadge"), bundled.isValid {
            bundled.size = NSSize(width: 18, height: 18)
            return bundled
        }
        DebugLog.log("badge image: FileLoreBadge.png missing from appex resources — using SF Symbol fallback")
        return NSImage(systemSymbolName: "note.text", accessibilityDescription: "FileLore Note")
            ?? NSImage(named: NSImage.actionTemplateName)!
    }

    /// Finder only asks for badges in icon view (⌘1) and list view (⌘2) —
    /// macOS never renders Finder Sync badges in column view (⌘3) or gallery
    /// view, so silence here while browsing in column view is expected.
    ///
    /// Lookup order: (dev, ino) in the badge registry → standardized path
    /// match against the registry (survives stale inodes, e.g. a noted file
    /// replaced in place) → sandboxed xattr read as a last-resort fallback
    /// (it fails for most paths but may work for Finder-handed URLs) → clear
    /// badge.
    override func requestBadgeIdentifier(for url: URL) {
        let path = url.path(percentEncoded: false)
        DebugLog.log("badge request: \(url.lastPathComponent) — \(BadgeRegistryReader.shared.statusDescription)")

        var hasNote = false
        var decision = "no note"

        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let dev = (attributes?[.systemNumber] as? NSNumber)?.uint64Value
        let ino = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
        if let dev, let ino, BadgeRegistryReader.shared.contains(dev: dev, ino: ino) {
            hasNote = true
            decision = "registry match (dev=\(dev) ino=\(ino))"
            DebugLog.log("badge request: \(url.lastPathComponent) — \(decision)")
        } else {
            if let dev, let ino {
                DebugLog.log("badge request: \(url.lastPathComponent) — stat dev=\(dev) ino=\(ino), no registry match; trying path match")
            } else {
                DebugLog.log("badge request: \(url.lastPathComponent) — stat failed for \(path); trying path match")
            }
            if BadgeRegistryReader.shared.contains(path: path) {
                hasNote = true
                decision = "path match"
                DebugLog.log("badge request: \(url.lastPathComponent) — path match")
            } else {
                DebugLog.log("badge request: \(url.lastPathComponent) — no path match; trying xattr fallback")
                hasNote = NoteStore.hasNote(url: url)
                decision = hasNote ? "xattr fallback hit" : "xattr fallback miss — clearing badge"
                DebugLog.log("badge request: \(url.lastPathComponent) — \(decision)")
            }
        }

        NSLog("FileLoreFinderSync badge request for %@ — %@",
              url.lastPathComponent,
              decision)
        FIFinderSyncController.default().setBadgeIdentifier(
            hasNote ? FinderSync.badgeIdentifier : "",
            for: url
        )
    }

    // MARK: - Toolbar item

    override var toolbarItemName: String { "FileLore" }

    override var toolbarItemToolTip: String { "FileLore: add or edit the sticky note for this file" }

    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "note.text", accessibilityDescription: "FileLore") ?? NSImage()
    }

    // MARK: - Context menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        DebugLog.log("menu requested: kind = \(menuKind.rawValue) (\(FinderSync.describe(menuKind)))")
        let menu = NSMenu(title: "")
        let item = NSMenuItem(
            title: "Add/Edit FileLore Note",
            action: #selector(openFileLoreNote(_:)),
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)

        // Multi-selection gets a batch item: the file list is handed to the
        // app through a JSON file in this container's tmp dir.
        let selectionCount = FIFinderSyncController.default().selectedItemURLs()?.count ?? 0
        if selectionCount > 1 {
            let batchItem = NSMenuItem(
                title: "Batch Tag with FileLore…",
                action: #selector(batchTagWithFileLore(_:)),
                keyEquivalent: ""
            )
            batchItem.target = self
            menu.addItem(batchItem)
        }
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

    /// The `.app` bundle that contains this extension, derived from
    /// `Bundle.main.bundleURL` (`FileLore.app/Contents/PlugIns/FileLoreFinderSync.appex`
    /// → three parents up). Opening `filelore://` URLs *at this app specifically*
    /// (instead of letting LaunchServices pick a handler) guarantees the copy
    /// that was just built receives the link — no ambiguity when stale FileLore
    /// processes or old builds are still running.
    private static var containerAppURL: URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent() // → Contents/PlugIns
            .deletingLastPathComponent() // → Contents
            .deletingLastPathComponent() // → FileLore.app
    }

    /// Opens a `filelore://` URL in this extension's own container app.
    private static func openInContainerApp(_ url: URL) {
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: containerAppURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    @IBAction func openFileLoreNote(_ sender: AnyObject?) {
        let controller = FIFinderSyncController.default()
        var urls = controller.selectedItemURLs() ?? []
        if urls.isEmpty, let target = controller.targetedURL() {
            urls = [target]
        }
        guard let fileURL = urls.first else { return }

        var components = URLComponents()
        components.scheme = "filelore"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: fileURL.path(percentEncoded: false))]
        if let url = components.url {
            Self.openInContainerApp(url)
        }
    }

    /// Multi-selection: write the selected paths as JSON into this container's
    /// tmp directory, then open `filelore://batch?ref=<filename>`. The
    /// (unsandboxed) main app reads the file back (`BatchRequestLoader`) and
    /// opens the batch editor; this keeps arbitrarily long file lists out of
    /// the URL itself.
    @IBAction func batchTagWithFileLore(_ sender: AnyObject?) {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(), urls.count > 1 else { return }

        let ref = "filelore-batch-\(UUID().uuidString).json"
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(ref, isDirectory: false)
        do {
            let paths = urls.map { $0.path(percentEncoded: false) }
            try JSONEncoder().encode(paths).write(to: fileURL, options: .atomic)
        } catch {
            DebugLog.log("batch: failed to write paths file \(fileURL.path): \(error.localizedDescription)")
            return
        }

        var components = URLComponents()
        components.scheme = "filelore"
        components.host = "batch"
        components.queryItems = [URLQueryItem(name: "ref", value: ref)]
        if let url = components.url {
            Self.openInContainerApp(url)
        }
    }
}
