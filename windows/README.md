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
- **Drop zone:** launching FileLore with no file argument opens it (a
  second bare launch just raises it), or use tray menu → **New note /
  batch…** — one file opens the editor, several open the batch window.
  Dropping a file onto the Desktop
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

## Explorer badges (optional, off by default)

Noted files can show a **small FileLore badge in Explorer**, like
OneDrive's status icons. Tray menu → **Settings…** → **Show badges in
Explorer** — a one-time step that asks for admin rights **once** (Windows
only registers icon overlays machine-wide; everything else in FileLore
stays per-user and admin-free). The badge appears/disappears the moment a
note is saved or deleted — no manual refresh. Turn it off again from the
same Settings panel, or during uninstall. If too many other apps
(cloud-sync tools) have grabbed Windows' ~15 overlay slots, Settings says
so and tells you what to remove.

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

- **First launch:** a small branded **"Getting FileLore ready…"** window
  pops up the instant you double-click `FileLore.exe` — that's the tiny
  native **launcher** (0.7.1+), not the app itself. It stays up, spinner
  animating, while Windows does the one-time self-extraction + scan of the
  real app (up to a minute on the very first launch), and fades out the
  moment the app's first window appears. Later launches are fast.
- **An animated FileLore splash** (brand-orange spinner + logo) appears
  whenever the app is busy before a window can show — in-process startup
  work (tray, hotkeys, pipe setup), and the ~1.5 s pause while a
  multi-select batch is collected — so a quiet moment never looks like a
  hang. It fades out the instant the editor, batch window or drop zone is
  ready. The WPF splash cannot cover the first launch's self-extraction
  and CLR load, which happen before any WPF window can exist — that gap
  is exactly what the native launcher window covers (they hand off to
  each other seamlessly).
- **The search window updates live:** saving a note (tags, body, links —
  from the editor or a batch run) immediately updates open search results
  and tag chips; deleting a note removes its row. No Refresh needed.
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

- **Two-exe layout (0.7.1):** `FileLore.exe` is a tiny **native Win32
  launcher** (~200 KB, `src/FileLore.Launcher/`, no ATL/MFC, `/MT` static
  CRT, x64+ARM64 via `build-launcher.cmd`); `FileLoreApp.exe` is the WPF
  app (`<AssemblyName>FileLoreApp</AssemblyName>`). The launcher shows the
  branded "Getting FileLore ready…" card INSTANTLY (borderless layered
  window, brand cream `#FDF7EC` / orange `#EB961E`, pure-GDI comet
  spinner on a 16 ms timer), then launches `FileLoreApp.exe` from its own
  folder **on a worker thread** — CreateProcess of the ~180 MB single-file
  exe can block for many seconds during Defender's first-scan, and the
  window must never wait on that. It closes (fade-out) when the app
  process shows its first visible top-level window (EnumWindows by PID)
  OR exits without one (single-instance forward case); 5-minute failsafe.
  Pass-through modes skip the card: `--tray` (launch + exit immediately),
  `--version`/`-v`/`--selftest` (wait + propagate exit code). The
  right-click verb and shortcuts point at the LAUNCHER; the Run-key
  autostart points DIRECTLY at `FileLoreApp.exe --tray` (no card at
  login). Multi-select is unaffected: N launchers each wait for their
  spawned process, which forwards to the first instance and exits.
  The app also publishes with `<PublishReadyToRun>true</PublishReadyToRun>`
  (cuts JIT warmup jank; ~+16 MB exe size, still single-file).
- **Bumping the version:** edit `src/FileLore.App/AppVersion.cs`
  (`Number` + `BuildDate`) — that one file feeds the tray menu label and
  `FileLore.exe --version` (forwarded to the app). Also bump `<Version>`
  in `src/FileLore.App/FileLore.App.csproj` (exe file properties), the
  hardcoded version string near the top of `tools/Install-FileLore.cmd`,
  and the VERSIONINFO in `src/FileLore.Launcher/FileLoreLauncher.rc`.
- Core note store (ADS read/write, JSON envelope compatible with macOS),
  link resolver, Markdown exporter: `src/FileLore.Core/`
- WPF app (editor with media pane + links, batch window, drop zone, search
  window, tray, hotkeys, settings): `src/FileLore.App/`
- Startup/collection feedback: `SplashWindow` (all-XAML storyboard
  animations, brand palette, failsafe auto-close) shown via
  `App.ShowSplash`/`CloseSplash` around cold start and the multi-select
  debounce. Live search refresh: every save/delete raises
  `NoteEvents.NoteChanged(path)`; `SearchWindow` patches its in-memory
  index in place.
