import Foundation

public enum NoteStoreError: Error, Equatable {
    case xattrReadFailed(path: String, errno: Int32)
    case xattrWriteFailed(path: String, errno: Int32)
    case xattrRemoveFailed(path: String, errno: Int32)
    case unsupportedVersion(Int)
}

/// Reads and writes `Note` values as a JSON-encoded xattr on arbitrary files.
///
/// The note lives *on the file itself* (xattr `com.tether.note`), so it survives
/// renames and moves on the same volume without any separate database.
public enum NoteStore {
    /// Name of the extended attribute that carries the note payload.
    public static let xattrName = "com.tether.note"

    // MARK: - Public API

    /// Returns the note attached to `url`, or `nil` when the file has no note.
    public static func read(url: URL) throws -> Note? {
        guard let data = try readXattr(url: url) else { return nil }
        let envelope = try JSONDecoder().decode(NoteEnvelope.self, from: data)
        guard envelope.version <= NoteEnvelope.currentVersion else {
            throw NoteStoreError.unsupportedVersion(envelope.version)
        }
        return envelope.note
    }

    /// Convenience non-throwing check used by badge/preview code paths.
    public static func hasNote(url: URL) -> Bool {
        (try? read(url: url)) != nil
    }

    /// Writes (or overwrites) the note on `url`, refreshing `modified`.
    public static func write(_ note: Note, to url: URL) throws {
        var note = note
        note.modified = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(NoteEnvelope(note: note))
        try writeXattr(url: url, data: data)
    }

    /// Removes the note xattr. Succeeds silently when no note is present.
    public static func delete(url: URL) throws {
        let path = fileSystemPath(of: url)
        let result: Int32 = path.withCString { cPath in
            xattrName.withCString { cName in
                removexattr(cPath, cName, XATTR_NOFOLLOW)
            }
        }
        if result != 0, errno != ENOATTR {
            throw NoteStoreError.xattrRemoveFailed(path: path, errno: errno)
        }
    }

    // MARK: - xattr plumbing

    private static func fileSystemPath(of url: URL) -> String {
        url.path(percentEncoded: false)
    }

    private static func readXattr(url: URL) throws -> Data? {
        let path = fileSystemPath(of: url)
        // Two attempts: the attribute could grow between the size probe and the read.
        for _ in 0..<2 {
            let probe: Int = path.withCString { cPath in
                xattrName.withCString { cName in
                    getxattr(cPath, cName, nil, 0, 0, XATTR_NOFOLLOW)
                }
            }
            if probe < 0 {
                if errno == ENOATTR { return nil }
                throw NoteStoreError.xattrReadFailed(path: path, errno: errno)
            }
            if probe == 0 { return Data() }

            var data = Data(count: probe)
            let actual: Int = data.withUnsafeMutableBytes { buffer in
                path.withCString { cPath in
                    xattrName.withCString { cName in
                        getxattr(cPath, cName, buffer.baseAddress, probe, 0, XATTR_NOFOLLOW)
                    }
                }
            }
            if actual < 0 {
                if errno == ENOATTR { return nil }
                if errno == ERANGE { continue } // grew between calls; probe again
                throw NoteStoreError.xattrReadFailed(path: path, errno: errno)
            }
            if actual < data.count { data = data.subdata(in: 0..<actual) }
            return data
        }
        throw NoteStoreError.xattrReadFailed(path: path, errno: ERANGE)
    }

    private static func writeXattr(url: URL, data: Data) throws {
        let path = fileSystemPath(of: url)
        let result: Int32 = path.withCString { cPath in
            xattrName.withCString { cName in
                data.withUnsafeBytes { buffer in
                    setxattr(cPath, cName, buffer.baseAddress, data.count, 0, XATTR_NOFOLLOW)
                }
            }
        }
        if result != 0 {
            throw NoteStoreError.xattrWriteFailed(path: path, errno: errno)
        }
    }
}
