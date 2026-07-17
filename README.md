# Tether

Notes that stay tethered to your files — through renames, moves, and everything else.

Tether attaches a sticky note to any file on your Mac. The note lives **on the file itself** as an extended attribute (xattr), not in a database, so it travels with the file through renames and folder moves on the same volume. Primary use case: keeping AI generation prompts, model info, and reference links attached to generated media.

See `SPEC.md` for the full product spec.

## Architecture

```
Tether.xcodeproj          Hand-authored (objectVersion 77, synchronized folders, no generators)
├── Tether/               SwiftUI macOS app — drop zone, note editor, menu bar recent list
├── TetherQuickLook/      Quick Look preview extension (com.apple.quicklook.preview)
├── TetherFinderSync/     Finder Sync extension (com.apple.FinderSync) — badges + context menu
└── TetherCore/           Local Swift package linked by all three targets
    ├── Note.swift          Note / LinkedFile models + versioned JSON envelope (version: 1)
    ├── NoteStore.swift     getxattr/setxattr/removexattr read/write/delete of com.tether.note
    ├── BookmarkResolver.swift  Security-scoped bookmark create/resolve + stale/broken status
    └── LinkDetector.swift  http/https URL detection via NSDataDetector
```

### Where notes live

- **xattr name:** `com.tether.note` — the same underlying mechanism macOS uses for Finder comments.
- **Payload:** JSON envelope `{ "version": 1, "note": { body, tags, links, created, modified } }`.
  `version` allows future payload migrations; unknown newer versions are rejected loudly.
- Survives: renames and moves on the same volume. Lost when: copying to another volume
  (most copy paths strip unknown xattrs), zipping, or some cloud-sync edge cases.

### Linked files

- Links to reference files (photos, etc.) are stored as **security-scoped bookmarks**
  (base64 `Data` inside the JSON envelope) plus a cached `displayName` and a cached
  relative-path hint.
- Bookmarks resolve by file identity on the volume, so they survive renames and folder
  moves on the same drive. They break across volumes or after delete-and-recreate.
- Broken links surface in the editor as "Link broken — relink?" with an NSOpenPanel relink flow.

### Registry

- `~/Library/Application Support/Tether/known-files.json` records noted files
  (path, name, tags, body preview, timestamp) on every save/delete. The menu-bar
  recent list uses it now; the search feature (later milestone) will build on it.

### Sandboxing

- **Host app is NOT sandboxed** — it must freely read/write xattrs on arbitrary user files.
- **Both extensions are sandboxed** (Finder Sync requires it; Quick Look extensions are
  sandboxed by nature) with `com.apple.security.files.user-selected.read-only`.
- Everything is ad-hoc signed (`CODE_SIGN_IDENTITY = "-"`, no team) for personal use.

## Build

```sh
# Core package tests
cd TetherCore && swift test

# App + both extensions
xcodebuild -project Tether.xcodeproj -scheme Tether -configuration Debug \
  -destination 'platform=macOS' build
```

Or open `Tether.xcodeproj` in Xcode 26 and build the **Tether** scheme (⌘B).

## Install for personal use

1. Build (Release recommended):
   ```sh
   xcodebuild -project Tether.xcodeproj -scheme Tether -configuration Release \
     -destination 'platform=macOS' build
   ```
2. Copy `Tether.app` from the build products directory to `/Applications`.
3. Launch it once via right-click → **Open** (one-time Gatekeeper bypass for the
   ad-hoc signed app).
4. Enable the extensions: **System Settings → Privacy & Security → Extensions** →
   enable **Tether** under *Finder Extensions* and *Quick Look*.

## Usage

### How to view/edit a note

- **⌥T (Option-T)** — select a file in Finder and press ⌥T to open its note editor.
  The first press triggers a one-time *"Tether wants to control Finder"* permission
  dialog; approve it once. If nothing is selected, Tether shows the drop-zone window.
- **Finder right-click → Add/Edit Tether Note** — provided by the Finder Sync
  extension; also available as a Finder toolbar button.
- **Finder right-click → Services / Quick Actions → Open Tether Note** — a macOS
  Service that accepts selected files. You can assign it *any* shortcut you like:
  **System Settings → Keyboard → Keyboard Shortcuts → Services → Open Tether Note**.
- **Menu bar** — the Tether icon lists the 10 most recently noted files.
  **Click** opens the note editor; **⌥-click** reveals the file in Finder.
- **Drop zone / Dock icon** — drop a file onto the Tether window or Dock icon.
- **`tether://open?path=...`** — opens the editor for a file (used internally by
  the Finder Sync context menu).
- **Spacebar (Quick Look)** — for media files (video, images, audio, PDFs…) the
  system's default previewer always wins, so spacebar keeps showing the normal
  preview/player. Tether's Quick Look extension only kicks in as a fallback for
  file types that have no system previewer.

### Editing

- Editor: multiline body, comma-separated tags, template menu (Blank / AI Generation),
  drop files into **Linked Files** to attach them as bookmarks, Save / Delete Note / Copy.
- Finder: files with notes get a `note.text` badge (requires the Finder Sync extension).

## Current limitations

- **Quick Look as fallback only:** the Quick Look extension declares `public.data`,
  but in practice macOS prefers the *most specific* preview generator, so files
  with a system previewer (media, PDFs, etc.) keep their default spacebar preview.
  Tether's preview appears only for types no other generator claims. A dedicated
  "view note" gesture for media files is ⌥T or the right-click menu instead.
- Templates are built-in only; the UserDefaults-backed store for custom templates exists
  but the editing UI is future work.
- Finder Sync badge refresh is event-driven by Finder; after editing a note outside
  Finder's view, the badge may appear only when the folder is next observed. After
  updating the app, Finder may need to re-observe a folder (open it / right-click
  inside it) before badges and the context menu show up there.
- Notes do not follow files copied to other volumes/cloud drives (xattr limitation,
  by design of the storage model).
- Linked files: single click opens in the default app; inline Quick Look preview of
  linked thumbnails is a later milestone.

## Build-order checklist (from SPEC.md)

1. ✅ Core read/write/edit engine for notes (extended attributes) — `TetherCore.NoteStore`, 24 unit tests green.
2. ✅ Drag-and-drop app for creating/editing notes (text) — drop zone, Dock-icon open, per-file editor windows.
3. ✅ Security-scoped bookmark logic for linked files + broken link/relink handling.
4. ✅ Web link auto-detection in note text — clickable in editor preview, Quick Look, and copy flows.
5. ✅ Quick Look extension — renders the note for file types no system previewer claims; media files keep the default spacebar preview (most-specific generator wins).
6. ✅ Finder Sync extension — badges + "Add/Edit Tether Note" context menu (watches the real home directory from inside the sandbox, plus iCloud Drive Desktop/Documents mirrors).
7. ⬜ Tags/categories + search — tags model/UI done; search window pending (registry at `known-files.json` ready for it).
8. ✅ Templates + quick copy — built-in templates (Blank / AI Generation), UserDefaults store, Copy button.
9. ⬜ Batch tagging.
10. ✅ Menu bar quick-access panel — 10 most recent noted files; click opens the note, ⌥-click reveals in Finder.
11. ⬜ Markdown export.

**Also shipped after M1:** ⌥T global hotkey (Carbon) for the current Finder selection, "Open Tether Note" macOS Service (assignable to any shortcut), and centralized URL/window routing so `tether://` links and Dock drops work even with all windows closed.
