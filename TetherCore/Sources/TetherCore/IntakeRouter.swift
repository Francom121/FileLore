import Foundation

/// What the app should open for a set of incoming file paths/URLs.
public enum IntakeDecision: Equatable, Sendable {
    /// Nothing usable arrived.
    case none
    /// Exactly one distinct file: open the classic single-note editor.
    case single(URL)
    /// Two or more distinct files: open the batch editor (one editor applying
    /// the same note body + tags to every file).
    case batch([URL])
}

/// Shared multi-file intake routing for every "open files in FileLore" entry
/// point: Finder right-click (Services menu and Finder Sync context menu),
/// the global hotkey's Finder selection, Dock-icon drops, and
/// `open -a FileLore a b c`.
///
/// Rules:
/// - empty input → `.none`
/// - paths are standardized and deduplicated (case-insensitive, first
///   occurrence wins) *before* the single-vs-batch decision, so opening the
///   same file twice still routes to `.single`
/// - two or more distinct files → `.batch`, input order preserved
public enum IntakeRouter {

    public static func decide(urls: [URL]) -> IntakeDecision {
        decide(paths: urls.map { $0.path(percentEncoded: false) })
    }

    public static func decide(paths: [String]) -> IntakeDecision {
        var seen: Set<String> = []
        var uniquePaths: [String] = []
        for raw in paths where !raw.isEmpty {
            let path = URL(fileURLWithPath: raw).standardizedFileURL.path(percentEncoded: false)
            guard !path.isEmpty else { continue }
            // APFS/HFS+ volumes are case-insensitive by default, so dedupe
            // case-insensitively like the Windows batch intake does.
            if seen.insert(path.lowercased()).inserted {
                uniquePaths.append(path)
            }
        }
        switch uniquePaths.count {
        case 0:
            return .none
        case 1:
            return .single(URL(fileURLWithPath: uniquePaths[0]))
        default:
            return .batch(uniquePaths.map { URL(fileURLWithPath: $0) })
        }
    }
}
