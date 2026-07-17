import Foundation

/// How the batch body is applied to each file's note.
public enum BatchBodyMode: String, CaseIterable, Equatable, Sendable {
    /// Append to the existing body (blank-separated); a file with no body gets just the batch body.
    case append
    /// Replace the existing body outright.
    case replace
    /// Only set the body when the file has no body yet.
    case onlyIfEmpty
}

/// Outcome for one file in a batch run.
public struct BatchFileResult: Equatable, Sendable {
    public var fileURL: URL
    public var succeeded: Bool
    public var errorDescription: String?

    public init(fileURL: URL, succeeded: Bool, errorDescription: String? = nil) {
        self.fileURL = fileURL
        self.succeeded = succeeded
        self.errorDescription = errorDescription
    }
}

/// Aggregate result of a batch run, in input order.
public struct BatchSummary: Equatable, Sendable {
    public var results: [BatchFileResult]

    public var successCount: Int { results.count(where: \.succeeded) }
    public var failureCount: Int { results.count - successCount }

    public init(results: [BatchFileResult]) {
        self.results = results
    }
}

/// Applies the same tags (and optionally the same body) to many files at once.
///
/// Each file is processed independently: its existing note is read (or a blank
/// one created), tags are merged case-insensitively (existing tags preserved,
/// duplicates never added), the body is applied per `mode`, and the note is
/// written back. One file's failure never stops the rest of the batch.
public enum BatchNoteService {

    /// Tags are expected pre-trimmed by callers, but trimming/empty-dropping
    /// is applied defensively here too. A `nil` body leaves every body
    /// untouched, regardless of mode.
    @discardableResult
    public static func apply(
        tags tagsToAdd: [String],
        body: String?,
        mode: BatchBodyMode,
        to fileURLs: [URL]
    ) -> BatchSummary {
        let newTags = tagsToAdd
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var results: [BatchFileResult] = []
        for url in fileURLs {
            do {
                var note = try NoteStore.read(url: url) ?? Note()
                mergeTags(newTags, into: &note)
                applyBody(body, mode: mode, to: &note)
                try NoteStore.write(note, to: url)
                results.append(BatchFileResult(fileURL: url, succeeded: true))
            } catch {
                results.append(BatchFileResult(
                    fileURL: url,
                    succeeded: false,
                    errorDescription: error.localizedDescription
                ))
            }
        }
        return BatchSummary(results: results)
    }

    // MARK: - Per-file transforms (pure, unit-testable without xattrs)

    /// Adds `newTags` to `note.tags`, refusing case-insensitive duplicates
    /// and preserving the existing tags' order and casing.
    static func mergeTags(_ newTags: [String], into note: inout Note) {
        for tag in newTags
        where !note.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            note.tags.append(tag)
        }
    }

    /// Applies `body` per `mode`; `nil` (and empty-string append) is a no-op.
    static func applyBody(_ body: String?, mode: BatchBodyMode, to note: inout Note) {
        guard let body else { return }
        switch mode {
        case .append:
            guard !body.isEmpty else { return }
            note.body = note.body.isEmpty ? body : note.body + "\n\n" + body
        case .replace:
            note.body = body
        case .onlyIfEmpty:
            if note.body.isEmpty { note.body = body }
        }
    }
}
