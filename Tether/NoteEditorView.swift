import SwiftUI
import AppKit
import QuickLookThumbnailing
import TetherCore

/// One entry in the note's linked-file list, with live resolution state.
struct LinkItem: Identifiable {
    let id: UUID
    var bookmark: Data
    var displayName: String
    var pathHint: String
    var resolvedURL: URL?
    var isBroken: Bool
    var thumbnail: NSImage?
}

@MainActor
final class NoteEditorModel: ObservableObject {
    let fileURL: URL

    @Published var body: String = ""
    @Published var tagsText: String = ""
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
        tagsText = note.tags.joined(separator: ", ")
        created = note.created
        links = note.links.map { linked in
            let resolution = BookmarkResolver.resolve(linked.bookmark)
            return LinkItem(
                id: linked.id,
                bookmark: linked.bookmark,
                displayName: linked.displayName,
                pathHint: linked.relativePathHint,
                resolvedURL: resolution.url,
                isBroken: resolution.isBroken,
                thumbnail: nil
            )
        }
        Task { await refreshThumbnails() }
    }

    var parsedTags: [String] {
        tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var detectedWebLinks: [DetectedLink] {
        LinkDetector.detectLinks(in: body)
    }

    func save() {
        do {
            var note = (try? NoteStore.read(url: fileURL)) ?? Note()
            note.body = body
            note.tags = parsedTags
            note.links = links.map {
                LinkedFile(id: $0.id, bookmark: $0.bookmark, displayName: $0.displayName, relativePathHint: $0.pathHint)
            }
            try NoteStore.write(note, to: fileURL)
            hasExistingNote = true
            created = note.created
            KnownFilesRegistry.shared.upsert(fileURL: fileURL, note: note)
            status = "Saved ✓"
        } catch {
            status = "Save failed: \(error.localizedDescription)"
        }
    }

    func deleteNote() {
        do {
            try NoteStore.delete(url: fileURL)
            KnownFilesRegistry.shared.remove(fileURL: fileURL)
            hasExistingNote = false
            body = ""
            tagsText = ""
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
                isBroken: false,
                thumbnail: nil
            ))
            Task { await refreshThumbnails() }
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
            Task { await refreshThumbnails() }
        } catch {
            status = "Relink failed: \(error.localizedDescription)"
        }
    }

    private func refreshThumbnails() async {
        for index in links.indices {
            guard let url = links[index].resolvedURL else { links[index].thumbnail = nil; continue }
            links[index].thumbnail = await ThumbnailProvider.thumbnail(for: url)
        }
    }
}

/// QuickLookThumbnailing with an NSWorkspace-icon fallback.
enum ThumbnailProvider {
    static func thumbnail(for url: URL) async -> NSImage {
        let size = CGSize(width: 96, height: 96)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            return representation.nsImage
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        icon.size = size
        return icon
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                bodyEditor
                tagsField
                linksSection
                webLinksPreview
                statusLine
            }
            .padding(20)
        }
        .frame(minWidth: 480, minHeight: 560)
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
                if model.hasExistingNote {
                    Button("Delete Note", role: .destructive) { model.deleteNote() }
                }
                Button("Save") { model.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: model.fileURL.path(percentEncoded: false)))
                .resizable()
                .frame(width: 48, height: 48)
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
            TextField("comma, separated, tags", text: $model.tagsText)
                .textFieldStyle(.roundedBorder)
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

    @ViewBuilder
    private var statusLine: some View {
        if let status = model.status {
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail).resizable()
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
                    Text(item.pathHint)
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
