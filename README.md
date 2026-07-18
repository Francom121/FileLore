# FileLore

Notes that stay attached to your files — through renames, moves, and everything else.

FileLore attaches a sticky note to any file on your Mac. The note lives **on the file itself** as an extended attribute (xattr), not in a database, so it travels with the file through renames and folder moves on the same volume. Primary use case: keeping AI generation prompts, model info, and reference links attached to generated media.

See `SPEC.md` for the full product spec (written under the app's original name, Tether).

> **Renamed from Tether.** The app was originally built as "Tether" and is now **FileLore**. See *Rename migration* below for what carries over and what resets.

## Architecture

```
FileLore.xcodeproj        Hand-authored (objectVersion 77, synchronized folders, no generators)
├── FileLore/             SwiftUI macOS app — drop zone, note editor, menu bar recent list
│   ├── Assets.xcassets     AppIcon (squircle + quill logo, all mac icon sizes)
│   └── BadgeRegistryBridge.swift  publishes noted-file (dev, ino) registry into the Finder Sync container
├── FileLoreQuickLook/    Quick Look preview extension (com.apple.quicklook.preview)
├── FileLoreFinderSync/   Finder Sync extension (com.apple.FinderSync) — badges + context menu
│   ├── FileLoreBadge.png   amber quill-circle badge glyph (36×36, transparent margin)
│   └── BadgeRegistryReader.swift  inode-based badge lookup against the mirrored registry
└── TetherCore/           Local Swift package linked by all three targets
    (module name kept from the original app to avoid code churn)
    ├── Note.swift          Note / LinkedFile models + versioned JSON envelope (version: 1)
    ├── NoteStore.swift     getxattr/setxattr/removexattr read/write/delete of com.filelore.note
    ├── BookmarkResolver.swift  Security-scoped bookmark create/resolve + stale/broken status
    ├── LinkDetector.swift  http/https URL detection via NSDataDetector
    ├── SearchEngine.swift  Spotlight-style ranked search (name > tags > body, snippets)
    ├── BatchNoteService.swift  batch tag/body apply with append/replace/onlyIfEmpty modes
    └── MarkdownExporter.swift  note → Markdown document rendering
```

Bundle IDs: `com.filelore.app` (app), `com.filelore.app.QuickLook`,
`com.filelore.app.FinderSync`. URL scheme: `filelore://`.

### Where notes live

- **xattr name:** `com.filelore.note` — the same underlying mechanism macOS uses for Finder comments.
- **Payload:** JSON envelope `{ "version": 1, "note": { body, tags, links, created, modified } }`.
  `version` allows future payload migrations; unknown newer versions are rejected loudly.
- Survives: renames and moves on the same volume. Lost when: copying to another volume
  (most copy paths strip unknown xattrs), zipping, or some cloud-sync edge cases.

### Rename migration (Tether → FileLore)

- **xattr:** reads fall back to the legacy `com.tether.note` attribute, so
  Tether-era notes keep working. Every save writes `com.filelore.note` and
  removes the legacy attribute, so files migrate opportunistically as they're
  touched. Delete removes both names.
- **App Support:** on launch, `~/Library/Application Support/Tether` is moved
  to `~/Library/Application Support/FileLore` (or, if both exist, the known
  files — `known-files.json`, `badge-registry.json` — are merge-copied without
  overwriting newer FileLore data).
- **What resets on rename** (one-time, because macOS keys these by bundle ID):
  - The **Finder Sync** and **Quick Look** extensions must be re-enabled:
    System Settings → Privacy & Security → Extensions → enable **FileLore**
    under *Finder Extensions* and *Quick Look*.
  - The **Automation permission** ("FileLore wants to control Finder")
    re-prompts on the first ⌥T press — approve it once.
  - **Custom global shortcuts** reset to defaults (⌥T / ⇧⌘F) because
    UserDefaults are stored per bundle ID — rebind via the menu bar icon →
    Global Shortcut… if you had changed them.
  - The **"Open FileLore Note" Service** shortcut (if you assigned one in
    System Settings) must be reassigned.
  - The login item (if you want one) must be re-created — Settings →
    **Launch FileLore at login**.

### Linked files

- Links to reference files (photos, etc.) are stored as **security-scoped bookmarks**
  (base64 `Data` inside the JSON envelope) plus a cached `displayName` and a cached
  relative-path hint.
- Bookmarks resolve by file identity on the volume, so they survive renames and folder
  moves on the same drive. They break across volumes or after delete-and-recreate.
- Broken links surface in the editor as "Link broken — relink?" with an NSOpenPanel relink flow.

### Registry

- `~/Library/Application Support/FileLore/known-files.json` records noted files
  (path, name, tags, body preview, timestamp) on every save/delete. The menu-bar
  recent list and the search window both build on it.

### Badge registry bridge

- The Finder Sync extension is sandboxed and **cannot read the `com.filelore.note`
  xattr**, so it can't decide on its own which files to badge. The (unsandboxed)
  main app bridges that gap: after every note save/delete and once at app launch,
  `BadgeRegistryBridge` rebuilds `badge-registry.json` — one entry per noted file
  with `path` (hint), `dev` (st_dev), `ino` (st_ino), `updatedAt` — derived from
  `known-files.json` re-validated with live `NoteStore.hasNote` checks (entries
  whose file vanished or lost its note are dropped).
- The registry is written atomically (temp file + `rename`) to the canonical
  `~/Library/Application Support/FileLore/badge-registry.json` **and** mirrored
  into the extension container at
  `~/Library/Containers/com.filelore.app.FinderSync/Data/badge-registry.json`
  (skipped silently, and retried next launch, if the container doesn't exist
  yet). Each successful bridge write posts the Darwin notification
  `com.filelore.app.badgesChanged` so the extension reloads immediately.
- The extension (`BadgeRegistryReader`) stats each badge-requested URL and
  matches its (dev, ino) against the mirrored registry, reloading when the
  file's mtime changes or the Darwin notification fires. Because matching is by
  inode, badges survive renames and moves on the same volume — same guarantee
  as the xattr itself. A direct `NoteStore.hasNote` read remains only as a
  last-resort fallback when the registry has no match.
- The badge image itself is `FileLoreBadge.png`, the amber quill circle from the
  app logo cropped with a transparent margin (36×36 = 18pt @2x), bundled in the
  appex. The SF Symbol `note.text` remains as a fallback if the resource is missing.

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
xcodebuild -project FileLore.xcodeproj -scheme FileLore -configuration Debug \
  -destination 'platform=macOS' build
```

Or open `FileLore.xcodeproj` in Xcode 26 and build the **FileLore** scheme (⌘B).

## Install for personal use

1. Build (Release recommended):
   ```sh
   xcodebuild -project FileLore.xcodeproj -scheme FileLore -configuration Release \
     -destination 'platform=macOS' build
   ```
2. Copy `FileLore.app` from the build products directory to `/Applications`.
3. Launch it once via right-click → **Open** (one-time Gatekeeper bypass for the
   ad-hoc signed app).
4. Enable the extensions: **System Settings → Privacy & Security → Extensions** →
   enable **FileLore** under *Finder Extensions* and *Quick Look*.
5. Optional: menu bar icon → **Global Shortcut: ⌥T…** → enable
   **Launch FileLore at login** (uses SMAppService; no helper bundle needed
   because the app is unsandboxed).

## Usage

### How to view/edit a note

- **⌥T (Option-T)** — select a file in Finder and press ⌥T to open its note editor.
  The first press triggers a one-time *"FileLore wants to control Finder"* permission
  dialog; approve it once. If nothing is selected, FileLore shows the drop-zone window.
  The shortcut is customizable: menu bar icon → **Global Shortcut: ⌥T…** opens a
  recorder window — click the field, press the new combo (must include at least one
  of ⌘⌥⇧⌃), and it takes effect immediately. Default is ⌥T; **Reset to ⌥T** restores it.
- **⇧⌘F (Shift-Command-F)** — opens the Spotlight-style **search window** from
  anywhere (works in the background like ⌥T, customizable via the same settings
  window, second recorder row — **Reset to ⇧⌘F** restores it). Also reachable via
  the menu bar icon → **Search Notes…** and **⌘F** while the app is active.
- **Finder right-click → Add/Edit FileLore Note** — provided by the Finder Sync
  extension; also available as a Finder toolbar button.
- **Finder right-click → Services / Quick Actions → Open FileLore Note** — a macOS
  Service that accepts selected files. You can assign it *any* shortcut you like:
  **System Settings → Keyboard → Keyboard Shortcuts → Services → Open FileLore Note**.
- **Menu bar** — the FileLore icon lists the 10 most recently noted files.
  **Click** opens the note editor; **⌥-click** reveals the file in Finder.
- **Drop zone / Dock icon** — drop a file onto the FileLore window or Dock icon.
  Dropping **several files at once** opens the batch editor instead of many
  single editors (see *Batch tagging* below).
- **`filelore://open?path=...`** — opens the editor for a file (used internally by
  the Finder Sync context menu). `filelore://batch?ref=...` opens the batch
  editor for a multi-selection (the Finder Sync extension hands the file list
  over through a JSON file in its container's tmp directory).

### Search

- Spotlight-style floating panel over every noted file: live results as you
  type, ranked name matches > tag matches > body matches (most recently
  modified first within a tier), with body hits showing a short excerpt.
  Matching is case- and diacritic-insensitive ("cafe" finds "café").
- **↩ / click** opens the note editor; **⌘↩ / right-click** reveals the file
  in Finder. A strip of tag chips above the results AND-filters them.
- Files whose note xattr vanished since they were registered are flagged
  "note missing"; files that no longer exist are skipped.

### Batch tagging / batch notes

- Select several files and apply the same tags (and optionally the same note
  body) to all of them in one action. Body modes: **Add to existing** /
  **Replace** / **Only if empty**; tags merge case-insensitively without
  clobbering existing ones. Per-file results (✓/✕) are shown inline, and
  badges appear for newly-noted files.
- Entry points: drop multiple files on the drop zone or Dock icon, or select
  several files in Finder → right-click → **Batch Tag with FileLore…**
  (single selection keeps the classic "Add/Edit FileLore Note").

### Markdown export

- In the note editor, **Export…** (next to Copy) → **Save as Markdown…**
  (default name `<filename>.md`) or **Copy Markdown to Clipboard**. The
  document is `# <filename>`, the body verbatim, `**Tags:** #a #b`, a
  `**Linked files:**` list (resolved paths, or "(broken link)"), and
  `*Noted <date>*`.
- **Spacebar (Quick Look)** — for media files (video, images, audio, PDFs…) the
  system's default previewer always wins, so spacebar keeps showing the normal
  preview/player. FileLore's Quick Look extension only kicks in as a fallback for
  file types that have no system previewer.

**Badges:** files with notes get the FileLore quill badge on the file's icon in
Finder — but only in **icon view (⌘1)** and **list view (⌘2)**. macOS does not
render Finder Sync badges in **column view (⌘3)** or **gallery view (⌘4)** at
all, so their absence there is expected, not a bug. The badge decision comes
from the badge registry bridge (see Architecture): the main app publishes noted
files by inode into the extension's container, so badges appear without the
sandboxed extension reading any xattrs.

### Editing

- Editor: real file thumbnail in the header (Quick Look), multiline body,
  **tag pills** — type a tag and press **Return**, **Tab**, or **,** to add it
  (pasting `a, b, c` adds three); click a pill's **×** to remove it;
  **double-click** a pill to edit it inline (**Return** commits, **Esc** cancels);
  duplicates are refused case-insensitively — template menu (Blank / AI Generation),
  drop files into **Linked Files** to attach them as bookmarks,
  Save / Delete Note / Copy.
- Finder: files with notes get the quill badge on the file's icon
  (requires the Finder Sync extension; icon view ⌘1 / list view ⌘2 only — never
  column view ⌘3 or gallery view).

## Current limitations

- **Quick Look as fallback only:** the Quick Look extension declares `public.data`,
  but in practice macOS prefers the *most specific* preview generator, so files
  with a system previewer (media, PDFs, etc.) keep their default spacebar preview.
  FileLore's preview appears only for types no other generator claims. A dedicated
  "view note" gesture for media files is ⌥T or the right-click menu instead.
- Templates are built-in only; the UserDefaults-backed store for custom templates exists
  but the editing UI is future work.
- Finder Sync badge refresh is event-driven by Finder; the app nudges the
  extension via a Darwin notification (`com.filelore.app.badgesChanged`) whenever
  the badge registry changes, but the badge itself appears only when Finder
  next asks the extension for the file's badge. After updating the app, Finder
  may need to re-observe a folder (open it / right-click inside it) before
  badges and the context menu show up there.
- Notes do not follow files copied to other volumes/cloud drives (xattr limitation,
  by design of the storage model).
- Linked files: single click opens in the default app; inline Quick Look preview of
  linked thumbnails is a later milestone.

## Build-order checklist (from SPEC.md)

1. ✅ Core read/write/edit engine for notes (extended attributes) — `TetherCore.NoteStore`, 51 unit tests green.
2. ✅ Drag-and-drop app for creating/editing notes (text) — drop zone, Dock-icon open, per-file editor windows.
3. ✅ Security-scoped bookmark logic for linked files + broken link/relink handling.
4. ✅ Web link auto-detection in note text — clickable in editor preview, Quick Look, and copy flows.
5. ✅ Quick Look extension — renders the note for file types no system previewer claims; media files keep the default spacebar preview (most-specific generator wins).
6. ✅ Finder Sync extension — badges + "Add/Edit FileLore Note" context menu (watches the real home directory from inside the sandbox, plus iCloud Drive Desktop/Documents mirrors).
7. ✅ Tags/categories + search — tag pills in the editor; Spotlight-style search window (⇧⌘F global hotkey, ⌘F in-app, menu bar item) with ranked results, snippets, and tag-chip filters.
8. ✅ Templates + quick copy — built-in templates (Blank / AI Generation), UserDefaults store, Copy button.
9. ✅ Batch tagging — multi-file drops (drop zone / Dock) and Finder "Batch Tag with FileLore…" open one batch editor; tags merge case-insensitively; body modes add/replace/only-if-empty.
10. ✅ Menu bar quick-access panel — 10 most recent noted files; click opens the note, ⌥-click reveals in Finder.
11. ✅ Markdown export — editor "Export…" menu saves/copies a `# filename` Markdown doc with body, tags, linked files (broken links marked), and noted date.

**Also shipped after M1:** customizable global hotkeys (Carbon, defaults ⌥T open-note / ⇧⌘F search, signature `FLOR`) — rebind via menu bar → Global Shortcut…, "Open FileLore Note" macOS Service (assignable to any shortcut), centralized URL/window routing so `filelore://` links and Dock drops work even with all windows closed, launch-at-login toggle (SMAppService), the FileLore app icon + Finder badge glyph from the logo, and a launch fix so Dock-icon launches open exactly one main window.
