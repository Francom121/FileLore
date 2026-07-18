import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TetherCore

/// Spotlight-style search over every noted file in the registry.
///
/// Candidates are rebuilt when the window appears: each registry entry's note
/// is read live via `NoteStore.read` (fine for hundreds of files). Files whose
/// path no longer resolves are skipped; files whose note xattr vanished are
/// kept (name-only matching) and flagged in the list. Results update live as
/// you type; the tag-chip strip AND-filters the current results.
///
/// Pinned tags (see `PinnedTagsStore`) get their own chip row above the
/// filter chips: one click filters the results to that tag, right-click
/// unpins. Any tag chip or result-row tag pill can be pinned via right-click.
///
/// Results are multi-selectable (⌘-click toggles, ⇧-click ranges); the
/// "Export…" button (or the right-click context item) writes all selected
/// notes to ONE Markdown file via `MarkdownExporter.batchMarkdown`.
struct SearchView: View {
    @StateObject private var model = SearchModel()
    @ObservedObject private var pinnedStore = PinnedTagsStore.shared
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

            // Pinned tags: one click filters to that tag, right-click unpins.
            if !pinnedStore.pinned.isEmpty {
                Divider()
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ForEach(pinnedStore.pinned, id: \.self) { tag in
                            PinnedTagChip(
                                tag: tag,
                                isActive: model.activeTags.contains(tag),
                                onFilter: { model.filterByPinnedTag(tag) },
                                onUnpin: { pinnedStore.unpin(tag) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }

            // Tag filter chips (built from every tag in the registry)
            if !model.allTags.isEmpty {
                Divider()
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(model.allTags, id: \.self) { tag in
                            TagFilterChip(
                                tag: tag,
                                isActive: model.activeTags.contains(tag),
                                isPinned: pinnedStore.isPinned(tag),
                                onToggle: { model.toggleTag(tag) },
                                onPinToggle: { pinnedStore.toggle(tag) }
                            )
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
                    List(model.results, selection: $model.selectedResultIDs) { result in
                        SearchResultRow(result: result)
                            .tag(result.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { model.open(result) }
                            .contextMenu {
                                Button("Open Note") { model.open(result) }
                                Button("Reveal in Finder") { model.reveal(result) }
                                Divider()
                                if model.selectedResultIDs.count > 1,
                                   model.selectedResultIDs.contains(result.id) {
                                    Button("Export \(model.selectedResultIDs.count) Selected Notes…") {
                                        model.exportSelection()
                                    }
                                } else {
                                    Button("Export Note…") { model.export(result) }
                                }
                            }
                    }
                    .listStyle(.plain)
                    .onChange(of: model.selectedResultIDs) { _, newValue in
                        if let first = model.results.first(where: { newValue.contains($0.id) }) {
                            withAnimation { proxy.scrollTo(first.id) }
                        }
                    }
                }
            }

            Divider()
            HStack(spacing: 8) {
                Text("\(model.results.count) result\(model.results.count == 1 ? "" : "s")")
                if !model.selectedResultIDs.isEmpty {
                    Text("· \(model.selectedResultIDs.count) selected")
                }
                Spacer()
                Button("Export…") { model.exportSelection() }
                    .disabled(model.selectedResultIDs.isEmpty)
                    .help("Export the selected notes as one Markdown file")
                Text("↩ open · ⌘↩ reveal · ⌘/⇧-click select")
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
    @ObservedObject private var pinnedStore = PinnedTagsStore.shared

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
                                .contextMenu {
                                    Button(pinnedStore.isPinned(tag) ? "Unpin Tag" : "Pin Tag") {
                                        pinnedStore.toggle(tag)
                                    }
                                }
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Tag chips

/// One chip in the filter strip. Click toggles the AND-filter; right-click
/// pins/unpins the tag (pinned tags surface in the pinned row and the menu
/// bar dropdown).
private struct TagFilterChip: View {
    let tag: String
    let isActive: Bool
    let isPinned: Bool
    let onToggle: () -> Void
    let onPinToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 3) {
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 7))
                }
                Text(tag)
            }
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
        .contextMenu {
            Button(isPinned ? "Unpin Tag" : "Pin Tag", action: onPinToggle)
        }
    }
}

/// One chip in the pinned row. Click filters the results to exactly this tag
/// (click again to clear); right-click unpins.
private struct PinnedTagChip: View {
    let tag: String
    let isActive: Bool
    let onFilter: () -> Void
    let onUnpin: () -> Void

