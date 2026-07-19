import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TetherCore

/// One entry in the note's linked-file list, with live resolution state.
struct LinkItem: Identifiable {
    let id: UUID
    var bookmark: Data
    var displayName: String
    var pathHint: String
    var resolvedURL: URL?
    var isBroken: Bool
}

@MainActor
final class NoteEditorModel: ObservableObject {
    let fileURL: URL

    @Published var body: String = ""
    @Published var tags: [String] = []
    /// In-progress text in the tag field (not yet a pill); merged into `tags`
    /// on Save so a half-typed tag is never lost.
    @Published var tagDraft: String = ""
    @Published var links: [LinkItem] = []
    @Published var created: Date?
    @Published var status: String?

    var hasExistingNote = false

    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    func load() {
        guard let note = try? NoteStore.read(url: fileURL) else {
            hasExistingNote = false
            return
        }
        hasExistingNote = true
        body = note.body
        tags = note.tags
        created = note.created
        links = note.links.map { linked in
            let resolution = BookmarkResolver.resolve(linked.bookmark)
            return LinkItem(
                id: linked.id,
                bookmark: linked.bookmark,
                displayName: linked.displayName,
                pathHint: linked.relativePathHint,
                resolvedURL: resolution.url,
                isBroken: resolution.isBroken
            )
        }
    }

    var detectedWebLinks: [DetectedLink] {
        LinkDetector.detectLinks(in: body)
    }

    func save() {
        do {
            // Merge a half-typed tag the user never committed into the pills.
            var finalTags = tags
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for piece in TagPillEditor.pieces(from: tagDraft)
            where !finalTags.contains(where: { $0.caseInsensitiveCompare(piece) == .orderedSame }) {
                finalTags.append(piece)
            }
            tags = finalTags
            tagDraft = ""

            var note = (try? NoteStore.read(url: fileURL)) ?? Note()
            note.body = body
            note.tags = finalTags
            note.links = links.map {
                LinkedFile(id: $0.id, bookmark: $0.bookmark, displayName: $0.displayName, relativePathHint: $0.pathHint)
            }
            try NoteStore.write(note, to: fileURL)
            hasExistingNote = true
            created = note.created
            KnownFilesRegistry.shared.upsert(fileURL: fileURL, note: note)
            BadgeRegistryBridge.refresh()
            status = "Saved ✓"
        } catch {
            status = "Save failed: \(error.localizedDescription)"
        }
    }

    func deleteNote() {
        do {
            try NoteStore.delete(url: fileURL)
            KnownFilesRegistry.shared.remove(fileURL: fileURL)
            BadgeRegistryBridge.refresh()
            hasExistingNote = false
            body = ""
            tags = []
            tagDraft = ""
            links = []
            created = nil
            status = "Note deleted"
        } catch {
            status = "Delete failed: \(error.localizedDescription)"
        }
    }

    func copyBodyToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body, forType: .string)
        status = "Copied to clipboard"
    }

    // MARK: - Markdown export

    /// The note as it would be saved right now (unsaved edits included).
    private func currentNote() -> Note {
        Note(
            body: body,
            tags: tags,
            links: links.map {
                LinkedFile(id: $0.id, bookmark: $0.bookmark, displayName: $0.displayName, relativePathHint: $0.pathHint)
            },
            created: created ?? Date(),
            modified: Date()
        )
    }

    func markdownForExport() -> String {
        MarkdownExporter.markdown(for: currentNote(), fileName: fileURL.lastPathComponent)
    }

    func copyMarkdownToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdownForExport(), forType: .string)
        status = "Markdown copied to clipboard"
    }

    /// NSSavePanel pre-filled with `<filename>.md`; writes the exported Markdown.
    func saveMarkdownAsFile() {
        let panel = NSSavePanel()
        panel.title = "Export Note as Markdown"
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = "\(baseName).md"
        panel.allowedContentTypes = [.init(filenameExtension: "md")].compactMap { $0 }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try markdownForExport().write(to: url, atomically: true, encoding: .utf8)
            status = "Exported to \(url.lastPathComponent) ✓"
        } catch {
            status = "Export failed: \(error.localizedDescription)"
        }
    }

    func applyTemplate(_ template: NoteTemplate) {
        guard !template.body.isEmpty else { body = ""; return }
        body = body.isEmpty ? template.body : body + "\n\n" + template.body
    }

    func addLink(url: URL) {
        do {
            let linked = try BookmarkResolver.makeLinkedFile(
                for: url,
                relativeTo: fileURL.deletingLastPathComponent()
            )
            links.append(LinkItem(
                id: linked.id,
                bookmark: linked.bookmark,
                displayName: linked.displayName,
                pathHint: linked.relativePathHint,
                resolvedURL: url,
                isBroken: false
            ))
        } catch {
            status = "Could not link file: \(error.localizedDescription)"
        }
    }

    func removeLink(id: UUID) {
        links.removeAll { $0.id == id }
    }

    func openLink(_ item: LinkItem) {
        guard let url = item.resolvedURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Broken link → ask the user to pick the file again, then store a fresh bookmark.
    func relink(_ item: LinkItem) {
        let panel = NSOpenPanel()
        panel.title = "Relink “\(item.displayName)”"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let fresh = try BookmarkResolver.makeLinkedFile(
                for: url,
                relativeTo: fileURL.deletingLastPathComponent()
            )
            guard let index = links.firstIndex(where: { $0.id == item.id }) else { return }
            links[index].bookmark = fresh.bookmark
            links[index].displayName = fresh.displayName
            links[index].pathHint = fresh.relativePathHint
            links[index].resolvedURL = url
            links[index].isBroken = false
        } catch {
            status = "Relink failed: \(error.localizedDescription)"
        }
    }
}

