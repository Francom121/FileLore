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

- Drop a file onto the Tether window (or onto the Dock icon) to open its note editor.
- Editor: multiline body, comma-separated tags, template menu (Blank / AI Generation),
  drop files into **Linked Files** to attach them as bookmarks, Save / Delete Note / Copy.
- `tether://open?path=...` opens the editor for a file (used by the Finder Sync
  context menu item "Add/Edit Tether Note").
- Finder: files with notes get a `note.text` badge (requires the Finder Sync extension).
- Quick Look: spacebar on a noted file shows the note (requires the Quick Look extension).
- Menu bar: the Tether icon lists the 10 most recently noted files; click to reveal in Finder.

## Current limitations

- **Broad Quick Look claim:** the Quick Look extension declares `public.data` as its
  supported content type, so once enabled it can shadow the *default* Quick Look preview
  for files without notes (they show "no preview available" instead of the normal preview).
  This will be refined in a later milestone (e.g. narrower types or a smarter fallback).
- Templates are built-in only; the UserDefaults-backed store for custom templates exists
  but the editing UI is future work.
- Finder Sync badge refresh is event-driven by Finder; after editing a note outside
  Finder's view, the badge may appear only when the folder is next observed.
- Notes do not follow files copied to other volumes/cloud drives (xattr limitation,
  by design of the storage model).
- Linked files: single click opens in the default app; inline Quick Look preview of
  linked thumbnails is a later milestone.

## Build-order checklist (from SPEC.md)

1. ✅ Core read/write/edit engine for notes (extended attributes) — `TetherCore.NoteStore`, 24 unit tests green.
2. ✅ Drag-and-drop app for creating/editing notes (text) — drop zone, Dock-icon open, per-file editor windows.
3. ✅ Security-scoped bookmark logic for linked files + broken link/relink handling.
4. ✅ Web link auto-detection in note text — clickable in editor preview, Quick Look, and copy flows.
5. ⬜ Quick Look extension — **scaffolding done** (target builds, embeds, renders notes); runtime approval + shadowing refinement pending.
6. ⬜ Finder Sync extension — **scaffolding done** (badges + context menu compile and embed); runtime verification pending.
7. ⬜ Tags/categories + search — tags model/UI done; search window pending (registry at `known-files.json` ready for it).
8. ✅ Templates + quick copy — built-in templates (Blank / AI Generation), UserDefaults store, Copy button.
9. ⬜ Batch tagging.
10. ✅ Menu bar quick-access panel — 10 most recent noted files, click to reveal.
11. ⬜ Markdown export.
