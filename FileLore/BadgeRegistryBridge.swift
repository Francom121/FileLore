import Foundation
import TetherCore

/// Badge registry bridge: publishes the set of noted files to the sandboxed
/// Finder Sync extension.
///
/// The Finder Sync extension cannot read the `com.filelore.note` xattr from
/// inside its sandbox, so it can't decide on its own which files deserve a
/// badge. The main app is NOT sandboxed and can read xattrs freely, so it
/// maintains `badge-registry.json` — one entry per noted file, keyed by
/// (st_dev, st_ino) — and mirrors it INTO the extension's container
/// (`~/Library/Containers/com.filelore.app.FinderSync/Data`), which the
/// extension can read. Matching by inode means badges survive renames and
/// moves on the same volume, exactly like the note xattr itself.
///
/// Refreshed after every note save/delete and once at app launch (which also
/// covers the "extension container didn't exist yet" case — the mirror write
/// is skipped silently when the container is missing and retried next launch).
@MainActor
enum BadgeRegistryBridge {

    /// One noted file. `path` is a debugging hint; matching is by (dev, ino).
    struct Entry: Codable, Equatable {
        var path: String
        var dev: UInt64  // st_dev
        var ino: UInt64  // st_ino
        var updatedAt: Date
    }

    /// Darwin notification posted after each successful bridge write so the
    /// extension reloads the registry immediately.
    static let darwinNotificationName = "com.filelore.app.badgesChanged"

    /// Canonical copy, next to `known-files.json`.
    private static var canonicalURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FileLore", isDirectory: true)
            .appendingPathComponent("badge-registry.json", isDirectory: false)
    }

    /// The extension container's `Data` directory, or `nil` when the
    /// container doesn't exist yet (extension never ran). Computed from the
    /// real home (`/Users/<name>`) — the app is unsandboxed, but
    /// `NSHomeDirectory()` could still be redirected in some launch contexts,
    /// so build it from the username like the extension does.
    private static var extensionContainerDataURL: URL? {
        let userName = NSUserName()
        guard !userName.isEmpty else { return nil }
        let container = URL(fileURLWithPath: "/Users/\(userName)", isDirectory: true)
            .appendingPathComponent("Library/Containers/com.filelore.app.FinderSync", isDirectory: true)
        guard FileManager.default.fileExists(atPath: container.path(percentEncoded: false)) else {
            return nil
        }
        return container.appendingPathComponent("Data", isDirectory: true)
    }

    /// Rebuilds the registry from `KnownFilesRegistry` + live xattr checks and
    /// writes both copies. Entries whose file vanished or lost its note are
    /// dropped. Never throws; failures are logged via NSLog.
    static func refresh() {
        let fileManager = FileManager.default
        var entries: [Entry] = []
        for known in KnownFilesRegistry.shared.entries {
            let path = known.path
            guard fileManager.fileExists(atPath: path),
                  NoteStore.hasNote(url: URL(fileURLWithPath: path)),
                  let attributes = try? fileManager.attributesOfItem(atPath: path),
                  let dev = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
                  let ino = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
            else { continue }
            entries.append(Entry(path: path, dev: dev, ino: ino, updatedAt: Date()))
        }

        do {
            try writeAtomically(entries: entries, to: canonicalURL)
        } catch {
            NSLog("FileLore: failed to write badge registry (canonical): \(error.localizedDescription)")
        }

        guard let containerData = extensionContainerDataURL else {
            // Extension never ran — nothing to mirror into. Retried on the
            // next refresh / app launch.
            return
        }
        let bridgeURL = containerData.appendingPathComponent("badge-registry.json", isDirectory: false)
        do {
            try fileManager.createDirectory(at: containerData, withIntermediateDirectories: true)
            try writeAtomically(entries: entries, to: bridgeURL)
            postBadgesChangedNotification()
        } catch {
            NSLog("FileLore: failed to write badge registry (extension container): \(error.localizedDescription)")
        }
    }

    // MARK: - Plumbing

    /// Atomic write: encode, write to a temp file in the same directory, then
    /// `rename(2)` over the destination so the extension never sees a torn file.
    private static func writeAtomically(entries: [Entry], to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(entries)

        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)", isDirectory: false)
        defer { try? fileManager.removeItem(at: tempURL) }

        try data.write(to: tempURL)
        if rename(tempURL.path(percentEncoded: false), url.path(percentEncoded: false)) != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "rename failed: \(String(cString: strerror(errno)))"
            ])
        }
    }

    private static func postBadgesChangedNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinNotificationName as CFString),
            nil,
            nil,
            true
        )
    }
}
