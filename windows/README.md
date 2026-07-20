# FileLore for Windows

Sticky notes for your files. The note lives **inside the file itself**
(an NTFS alternate data stream, the same idea as the macOS version's
xattr), so it survives renames and moves **on the same drive** — there is
no database to lose or sync. Notes are plain JSON and readable by the Mac
app (Swift Codable ignores the extra keys Windows adds, e.g. `path` inside
link entries; the shared keys `body, tags, links, created, modified, id,
bookmark, displayName, relativePathHint` are never renamed or removed).

## Everyday use

- **Attach or edit a note:** right-click any file → **Show more options** →
  **FileLore Note**. (Windows 11 hides classic verbs in the modern menu;
  "Show more options" is the standard way in for now.)
- **Batch many files at once:** select several files → right-click →
  **FileLore Note**. Explorer fires one process per file; instances 2..N
  forward their path to the first instance over a named pipe and exit, and
  a ~1.5 s debounce collects them into ONE batch window. Set / Append the
  body, Add / Replace tags, Apply — with per-file results and a summary
  ("5 notes updated, 1 skipped (network path)").
- **Drop zone:** tray menu → **New note / batch…** — one file opens the
  editor, several open the batch window. Dropping a file onto the Desktop
  shortcut works too (Windows passes it as the exe's argument → editor).
- **Note the file you're looking at:** select it in Explorer and press
  **Ctrl+Alt+T**. Nothing selected? You get a file picker instead.
- **Find a note:** press **Ctrl+Alt+F** (or tray menu → **Search notes…**).
  Type to search note text, file names and tags; click a tag chip to
  filter; **right-click a chip to pin it** (pinned chips sit on top with a
  📌 glyph; tray menu → **Pinned Tags** lists noted files per tag);
  double-click a result to edit it. **Ctrl/Shift-click multi-selects,
  Export… writes one Markdown** (grouped by tag when the selection spans
  ≥2 tags, exactly like the Mac) and reveals it in Explorer.

## Inside the note editor

- **Media peek (split layout, like the Mac):** video/audio play in a left
  pane (play/pause, scrub, volume; starts paused; codec cleanup on close).
  Images show aspect-fit. Formats WIC can't decode (e.g. PSD) fall back to
  a 256px shell thumbnail. PDFs and other non-media files show a big icon —
  **no inline PDF renderer (documented difference vs Mac)**.
- **Linked files:** drag files onto the editor or click **Add files…**.
  Each row shows a shell thumbnail, the name, and the parent folder; click
  opens the file, × removes. Links resolve by absolute path, then by
  same-folder fallback (a reference photo moved/renamed together with the
  noted file's folder is still found), else a red **"Link broken —
  relink?"** state with a Relink button that rebinds the path.
- **Templates:** the dropdown prefills an EMPTY note only (ships with
  "AI Generation": `Prompt:\n\nModel:\n\nVoice:\n\nLinks:\n`). **Manage
  templates…** adds/edits/deletes; persisted in settings.json. **Mac
  templates are NOT synced** — templates are per-device.
- **Export…** writes `<filename>-note.md` matching the Mac Markdown
  exporter's shape (header + `**File:**` + `**Tags:**`, body verbatim,
  `**Linked files:**` with resolved paths or "(broken link)", `*Noted …*`).

## Settings & hotkeys

- Tray menu → **Settings…** rebinds both global hotkeys (click a box,
  press a combo, Save). The old chords are unregistered first; a conflict
  keeps the previous binding and shows a balloon.
- Tray menu → **Keyboard Shortcuts…** lists every shortcut/interaction and
  always reflects the current bindings.

## Where notes work

- **Local NTFS drives (C:, D:, …): yes.** That's every normal Windows PC,
  so notes just work for files on the PC's own drives.
- **Network shares and mapped network drives: no.** Notes live in an NTFS
  alternate data stream, which only NTFS volumes can store — so files on
  NAS boxes, `\\server\share` paths and VM shared folders (e.g. Parallels
  `\\Mac\Home`) can't hold notes. FileLore tells you this in the editor and
  skips network folders when searching, instead of failing. Move or copy
  the file to a local folder and note it there.
- **FAT32/exFAT USB sticks: no**, for the same reason.

## Good to know

- **First launch can take up to a minute** (one-time self-extraction +
  Windows scan); later launches are fast.
- Notes survive rename and move **on the same NTFS drive**. Copying to
  another drive, a network share, OneDrive or email usually drops the
  hidden stream (Explorer may warn "the file has properties that can't be
  copied").
- Settings (search folders, templates, pinned tags, hotkeys), recent notes
  and the app log live in `%LOCALAPPDATA%\FileLore\` (`settings.json`,
  `recents.json`, `app.log`).
- FileLore starts with Windows (registry Run key) in tray-only mode; delete
  the `FileLore` value under
  `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` to disable.
- Shortcuts are on the Desktop and in Start Menu → Programs → FileLore.
- **Updating:** re-run `Install-FileLore.cmd` from the new zip — it stops
  the old copy, replaces the exe, and re-registers; notes and settings are
  kept. No uninstall needed.

## For developers

- Core note store (ADS read/write, JSON envelope compatible with macOS),
  link resolver, Markdown exporter: `src/FileLore.Core/`
- WPF app (editor with media pane + links, batch window, drop zone, search
  window, tray, hotkeys, settings): `src/FileLore.App/`
- Single-instance multi-select: `InstanceMessenger` (named pipe
  `FileLore.SingleInstance.Paths`, one UTF-8 line per path, ack per line).
- Shell thumbnails via `IShellItemImageFactory` P/Invoke (`ShellThumbnail`) —
  no NuGet packages.
- Headless verification (all write PASS/FAIL lines to the result file,
  exit code 0 = pass):
  - `FileLore.exe --selftest <resultFile> <path> <body> <tagsCsv>` — save round-trip
  - `--selftest search <resultFile>` — enumeration + text/tag search
  - `--selftest netpath <resultFile>` — unsupported-location guard
  - `--selftest links <resultFile>` — link write/read-back, same-folder
    fallback, broken state, relink
  - `--selftest batch <resultFile>` — Set/Append body, Add/Replace tags,
    UNC skip with reason
  - `--selftest export <resultFile>` — golden-compare per-note + batch
    Markdown (prints the outputs)
  - `--selftest templates|pins|hotkeys <resultFile>` — settings round-trips
    (settings.json is snapshot-restored; hotkey test must run in an
    interactive session — RegisterHotKey fails in session 0)
- Dev hook for the note-selection hotkey handler: `FileLore.exe --hotkey-open-selection`
- Explorer verb + shortcuts: `tools/install-context-menu.cmd`,
  `tools/install-shortcuts.ps1`; demo fixtures: `tools/vm-m5-fixtures.ps1`

## Known Mac-parity gaps

- No Finder-style **Explorer badges** on noted files.
- No **Explorer preview-pane / Quick Look** integration.
- **No inline PDF rendering** in the editor (icon fallback).
- **Templates are per-device** (Mac templates are not synced).
- macOS security-scoped **bookmarks are placeholders** on Windows; links
  resolve by path + same-folder fallback instead.
