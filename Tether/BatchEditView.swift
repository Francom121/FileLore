import SwiftUI
import AppKit
import TetherCore

/// Batch tag/note editor: apply the same tags (and optionally the same body)
/// to many files at once.
///
/// Reached by dropping several files on the drop zone / Dock icon, or via the
/// Finder Sync "Batch Tag with Tether…" context menu item (which hands the
/// file list over through a `tether://batch?ref=` URL — see
/// `BatchRequestLoader`).
struct BatchEditView: View {
    @StateObject private var model: BatchEditModel

    init(fileURLs: [URL]) {
        _model = StateObject(wrappedValue: BatchEditModel(fileURLs: fileURLs))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                fileList
                tagsSection
                bodySection
                modePicker
                applyRow
                statusLine
            }
            .padding(20)
        }
        .frame(minWidth: 520, minHeight: 560)
        .navigationTitle("Batch Edit — \(model.fileURLs.count) files")
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Files (\(model.fileURLs.count))").font(.subheadline.weight(.semibold))
            VStack(spacing: 4) {
                ForEach(model.fileURLs, id: \.self) { url in
                    HStack(spacing: 10) {
                        FileThumbnailView(url: url, pointSize: 28, cornerRadius: 5)
                        Text(url.lastPathComponent)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if let result = model.result(for: url) {
                            Image(systemName: result.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.succeeded ? .green : .red)
                                .help(result.succeeded ? "Done" : (result.errorDescription ?? "Failed"))
                        } else if NoteStore.hasNote(url: url) {
                            Image(systemName: "note.text")
                                .foregroundStyle(.secondary)
                                .help("Already has a note")
                        }
                    }
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags to Add").font(.subheadline.weight(.semibold))
            TagPillEditor(tags: $model.tagsToAdd, draft: $model.tagDraft)
        }
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Note Body (optional)").font(.subheadline.weight(.semibold))
            TextEditor(text: $model.body)
                .font(.body)
                .frame(minHeight: 90)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
        }
    }

    private var modePicker: some View {
        Picker("Body", selection: $model.mode) {
            Text("Add to existing").tag(BatchBodyMode.append)
            Text("Replace").tag(BatchBodyMode.replace)
            Text("Only if empty").tag(BatchBodyMode.onlyIfEmpty)
        }
        .pickerStyle(.segmented)
    }

    private var applyRow: some View {
        HStack {
            Button("Apply to \(model.fileURLs.count) Files") { model.apply() }
                .buttonStyle(.borderedProminent)
                .disabled(model.isApplying || (model.tagsToAdd.isEmpty && model.tagDraft.isEmpty && model.body.isEmpty))
            if let summary = model.summary {
                Text("\(summary.successCount) succeeded · \(summary.failureCount) failed")
                    .font(.callout)
                    .foregroundStyle(summary.failureCount == 0 ? Color.secondary : Color.orange)
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

// MARK: - Model

@MainActor
final class BatchEditModel: ObservableObject {
    let fileURLs: [URL]

    @Published var tagsToAdd: [String] = []
    @Published var tagDraft: String = ""
    @Published var body: String = ""
    @Published var mode: BatchBodyMode = .append
    @Published private(set) var summary: BatchSummary?
    @Published var status: String?
    @Published var isApplying = false

    init(fileURLs: [URL]) {
        self.fileURLs = fileURLs
    }

    func result(for url: URL) -> BatchFileResult? {
        summary?.results.first { $0.fileURL == url }
    }

    func apply() {
        isApplying = true
        // Merge a half-typed tag like the note editor does on Save.
        var tags = tagsToAdd
        for piece in TagPillEditor.pieces(from: tagDraft)
        where !tags.contains(where: { $0.caseInsensitiveCompare(piece) == .orderedSame }) {
            tags.append(piece)
        }
        tagsToAdd = tags
        tagDraft = ""

        let bodyText = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = BatchNoteService.apply(
            tags: tags,
            body: bodyText.isEmpty ? nil : bodyText,
            mode: mode,
            to: fileURLs
        )
        self.summary = summary

        // Refresh the registry + Finder badges for every file that took a note.
        for result in summary.results where result.succeeded {
            if let note = try? NoteStore.read(url: result.fileURL) {
                KnownFilesRegistry.shared.upsert(fileURL: result.fileURL, note: note)
            }
        }
        BadgeRegistryBridge.refresh()

        status = summary.failureCount == 0
            ? "Applied to all \(summary.successCount) files ✓"
            : "\(summary.failureCount) file(s) failed — hover the ✕ marks for details."
        isApplying = false
    }
}

// MARK: - tether://batch hand-off from the Finder Sync extension

/// The sandboxed Finder Sync extension can't pass a long file list through a
/// URL query reliably, so for multi-selection it writes the selected paths as
/// JSON into its container's tmp directory and opens `tether://batch?ref=<file>`.
/// The (unsandboxed) app reads the file back here and deletes it afterwards.
enum BatchRequestLoader {
    /// Directory the extension writes into: `NSTemporaryDirectory()` inside
    /// its sandbox resolves to `<container>/Data/tmp`.
    private static var extensionTmpURL: URL {
        URL(fileURLWithPath: "/Users/\(NSUserName())", isDirectory: true)
            .appendingPathComponent("Library/Containers/com.tether.app.FinderSync/Data/tmp", isDirectory: true)
    }

    /// Parses `tether://batch?ref=<filename>` and loads the referenced path
    /// list. Returns `nil` for malformed URLs, missing files, or bad JSON.
    static func fileURLs(from url: URL) -> [URL]? {
        guard url.scheme == "tether", url.host == "batch",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let ref = comps.queryItems?.first(where: { $0.name == "ref" })?.value,
              !ref.isEmpty,
              // The ref must be a plain filename, never a path.
              !ref.contains("/"), !ref.contains("\\"), ref != ".."
        else { return nil }

        let fileURL = extensionTmpURL.appendingPathComponent(ref, isDirectory: false)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        guard let data = try? Data(contentsOf: fileURL),
              let paths = try? JSONDecoder().decode([String].self, from: data),
              paths.count > 1
        else { return nil }
        return paths.map { URL(fileURLWithPath: $0) }
    }
}
