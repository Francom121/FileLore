import Foundation

/// User-pinned tags, shared by the search window (pinned chip row) and the
/// menu bar dropdown (Pinned Tags section).
///
/// Persisted in `UserDefaults` as a plain `[String]` under `pinnedTags`.
/// Order is user-curated (append on pin); matching is case-insensitive to
/// mirror how tags compare everywhere else in the app.
@MainActor
final class PinnedTagsStore: ObservableObject {
    static let shared = PinnedTagsStore()

    private static let defaultsKey = "pinnedTags"

    @Published private(set) var pinned: [String] {
        didSet { UserDefaults.standard.set(pinned, forKey: Self.defaultsKey) }
    }

    private init() {
        pinned = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
    }

    func isPinned(_ tag: String) -> Bool {
        pinned.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    func pin(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPinned(trimmed) else { return }
        pinned.append(trimmed)
    }

    func unpin(_ tag: String) {
        pinned.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    func toggle(_ tag: String) {
        if isPinned(tag) { unpin(tag) } else { pin(tag) }
    }
}
