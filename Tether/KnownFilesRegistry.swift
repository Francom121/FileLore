import Foundation
import TetherCore

/// Small local registry of files that carry a Tether note.
///
/// Persisted at `~/Library/Application Support/Tether/known-files.json`.
/// The note itself always lives in the xattr; this registry only exists so the
/// menu bar list (and a future search feature) can find noted files quickly.
@MainActor
final class KnownFilesRegistry {
    static let shared = KnownFilesRegistry()

    struct Entry: Codable, Equatable {
        var path: String
        var displayName: String
        var tags: [String]
        var preview: String
        var updatedAt: Date
    }

    private(set) var entries: [Entry] = []

    private var storageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tether", isDirectory: true)
            .appendingPathComponent("known-files.json")
    }

    private init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: storageURL) else { entries = []; return }
        entries = (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            try encoder.encode(entries).write(to: storageURL, options: .atomic)
        } catch {
            NSLog("Tether: failed to persist known-files.json: \(error.localizedDescription)")
        }
    }

    func upsert(fileURL: URL, note: Note) {
        let path = fileURL.path(percentEncoded: false)
        entries.removeAll { $0.path == path }
        entries.append(Entry(
            path: path,
            displayName: fileURL.lastPathComponent,
            tags: note.tags,
            preview: String(note.body.prefix(160)),
            updatedAt: Date()
        ))
        persist()
    }

    func remove(fileURL: URL) {
        let path = fileURL.path(percentEncoded: false)
        entries.removeAll { $0.path == path }
        persist()
    }

    /// Most recently updated noted files first.
    func recent(_ count: Int) -> [Entry] {
        Array(entries.sorted { $0.updatedAt > $1.updatedAt }.prefix(count))
    }
}
