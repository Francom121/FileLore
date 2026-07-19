import SwiftUI
import AppKit

/// In-app keyboard shortcut cheat sheet.
///
/// The two global hotkeys are user-customizable in Settings, so their key
/// caps are read live from `GlobalShortcutStore` on every render — the panel
/// always shows the CURRENTLY configured combo, never a hard-coded string.
/// Everything else is a fixed binding extracted from the code (editor ⌘S,
/// search window ↩/⌘↩/arrows, menu bar ⌥-click, Finder interactions).
struct ShortcutsPanelView: View {
    /// Re-rendered on appear so a shortcut rebound while the panel is open
    /// shows up the next time the window is focused.
    @State private var openNoteShortcut = GlobalShortcutStore.load(.openNote)
    @State private var searchShortcut = GlobalShortcutStore.load(.search)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Global — work from anywhere", rows: [
                    (openNoteShortcut.displayString,
                     "Open the note editor for the current Finder selection  ·  customizable in Settings"),
                    (searchShortcut.displayString,
                     "Open the Spotlight-style search over all noted files  ·  customizable in Settings"),
                ])

                section("FileLore active", rows: [
                    ("⌘F", "Open the search window"),
                ])

                section("Note Editor", rows: [
                    ("⌘S", "Save the note"),
                    ("↩ / ⇥ / ,", "Commit the tag being typed into a pill"),
                    ("⎋", "Clear the tag draft / cancel an inline tag edit"),
                ])

                section("Search Window", rows: [
                    ("↩", "Open the selected result's note"),
                    ("⌘↩", "Reveal the selected result in Finder"),
                    ("↑ / ↓", "Move the selection"),
                ])

                section("Menu Bar", rows: [
                    ("click", "Open the note for a recent file / pinned-tag file"),
                    ("⌥-click", "Reveal the file in Finder instead"),
                ])

                section("Finder", rows: [
                    ("right-click", "“Add/Edit FileLore Note” on a file · “Batch Tag with FileLore…” on a multi-selection"),
                    ("Services", "“Open FileLore Note” — assign any shortcut in System Settings → Keyboard → Services"),
                    ("Space", "Quick Look on a noted file shows the note beside the media preview"),
                    ("drag", "Drop file(s) on the FileLore Dock icon or the main window to open a note"),
                ])
            }
            .padding(20)
        }
        .frame(width: 520)
        .frame(maxHeight: 560)
        .onAppear {
            openNoteShortcut = GlobalShortcutStore.load(.openNote)
            searchShortcut = GlobalShortcutStore.load(.search)
        }
    }

    private func section(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider() }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        KeyCap(label: row.0)
                            .frame(width: 84, alignment: .leading)
                        Text(row.1)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

/// A keyboard-key-styled label (rounded cap, monospaced glyphs).
private struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(.callout, design: .rounded).weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12))
            )
    }
}
