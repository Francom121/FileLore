import SwiftUI
import AppKit

/// Pill/chip editor for a note's tags.
///
/// Each tag renders as an accent-tinted pill with a × remove button; the pills
/// wrap across lines. The inline field at the end commits a new pill on
/// Return, Tab, or comma (pasted "a, b, c" splits into several pills). Tags
/// are trimmed, empties rejected, and duplicates refused case-insensitively.
/// Double-clicking a pill turns it back into an inline editor — Return/Tab
/// commits, Esc cancels. Right-clicking a pill pins/unpins the tag (shared
/// `PinnedTagsStore`); pinned pills show a small pin glyph.
struct TagPillEditor: View {
    @Binding var tags: [String]
    /// The in-progress (not yet committed) text of the new-tag field. Lifted
    /// into the model so Save can merge a half-typed tag the user never
    /// committed with Return/Tab/comma.
    @Binding var draft: String

    @State private var editingIndex: Int?
    @State private var editDraft = ""

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                if editingIndex == index {
                    TagTextField(
                        text: $editDraft,
                        placeholder: "",
                        autoFocus: true,
                        onCommit: { _ in commitEdit(at: index) },
                        onCancel: { editingIndex = nil }
                    )
                    .fixedSize()
                } else {
                    TagPill(
                        tag: tag,
                        onRemove: { remove(at: index) },
                        onEdit: { beginEdit(at: index) }
                    )
                }
            }

            TagTextField(
                text: $draft,
                placeholder: tags.isEmpty ? "Add tags…" : "Add…",
                autoFocus: false,
                onCommit: { _ in commitDraft() },
                onCancel: { draft = "" }
            )
            .frame(minWidth: 70)
            .fixedSize()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
    }

    // MARK: - Mutations

    private func commitDraft() {
        let pieces = Self.pieces(from: draft)
        draft = ""
        for piece in pieces where !containsCaseInsensitive(piece) {
            tags.append(piece)
        }
    }

    private func beginEdit(at index: Int) {
        guard tags.indices.contains(index) else { return }
        editDraft = tags[index]
        editingIndex = index
    }

    private func commitEdit(at index: Int) {
        // Guard against the endEditing double-fire when committing removes the
        // inline field (resigning its field editor sends a second commit).
        guard editingIndex == index else { return }
        editingIndex = nil
        guard tags.indices.contains(index) else { return }
        let candidate = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty {
            tags.remove(at: index)
        } else if !tags.enumerated().contains(where: {
            $0.offset != index && $0.element.caseInsensitiveCompare(candidate) == .orderedSame
        }) {
            tags[index] = candidate
        }
        // A candidate duplicating another pill is rejected: the pill reverts.
    }

    private func remove(at index: Int) {
        editingIndex = nil
        guard tags.indices.contains(index) else { return }
        tags.remove(at: index)
    }

    private func containsCaseInsensitive(_ candidate: String) -> Bool {
        tags.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
    }

    /// Trims and splits raw field text on commas, dropping empties.
    static func pieces(from raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Pill

private struct TagPill: View {
    let tag: String
    let onRemove: () -> Void
    let onEdit: () -> Void
    /// Observed so the pin glyph appears/disappears live when the tag is
    /// pinned or unpinned from anywhere (here, search, menu bar).
    @ObservedObject private var pinnedStore = PinnedTagsStore.shared

    var body: some View {
        HStack(spacing: 5) {
            if pinnedStore.isPinned(tag) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
            }
            Text(tag)
                .font(.callout)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove tag \(tag)")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.16), in: Capsule())
        .foregroundStyle(Color.accentColor)
        .onTapGesture(count: 2, perform: onEdit)
        .help("Double-click to edit · right-click to pin")
        .contextMenu {
            Button(pinnedStore.isPinned(tag) ? "Unpin Tag" : "Pin Tag") {
                pinnedStore.toggle(tag)
            }
        }
    }
}

// MARK: - Wrapping layout

/// Minimal left-to-right, top-to-bottom wrapping layout (dependency-free).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [CGSize] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                rows.append(CGSize(width: rowWidth, height: rowHeight))
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        if rowWidth > 0 {
            rows.append(CGSize(width: rowWidth, height: rowHeight))
        }

        let totalHeight = rows.reduce(0) { $0 + $1.height }
            + CGFloat(max(rows.count - 1, 0)) * spacing
        let usedWidth = rows.map(\.width).max() ?? 0
        return CGSize(width: min(usedWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - AppKit-backed tag field

/// Why AppKit: SwiftUI's `TextField` can't reliably intercept Tab (focus
/// movement) or comma on macOS, so tag entry/editing uses an `NSTextField`
/// whose delegate handles Return, Tab, comma, and Esc exactly.
struct TagTextField: NSViewRepresentable {
    enum CommitTrigger { case returnKey, tab, comma }

    @Binding var text: String
    var placeholder: String
    var autoFocus: Bool
    var onCommit: (CommitTrigger) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.stringValue = text
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.lineBreakMode = .byTruncatingTail
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.pendingFocus = autoFocus
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        if context.coordinator.pendingFocus {
            context.coordinator.pendingFocus = false
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TagTextField
        var pendingFocus = false

        init(_ parent: TagTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let value = field.stringValue

            // A comma commits everything before the last comma as pill(s) and
            // keeps the remainder in the field, so pasting "a, b, c" works.
            if let lastComma = value.lastIndex(of: ",") {
                let committed = String(value[..<lastComma])
                let remainder = String(value[value.index(after: lastComma)...])
                parent.text = committed
                parent.onCommit(.comma)
                field.stringValue = remainder
                parent.text = remainder
                field.currentEditor()?.selectedRange = NSRange(location: remainder.utf16.count, length: 0)
                return
            }
            parent.text = value
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            // Losing focus commits whatever is in the field (standard chip-editor
            // behavior; a no-op when the field is empty).
            parent.onCommit(.returnKey)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)): // Return
                parent.onCommit(.returnKey)
                return true
            case #selector(NSResponder.insertTab(_:)): // Tab
                parent.onCommit(.tab)
                return true
            case #selector(NSResponder.cancelOperation(_:)): // Esc
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}
