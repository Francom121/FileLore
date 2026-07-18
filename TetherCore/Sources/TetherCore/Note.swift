import Foundation

/// A file referenced from a note, stored as a security-scoped bookmark so the
/// link survives renames and moves on the same volume.
public struct LinkedFile: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// Security-scoped bookmark data (Codable encodes `Data` as base64 inside the JSON envelope).
    public var bookmark: Data
    /// Cached display name, so the UI can still show something when the link is broken.
    public var displayName: String
    /// Cached path hint (relative to the noted file's folder when possible) for diagnostics/relinking.
    public var relativePathHint: String

    public init(id: UUID = UUID(), bookmark: Data, displayName: String, relativePathHint: String) {
        self.id = id
        self.bookmark = bookmark
        self.displayName = displayName
        self.relativePathHint = relativePathHint
    }
}

/// A sticky note attached to a file via the `com.filelore.note` extended attribute.
public struct Note: Codable, Equatable, Sendable {
    public var body: String
    public var tags: [String]
    public var links: [LinkedFile]
    public var created: Date
    public var modified: Date

    public init(
        body: String = "",
        tags: [String] = [],
        links: [LinkedFile] = [],
        created: Date = Date(),
        modified: Date = Date()
    ) {
        self.body = body
        self.tags = tags
        self.links = links
        self.created = created
        self.modified = modified
    }
}

/// Versioned JSON envelope persisted as the xattr payload, so future payload
/// migrations can detect what they are reading.
public struct NoteEnvelope: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var note: Note

    public init(note: Note, version: Int = NoteEnvelope.currentVersion) {
        self.version = version
        self.note = note
    }
}
