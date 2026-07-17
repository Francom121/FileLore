import SwiftUI
import AppKit
import TetherCore

/// Spotlight-style search over every noted file in the registry.
///
/// Candidates are rebuilt when the window appears: each registry entry's note
/// is read live via `NoteStore.read` (fine for hundreds of files). Files whose
/// path no longer resolves are skipped; files whose note xattr vanished are
/// kept (name-only matching) and flagged in the list. Results update live as
/// you type; the tag-chip strip AND-filters the current results.
struct SearchView: View {
    @StateObject private var model = SearchModel()
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Big query field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search notes, files, tags…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .light))
                    .focused($fieldFocused)
                    .onSubmit { model.openSelected() }
                if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            // Tag filter chips (built from every tag in the registry)
            if !model.allTags.isEmpty {
                Divider()
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(model.allTags, id: \.self) { tag in
                            TagFilterChip(
                                tag: tag,
                                isActive: model.activeTags.contains(tag)
                            ) { model.toggleTag(tag) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }

            Divider()

            // Results
            if model.results.isEmpty {
                ContentUnavailableView {
                    Label("No Results", systemImage: "note.text")
                } description: {
                    Text(model.hasCandidates
                         ? "No noted files match “\(model.query)”."
                         : "No noted files yet — notes you save appear here.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(model.results, selection: $model.selectedResultID) { result in
                        SearchResultRow(result: result)
                            .tag(result.id)
                            .contentShape(Rectangle())
                            .onTapGesture { model.open(result) }
                            .contextMenu {
                                Button("Open Note") { model.open(result) }
                                Button("Reveal in Finder") { model.reveal(result) }
                            }
                    }
                    .listStyle(.plain)
                    .onChange(of: model.selectedResultID) { _, newValue in
                        if let newValue {
                            withAnimation { proxy.scrollTo(newValue) }
                        }
                    }
                }
            }

            Divider()
            HStack {
                Text("\(model.results.count) result\(model.results.count == 1 ? "" : "s")")
                Spacer()
                Text("↩ open · ⌘↩ reveal in Finder · right-click for more")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .frame(minWidth: 560, minHeight: 440)
        .onAppear {
            model.rebuildCandidates()
            fieldFocused = true
        }
        .onMoveCommand { direction in
            model.moveSelection(direction == .down ? 1 : -1)
        }
    }
}

// MARK: - Row

private struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        HStack(spacing: 10) {
            FileThumbnailView(url: result.candidate.fileURL, pointSize: 36, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(result.candidate.displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if result.candidate.noteMissing {
                        Text("note missing")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.18), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                if let snippet = result.snippet {
                    Text(snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(result.candidate.fileURL.deletingLastPathComponent().path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let tags = result.candidate.note?.tags, !tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Tag chip

private struct TagFilterChip: View {
    let tag: String
    let isActive: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Text(tag)
                .font(.caption)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    isActive ? Color.accentColor : Color.accentColor.opacity(0.14),
                    in: Capsule()
                )
                .foregroundStyle(isActive ? .white : Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Model

@MainActor
final class SearchModel: ObservableObject {
    @Published var query: String = "" { didSet { applyFilters() } }
    @Published private(set) var candidates: [SearchCandidate] = []
    @Published private(set) var results: [SearchResult] = []
    @Published var activeTags: Set<String> = [] { didSet { applyFilters() } }
    @Published var selectedResultID: SearchResult.ID?

    private(set) var allTags: [String] = []
    var hasCandidates: Bool { !candidates.isEmpty }

    /// Reads every registry entry's note live. Files that no longer exist are
    /// skipped; files whose xattr vanished stay searchable by name and are
    /// flagged via `candidate.noteMissing`.
    func rebuildCandidates() {
        KnownFilesRegistry.shared.load()
        var built: [SearchCandidate] = []
        for entry in KnownFilesRegistry.shared.entries {
            let url = URL(fileURLWithPath: entry.path)
            guard FileManager.default.fileExists(atPath: entry.path) else { continue }
            let note = try? NoteStore.read(url: url)
            built.append(SearchCandidate(
                fileURL: url,
                displayName: entry.displayName,
                note: note,
                updatedAt: note?.modified ?? entry.updatedAt
            ))
        }
        candidates = built

        var seen = Set<String>()
        allTags = built
            .flatMap { $0.note?.tags ?? [] }
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        activeTags = activeTags.intersection(Set(allTags))
        applyFilters()
    }

    func toggleTag(_ tag: String) {
        if activeTags.contains(tag) {
            activeTags.remove(tag)
        } else {
            activeTags.insert(tag)
        }
    }

    private func applyFilters() {
        var filtered = SearchEngine.search(query, in: candidates)
        if !activeTags.isEmpty {
            filtered = filtered.filter { result in
                let tags = result.candidate.note?.tags ?? []
                return activeTags.allSatisfy { active in
                    tags.contains { $0.caseInsensitiveCompare(active) == .orderedSame }
                }
            }
        }
        results = filtered
        if !filtered.contains(where: { $0.id == selectedResultID }) {
            selectedResultID = filtered.first?.id
        }
    }

    // MARK: - Selection & actions

    func moveSelection(_ offset: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex(where: { $0.id == selectedResultID }) ?? 0
        let next = min(max(current + offset, 0), results.count - 1)
        selectedResultID = results[next].id
    }

    func openSelected() {
        if NSEvent.modifierFlags.contains(.command) {
            revealSelected()
        } else if let selected = results.first(where: { $0.id == selectedResultID }) ?? results.first {
            open(selected)
        }
    }

    private func revealSelected() {
        if let selected = results.first(where: { $0.id == selectedResultID }) ?? results.first {
            reveal(selected)
        }
    }

    func open(_ result: SearchResult) {
        WindowRouter.shared.openNoteEditor(for: result.candidate.fileURL)
    }

    func reveal(_ result: SearchResult) {
        NSWorkspace.shared.activateFileViewerSelecting([result.candidate.fileURL])
    }
}