/// Note editor for a single file.
struct NoteEditorView: View {
    @StateObject private var model: NoteEditorModel
    @State private var linksDropTargeted = false

    init(fileURL: URL) {
        _model = StateObject(wrappedValue: NoteEditorModel(fileURL: fileURL))
    }

    var body: some View {
        // Media peek: playable/previewable files (video, audio, images, PDF,
        // text) get a live media pane beside the note controls; anything else
        // keeps the classic single-column editor (header thumbnail only).
        let showsMedia = MediaPreview.kind(for: model.fileURL) != .other
        HStack(spacing: 0) {
            if showsMedia {
                MediaPreviewView(url: model.fileURL)
                    .id(model.fileURL)  // file change → fresh pane (old player torn down)
                    .frame(minWidth: 320, maxWidth: .infinity)
                    // Float the framed media card inside a window-colored
                    // column; the card supplies its own border/background.
                    .padding(12)
                    .background(Color(nsColor: .windowBackgroundColor))
                    // Hosted AppKit views aren't clipped by SwiftUI; keep the
                    // media strictly inside its pane no matter what it renders.
                    .clipped()
                Divider()
            }
            editorColumn
                .frame(minWidth: 440, maxWidth: .infinity)
        }
        .frame(minWidth: showsMedia ? 800 : 480, minHeight: 560)
        .navigationTitle(model.fileURL.lastPathComponent)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu("Template") {
                    ForEach(TemplateStore.all()) { template in
                        Button(template.name) { model.applyTemplate(template) }
                    }
                }
                Button("Copy") { model.copyBodyToPasteboard() }
                    .help("Copy note body to the clipboard")
                Menu("Export…") {
                    Button("Save as Markdown…") { model.saveMarkdownAsFile() }
                    Button("Copy Markdown to Clipboard") { model.copyMarkdownToPasteboard() }
                }
                .help("Export the note (text, tags, links) as Markdown")
            }
        }
    }

    /// The classic editor: header, note body, tags, linked files, web links,
    /// and the persistent Save bar — unchanged, now the right-hand column.
    private var editorColumn: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    bodyEditor
                    tagsField
                    linksSection
                    webLinksPreview
                }
                .padding(20)
            }
            Divider()
            actionBar
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            FileThumbnailView(url: model.fileURL, pointSize: 64, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.fileURL.lastPathComponent).font(.headline)
                Text(model.fileURL.deletingLastPathComponent().path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let created = model.created {
                    Text("Noted \(created.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Note").font(.subheadline.weight(.semibold))
            TextEditor(text: $model.body)
                .font(.body)
                .frame(minHeight: 160)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
        }
    }

    private var tagsField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags").font(.subheadline.weight(.semibold))
            TagPillEditor(tags: $model.tags, draft: $model.tagDraft)
        }
    }

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Linked Files").font(.subheadline.weight(.semibold))
            VStack(spacing: 6) {
                if model.links.isEmpty {
                    Text("Drop files here to link them (reference photos, etc.)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else {
                    ForEach(model.links) { item in
                        LinkRow(
                            item: item,
                            onOpen: { model.openLink(item) },
                            onRelink: { model.relink(item) },
                            onRemove: { model.removeLink(id: item.id) }
                        )
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(linksDropTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
            ).foregroundStyle(Color.secondary.opacity(0.4)))
            .onDrop(of: [.fileURL], isTargeted: $linksDropTargeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in model.addLink(url: url) }
                    }
                }
                return true
            }
        }
    }

    @ViewBuilder
    private var webLinksPreview: some View {
        if !model.detectedWebLinks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Web Links").font(.subheadline.weight(.semibold))
                Text(LinkDetector.attributedString(for: model.body))
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Persistent bottom action bar. The Save affordance lives here — not only
    /// in the toolbar, which collapses into the ">>" overflow chevron at the
    /// default 520pt window width — so it stays unmissable at any window width.
    /// ⌘S is attached to this always-visible button, so the shortcut keeps
    /// working even while the text editor has focus.
    private var actionBar: some View {
        HStack(spacing: 12) {
            if let status = model.status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if model.hasExistingNote {
                Button("Delete Note", role: .destructive) { model.deleteNote() }
                    .help("Delete the note from this file")
            }
            Button("Save Note") { model.save() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help("Save the note (⌘S)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

private struct LinkRow: View {
    let item: LinkItem
    let onOpen: () -> Void
    let onRelink: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let url = item.resolvedURL {
                    FileThumbnailView(url: url, pointSize: 36, cornerRadius: 6)
                } else {
                    Image(systemName: item.isBroken ? "exclamationmark.triangle" : "doc")
                        .resizable().scaledToFit().padding(6)
                }
            }
            .frame(width: 36, height: 36)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName).font(.callout).lineLimit(1)
                if item.isBroken {
                    Text("Link broken — relink?")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    // Line 2 is the file's LOCATION (parent folder), styled
                    // like the header's folder line for the noted file.
                    Text(item.resolvedURL.map { BookmarkResolver.locationDisplay(for: $0) } ?? item.pathHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if item.isBroken {
                Button("Relink…") { onRelink() }
            } else {
                Button("Open") { onOpen() }
            }
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove link from note")
        }
        .contentShape(Rectangle())
        .onTapGesture { if !item.isBroken { onOpen() } }
    }
}
