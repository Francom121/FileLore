import Foundation

/// Creates and resolves security-scoped bookmarks for files linked from a note.
///
/// Bookmarks resolve by file identity on the volume, so a linked file keeps
/// resolving after it is renamed or moved to another folder on the same drive.
public enum BookmarkResolver {

    public struct Resolution: Equatable, Sendable {
        /// Resolved URL, or `nil` when the bookmark could not be resolved to an existing file.
        public var url: URL?
        /// The bookmark resolved, but its stored path no longer matches; re-saving is recommended.
        public var isStale: Bool
        public var isBroken: Bool { url == nil }

        public init(url: URL?, isStale: Bool) {
            self.url = url
            self.isStale = isStale
        }
    }

    /// Creates a security-scoped bookmark for `url`.
    ///
    /// Falls back to `.suitableForBookmarkFile` when the plain security-scoped
    /// variant fails (some volumes/file types are picky).
    public static func createBookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            return try url.bookmarkData(
                options: [.withSecurityScope, .suitableForBookmarkFile],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }

    /// Resolves bookmark data back to a URL. When `verifyExists` is true (default),
    /// a bookmark that resolves to a non-existent path is reported as broken.
    public static func resolve(_ bookmark: Data, verifyExists: Bool = true) -> Resolution {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return Resolution(url: nil, isStale: false)
        }
        if verifyExists, !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            return Resolution(url: nil, isStale: stale)
        }
        return Resolution(url: url, isStale: stale)
    }

    /// Builds a `LinkedFile` for `url`, caching a display name and a path hint
    /// relative to `base` (typically the noted file's folder) when possible.
    public static func makeLinkedFile(for url: URL, relativeTo base: URL? = nil) throws -> LinkedFile {
        let bookmark = try createBookmark(for: url)
        let target = url.standardizedFileURL.path(percentEncoded: false)
        var hint = target
        if let base {
            let basePath = base.standardizedFileURL.path(percentEncoded: false)
            let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
            if target.hasPrefix(prefix) {
                hint = String(target.dropFirst(prefix.count))
            }
        }
        return LinkedFile(bookmark: bookmark, displayName: url.lastPathComponent, relativePathHint: hint)
    }
}
