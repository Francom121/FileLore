# FileLore for Windows

Sticky notes for your files. The note lives **inside the file itself**
(an NTFS alternate data stream, the same idea as the macOS version's
xattr), so it survives renames and moves **on the same drive** — there is
no database to lose or sync. Notes are plain JSON and readable by the Mac
app.

## Everyday use

- **Attach or edit a note:** right-click any file → **Show more options** →
  **FileLore Note**. (Windows 11 hides classic verbs in the modern menu;
  "Show more options" is the standard way in for now.)
- **Note the file you're looking at:** select it in Explorer and press
  **Ctrl+Alt+T**. Nothing selected? You get a file picker instead.
- **Find a note:** press **Ctrl+Alt+F** (or tray menu → **Search notes…**).
  Type to search note text, file names and tags; click a tag chip to
  filter; double-click a result to edit it. Use **Add folder…** to tell
  FileLore which folders to scan (default: `C:\FileLoreTest`).
- **Tray icon:** FileLore runs quietly in the notification area — click the
  **^** overflow arrow if you don't see it. Right-click it for recent
  notes, search, and Exit.
- **Keyboard in the editor:** Ctrl+S saves; Enter adds a tag.

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

- Notes survive rename and move **on the same NTFS drive**. Copying to
  another drive, a network share, OneDrive or email usually drops the
  hidden stream (Explorer may warn "the file has properties that can't be
  copied").
- Settings (search folders), recent notes and the app log live in
  `%LOCALAPPDATA%\FileLore\` (`settings.json`, `recents.json`, `app.log`).
- FileLore starts with Windows (registry Run key) in tray-only mode; delete
  the `FileLore` value under
  `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` to disable.
- Shortcuts are on the public Desktop and in Start Menu → Programs →
  FileLore.

## For developers

- Core note store (ADS read/write, JSON envelope compatible with macOS):
  `src/FileLore.Core/`
- WPF app (editor, search window, tray, hotkeys): `src/FileLore.App/`
- Headless verification: `FileLore.exe --selftest <resultFile> <path> <body> <tagsCsv>`,
  `FileLore.exe --selftest search <resultFile>` and
  `FileLore.exe --selftest netpath <resultFile>` (unsupported-location guard)
- Dev hook for the Ctrl+Alt+T handler: `FileLore.exe --hotkey-open-selection`
- Explorer verb + shortcuts: `tools/install-context-menu.cmd`,
  `tools/install-shortcuts.ps1`