- Version visibility: tray menu shows `FileLore <version> (build <date>)`
  as a disabled item above Exit; `FileLoreApp.exe --version` prints the
  same line and exits (attaches to the parent console when there is one);
  the launcher forwards `--version` to the app without showing its card.
- Installer: `tools/Install-FileLore.cmd` verifies every registry write
  with a read-back (`[OK]`/`[FAIL]` per entry), reports the OLD vs NEW exe
  date when upgrading, and offers to restart Explorer at the end
  (`/q` prints a note instead). Field diagnostics:
  `tools/FileLore-Diagnose.cmd` — no admin, pure cmd, writes
  `FileLore-Diagnose.txt` to the Desktop (Windows build, exe presence,
  HKCU/HKLM verb dumps, Run key, running processes, `--version` output).
- Single-instance multi-select: `InstanceMessenger` (named pipe
  `FileLore.SingleInstance.Paths`, one UTF-8 line per path, ack per line).
- Shell thumbnails via `IShellItemImageFactory` P/Invoke (`ShellThumbnail`) —
  no NuGet packages.
- **Explorer overlay badge (0.7.0):** `src/FileLore.Overlay/` — a tiny
  no-ATL C++ `IShellIconOverlayIdentifier` (`FileLoreOverlay.dll`, ~200
  lines, `/MT` static CRT → zero dependencies inside explorer.exe; deps:
  kernel32/ole32/advapi32 only). `IsMemberOf` replicates
  `NoteIndex.HasNoteStream`'s `FindFirstStreamW(":filelore.note:$DATA")`
  check in native code; `GetPriority` returns 0; registered (opt-in,
  elevated — the `ShellIconOverlayIdentifiers` enumeration key is
  HKLM-only) under the key name **` FileLore` with ONE leading space**
  (OneDrive's alphabetical-priority convention, so we survive the ~15
  overlay limit). Build both arches with
  `src/FileLore.Overlay/build-overlay.cmd` (needs VS Build Tools:
  VCTools workload + `VC.Tools.ARM64` + Windows 11 SDK — install via
  `vs_BuildTools.exe --quiet --wait`; no winget in the VM).
  App side: `BadgeRegistration.cs` (status + read-only slot check +
  `runas`-verb launch of `tools/Register-FileLoreOverlay.cmd` /
  `Unregister-FileLoreOverlay.cmd`, which write the HKLM keys, fire
  `SHCNE_ASSOCCHANGED`, and restart Explorer); the CLSID
  `{7F3C1A2E-9B4D-4E5F-A6C7-1D2E3F4A5B6C}` is shared between the C++ and
  C#. Live refresh: `ShellBadgeRefresh.cs` hooks `NoteEvents` →
  `SHChangeNotify(SHCNE_UPDATEITEM, SHCNF_PATHW)` + **debounced
  `Shell.Application` window `Refresh()` on every open Explorer window
  showing the noted file's folder**. Measured on Win11 23H2: the
  SHChangeNotify alone makes a NEW badge appear (via the folder's
  change-notification revalidation) but NEVER removes one —
  `SHCNF_PATHW`/`SHCNF_IDLIST`/`FLUSHNOWAIT`/`SHCNE_ATTRIBUTES`/
  `SHCNE_UPDATEDIR`/same-path `SHCNE_RENAMEITEM` all fail to make Explorer
  re-run `IsMemberOf` for an already-displayed item; only a real folder
  refresh (F5 / `IWebBrowserApp.Refresh()`) does.
- Headless verification (all write PASS/FAIL lines to the result file,
  exit code 0 = pass) — run against `FileLoreApp.exe` directly (the
  launcher forwards `--selftest` too, but direct is simpler):
  - `FileLoreApp.exe --selftest <resultFile> <path> <body> <tagsCsv>` — save round-trip
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
- Dev hook for the note-selection hotkey handler: `FileLoreApp.exe --hotkey-open-selection`
- Explorer verb + shortcuts: `tools/install-context-menu.cmd`,
  `tools/install-shortcuts.ps1`; demo fixtures: `tools/vm-m5-fixtures.ps1`

## Known Mac-parity gaps

- No **Explorer preview-pane / Quick Look** integration.
- **No inline PDF rendering** in the editor (icon fallback).
- **Templates are per-device** (Mac templates are not synced).
- macOS security-scoped **bookmarks are placeholders** on Windows; links
  resolve by path + same-folder fallback instead.