    var body: some View {
        Button(action: onFilter) {
            HStack(spacing: 3) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 7))
                Text(tag)
            }
            .font(.caption)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                isActive ? Color.accentColor : Color.secondary.opacity(0.16),
                in: Capsule()
            )
            .foregroundStyle(isActive ? .white : .primary)
        }
        .buttonStyle(.plain)
        .help("Filter by #\(tag) (right-click to unpin)")
        .contextMenu {
            Button("Unpin Tag", action: onUnpin)
        }
    }
}

// MARK: - Model

@MainActor
final class SearchModel: ObservableObject {
    @Published var query: String = "" { didSet { applyFilters() } }
    @Published private(set) var candidates: [SearchCandidate] = []
    @Published private(set) var results: [SearchResult] = []
    @Published var activeTags: Set<String> = [] { didSet { applyFilters() } }
    /// Multi-selection (⌘-click toggles, ⇧-click ranges). Keyboard navigation
    /// collapses this to a single element.
    @Published var selectedResultIDs: Set<SearchResult.ID> = []

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

    /// Pinned-tag click: filter to exactly this tag (clicking the active one
    /// clears the filter again).
    func filterByPinnedTag(_ tag: String) {
        if activeTags == [tag] {
            activeTags = []
        } else {
            activeTags = [tag]
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
        // Keep the selection inside the visible results; fall back to the
        // first result so ↩ always has something to open.
        selectedResultIDs = selectedResultIDs.intersection(Set(filtered.map(\.id)))
        if selectedResultIDs.isEmpty, let first = filtered.first {
            selectedResultIDs = [first.id]
        }
    }

    // MARK: - Selection & actions

    func moveSelection(_ offset: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex(where: { selectedResultIDs.contains($0.id) }) ?? 0
        let next = min(max(current + offset, 0), results.count - 1)
        selectedResultIDs = [results[next].id]
    }

    private var primarySelection: SearchResult? {
        results.first(where: { selectedResultIDs.contains($0.id) }) ?? results.first
    }

    func openSelected() {
        if NSEvent.modifierFlags.contains(.command) {
            if let selected = primarySelection { reveal(selected) }
        } else if let selected = primarySelection {
            open(selected)
        }
    }

    func open(_ result: SearchResult) {
        WindowRouter.shared.openNoteEditor(for: result.candidate.fileURL)
    }

    func reveal(_ result: SearchResult) {
        NSWorkspace.shared.activateFileViewerSelecting([result.candidate.fileURL])
    }

    // MARK: - Batch Markdown export

    /// Exports every selected result that still carries a note.
    func exportSelection() {
        export(results: results.filter { selectedResultIDs.contains($0.id) })
    }

    func export(_ result: SearchResult) {
        export(results: [result])
    }

    /// NSSavePanel (default `FileLore Export <yyyy-MM-dd>.md`) → ONE Markdown
    /// document for all selected notes, then reveals it in Finder. Results
    /// whose note xattr vanished can't be exported and are reported skipped.
    private func export(results selected: [SearchResult]) {
        var items: [MarkdownExporter.ExportItem] = []
        var skipped = 0
        for result in selected {
            if let note = result.candidate.note {
                items.append(MarkdownExporter.ExportItem(
                    note: note,
                    fileName: result.candidate.displayName,
                    filePath: result.candidate.fileURL.path(percentEncoded: false)
                ))
            } else {
                skipped += 1
            }
        }
        guard !items.isEmpty else {
            showAlert(title: "Nothing to Export",
                      message: "None of the selected files still carries a FileLore note, so there is nothing to export.")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Notes as Markdown"
        panel.nameFieldStringValue = "FileLore Export \(MarkdownExporter.exportDateString()).md"
        panel.allowedContentTypes = [.init(filenameExtension: "md")].compactMap { $0 }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try MarkdownExporter.batchMarkdown(for: items)
                .write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            if skipped > 0 {
                showAlert(
                    title: "Export Complete",
                    message: "Exported \(items.count) note\(items.count == 1 ? "" : "s"). \(skipped) selected file\(skipped == 1 ? "was" : "s were") skipped because its note is missing."
                )
            }
        } catch {
            showAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
