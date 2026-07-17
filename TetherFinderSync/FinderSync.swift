import Cocoa
import FinderSync
import TetherCore

/// Finder Sync extension: badges files that carry a Tether note and adds an
/// "Add/Edit Tether Note" context menu item that opens the note in the main app.
final class FinderSync: FIFinderSync {

    private static let badgeIdentifier = "TetherNote"

    override init() {
        super.init()
        NSLog("TetherFinderSync launched from %@", Bundle.main.bundlePath as NSString)

        // Watch the user's home directory.
        FIFinderSyncController.default().directoryURLs = [FileManager.default.homeDirectoryForCurrentUser]

        let image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Tether Note")
            ?? NSImage(named: NSImage.actionTemplateName)!
        FIFinderSyncController.default().setBadgeImage(
            image,
            label: "Tether Note",
            forBadgeIdentifier: FinderSync.badgeIdentifier
        )
    }

    // MARK: - Badges

    override func requestBadgeIdentifier(for url: URL) {
        let hasNote = NoteStore.hasNote(url: url)
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
