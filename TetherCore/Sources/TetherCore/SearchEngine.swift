import Foundation

/// One searchable file: its URL, display name, the note it carries (or `nil`
/// when the file exists but its `com.filelore.note` xattr vanished), and the
/// recency timestamp used for ranking.
public struct SearchCandidate: Equatable, Sendable {
    public var fileURL: URL
    public var displayName: String
    public var note: Note?
    public var updatedAt: Date
    /// True when the registry knows this file but the note xattr is gone.
    public var noteMissing: Bool { note == nil }

    public init(fileURL: URL, displayName: String, note: Note?, updatedAt: Date) {
        self.fileURL = fileURL
        self.displayName = displayName
        self.note = note
        self.updatedAt = updatedAt
    }

    /// Convenience: recency defaults to the note's `modified` timestamp.
    public init(fileURL: URL, note: Note) {
        self.init(
            fileURL: fileURL,
            displayName: fileURL.lastPathComponent,
            note: note,
            updatedAt: note.modified
        )
    }
}

/// One search hit: the candidate plus *how* it matched and, for body hits, a
/// short excerpt around the first occurrence of the query.
public struct SearchResult: Equatable, Sendable {
    /// Match tier — name hits outrank tag hits, which outrank body hits.
    /// `nil` when the result came from an empty query (no matching involved).
    public enum MatchKind: String, Equatable, Sendable, Comparable {
        case name, tag, body

        private var rank: Int {
            switch self {
            case .name: return 0
            case .tag: return 1
            case .body: return 2
            }
        }

        public static func < (lhs: MatchKind, rhs: MatchKind) -> Bool {
            lhs.rank < rhs.rank
        }
    }

    public var candidate: SearchCandidate
    public var match: MatchKind?
    /// ~80-character window around the first body hit (body matches only).
    public var snippet: String?

    public init(candidate: SearchCandidate, match: MatchKind?, snippet: String? = nil) {
        self.candidate = candidate
        self.match = match
        self.snippet = snippet
    }
}

extension SearchResult: Identifiable {
    public var id: String { candidate.fileURL.path(percentEncoded: false) }
}

/// Spotlight-style search over the registry's noted files.
///
/// Matching is case- and diacritic-insensitive substring matching across the
/// file name, the note's tags, and the note body (via `String.range(of:options:)`,
/// which also handles Unicode canonically — "café" matches "cafe" and "É" matches "e").
///
/// Ranking: name matches first, then tag matches, then body matches; within a
/// tier the most recently updated file wins. An empty/whitespace query returns
/// everything, most recent first, capped at `limit`.
public enum SearchEngine {

    /// Default maximum number of results (also the cap for empty queries).
    public static let defaultLimit = 50

    public static func search(
        _ query: String,
        in candidates: [SearchCandidate],
        limit: Int = SearchEngine.defaultLimit
    ) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return candidates
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(limit)
                .map { SearchResult(candidate: $0, match: nil) }
        }

        var results: [SearchResult] = []
        for candidate in candidates {
            if contains(candidate.displayName, trimmed) {
                results.append(SearchResult(candidate: candidate, match: .name))
            } else if let note = candidate.note,
                      note.tags.contains(where: { contains($0, trimmed) }) {
                results.append(SearchResult(candidate: candidate, match: .tag))
            } else if let note = candidate.note,
                      let snippet = snippet(for: trimmed, in: note.body) {
                results.append(SearchResult(candidate: candidate, match: .body, snippet: snippet))
            }
        }

        results.sort { lhs, rhs in
            guard let l = lhs.match, let r = rhs.match else { return lhs.match != nil }
            if l != r { return l < r }
            return lhs.candidate.updatedAt > rhs.candidate.updatedAt
        }
        return Array(results.prefix(limit))
    }

    // MARK: - Matching helpers

    /// Case- and diacritic-insensitive substring check.
    static func contains(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// An ~`maxLength`-character excerpt of `body` around the first
    /// (case/diacritic-insensitive) occurrence of `query`, ellipsized at the
    /// edges where text was cut. Returns `nil` when there is no hit.
    static func snippet(for query: String, in body: String, maxLength: Int = 80) -> String? {
        guard let hit = body.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }

        // Center the hit in the window, then nudge the edges to word
        // boundaries so the excerpt doesn't start/end mid-word.
        let context = max((maxLength - query.count) / 2, 0)
        var start = body.index(hit.lowerBound, offsetBy: -context, limitedBy: body.startIndex) ?? body.startIndex
        if start != body.startIndex,
           let space = body[start..<hit.lowerBound].firstIndex(where: { $0.isWhitespace }) {
            start = body.index(after: space)
        }
        var end = body.index(start, offsetBy: maxLength, limitedBy: body.endIndex) ?? body.endIndex
        if end != body.endIndex,
           let space = body[end...].firstIndex(where: { $0.isWhitespace }),
           body.distance(from: end, to: space) < 12 {
            end = space
        }

        var excerpt = body[start..<end]
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if start != body.startIndex { excerpt = "…" + excerpt }
        if end != body.endIndex { excerpt += "…" }
        return excerpt
    }
}
