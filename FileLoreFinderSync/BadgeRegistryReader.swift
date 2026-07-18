import Foundation

/// Reads the badge registry the main app mirrors into this extension's
/// container.
///
/// The extension is sandboxed and CANNOT read the `com.filelore.note` xattr, so
/// badge decisions come from `badge-registry.json`, which the (unsandboxed)
/// main app writes into this container's `Data` directory after every note
/// save/delete and at app launch. Inside the sandbox
/// `homeDirectoryForCurrentUser` IS that `Data` directory (same trick as
/// `DebugLog`), so the file is always readable here.
///
/// Entries are matched by (st_dev, st_ino), so badges survive renames and
/// moves on the same volume; a standardized-path match remains as a fallback
/// when an entry's inode went stale (e.g. the noted file was replaced in
/// place). The decoded entries are cached and reloaded when the file's
/// modification date changes (cheap `attributesOfItem` check per lookup) or
/// when the main app's Darwin notification
/// (`com.filelore.app.badgesChanged`) fires. Every (re)load — initial load
/// included — notifies `onReload` with the fresh entries so observers can
/// push badges proactively instead of waiting for Finder to re-ask.
final class BadgeRegistryReader {

    static let shared = BadgeRegistryReader()

    /// Mirrors `BadgeRegistryBridge.Entry` in the main app. Both sides use the
    /// JSONEncoder/JSONDecoder defaults, so the date encoding matches.
    struct Entry: Codable {
        var path: String
        var dev: UInt64
        var ino: UInt64
        var updatedAt: Date
    }

    private struct Key: Hashable {
        let dev: UInt64
        let ino: UInt64
    }

    private let fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("badge-registry.json", isDirectory: false)

    /// Invoked after every load (initial, mtime change, Darwin notification,
    /// or failure) with the fresh entries — `[]` when the load failed. Called
    /// outside the registry lock, so observers may run arbitrary work.
    var onReload: (([Entry]) -> Void)?

    private let lock = NSLock()
    private var keys: Set<Key> = []
    private var paths: Set<String> = []
    private var loadedModificationDate: Date?
    private var lastLoadError: String?

    private init() {
        load(reason: "initial load")
    }

    /// True when (dev, ino) is in the registry. Reloads first if the registry
    /// file's mtime changed since the last load.
    func contains(dev: UInt64, ino: UInt64) -> Bool {
        reloadIfModificationDateChanged(reason: "badge lookup")
        lock.lock()
        defer { lock.unlock() }
        return keys.contains(Key(dev: dev, ino: ino))
    }

    /// True when the registry contains an entry whose standardized path equals
    /// this path's standardized form. Fallback for stale inodes: if a noted
    /// file was replaced in place, its (dev, ino) changed but its path didn't.
    func contains(path: String) -> Bool {
        reloadIfModificationDateChanged(reason: "badge lookup")
        lock.lock()
        defer { lock.unlock() }
        return paths.contains(BadgeRegistryReader.standardize(path))
    }

    /// One-line status for the debug log: entry count or the failure reason.
    var statusDescription: String {
        lock.lock()
        defer { lock.unlock() }
        if let error = lastLoadError {
            return "registry unavailable: \(error)"
        }
        return "registry loaded: \(keys.count) entries"
    }

    /// Unconditional reload — called when the Darwin notification fires.
    func reload(reason: String) {
        load(reason: reason)
    }

    // MARK: - Internals

    private func reloadIfModificationDateChanged(reason: String) {
        let modificationDate = currentModificationDate()
        lock.lock()
        let changed = modificationDate != loadedModificationDate
        lock.unlock()
        if changed {
            load(reason: "\(reason) — registry file changed")
        }
    }

    private func currentModificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(
            atPath: fileURL.path(percentEncoded: false)))?[.modificationDate] as? Date
    }

    /// Canonical form for path comparisons (expands `~`, resolves symlinks and
    /// `.`/`..`, collapses duplicate slashes) applied to both sides.
    private static func standardize(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    /// Locked internally. A missing/unreadable file clears the cache so a
    /// deleted registry never leaves stale badges. `onReload` fires AFTER the
    /// lock is released, so observers can safely run arbitrary work (proactive
    /// `setBadgeIdentifier` calls) without deadlocking the reader.
    private func load(reason: String) {
        var loadedEntries: [Entry] = []
        lock.lock()
        do {
            let data = try Data(contentsOf: fileURL)
            let entries = try JSONDecoder().decode([Entry].self, from: data)
            keys = Set(entries.map { Key(dev: $0.dev, ino: $0.ino) })
            paths = Set(entries.map { BadgeRegistryReader.standardize($0.path) })
            loadedModificationDate = currentModificationDate()
            lastLoadError = nil
            loadedEntries = entries
            lock.unlock()
            DebugLog.log("badge registry: loaded \(entries.count) entries (\(reason))")
        } catch let error as NSError {
            keys = []
            paths = []
            loadedModificationDate = currentModificationDate()
            if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoSuchFileError {
                lastLoadError = "no registry file at \(fileURL.path(percentEncoded: false))"
            } else {
                lastLoadError = "\(error.localizedDescription) (\(error.domain) \(error.code))"
            }
            let errorDescription = lastLoadError!
            lock.unlock()
            DebugLog.log("badge registry: load failed (\(reason)) — \(errorDescription)")
        }
        onReload?(loadedEntries)
    }
}
