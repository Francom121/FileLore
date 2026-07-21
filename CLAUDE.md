# FileLore — Project Context for AI Assistants

> **Purpose of this file:** everything an AI coding assistant needs to work on
> this repository cold — what exists, how it works, how to build/test/deploy,
> and the hard-won gotchas. All facts below were verified against the repo and
> live environment (see *Verification notes* at the bottom).

---

## 1. Quick start — read this first

**What this is:** FileLore is "sticky notes that live ON files" — no database.
Three deliverables in one repo:

| Deliverable | Status | Location |
|---|---|---|
| macOS app (Swift/SwiftUI/AppKit) | shipped v1 | `FileLore/`, `FileLoreFinderSync/`, `FileLoreQuickLook/`, `TetherCore/`, `FileLore.xcodeproj` |
| Windows app (C# WPF, .NET 8) | v0.6.0 | `windows/` |
| Marketing site (React+TS+Vite+Tailwind+shadcn) | built, not yet publicly deployed | `website/` |

Primary use case: attaching AI-generation prompts, model info, and reference
links to generated media files.

**Where to look for what:**

- Change note storage/format → `TetherCore/Sources/TetherCore/Note.swift` + `NoteStore.swift` (Mac) and `windows/src/FileLore.Core/Note.cs` + `NoteStore.cs` (Windows) — **always change both, additively**.
- macOS app UI/behavior → `FileLore/*.swift` (one file per feature; names are self-describing).
- Windows app UI/behavior → `windows/src/FileLore.App/` (WPF) — core logic in `windows/src/FileLore.Core/`.
- In-repo docs: `README.md` (Mac product doc), `windows/README.md` (Windows product + dev doc), `SPEC.md` (original spec), `SHORTCUTS.md` (Mac shortcut cheat sheet).

**What NOT to do (each of these has bitten someone):**

- ❌ Do **not** rename the Swift package module `TetherCore` or the `TetherCore/` directory — the legacy name is kept intentionally to avoid code churn. User-facing name is "FileLore" everywhere else.
- ❌ Do **not** rename the workspace root `/Users/fm/Documents/Tether` — paths, the Parallels share, and habits depend on it.
- ❌ Do **not** touch CleanMyMac's pluginkit state. It was deliberately disabled via `pluginkit -e ignore -i com.macpaw.CleanMyMac5.FinderSyncExtension` because it starved FileLore's Finder Sync extension. Current state (verified): FileLore appexes `+`, CleanMyMac5 FinderSync `-`.
- ❌ Do **not** re-enable Secure Boot in the Parallels "Windows 11" VM. It caused a firmware-mismatch boot failure incident; it stays off.
- ❌ Do **not** build the Windows app on the `\\Mac\Home` network share — always `robocopy` to `C:\filelore` inside the VM first (share is non-NTFS, slow, and breaks the build/ADS assumptions).
- ❌ Do **not** kill pre-existing listeners on ports 3000 or 7100 — other Kimi Work previews may live there.
- ❌ Do **not** change the cross-platform JSON format non-additively. Additive keys only; never rename or remove existing keys (see §3).
- ❌ Do **not** leave a dev server running after website work (see §8 preview convention).

---

## 2. Repository layout

```
/Users/fm/Documents/Tether          git repo root (branch: main)
├── FileLore.xcodeproj/             hand-authored Xcode project (objectVersion 77,
│                                   synchronized folders, no generators), scheme "FileLore"
├── FileLore/                       SwiftUI macOS app — editor, drop zone, search, menu bar,
│                                   settings, hotkeys, batch editor, URL/window routing
├── FileLoreFinderSync/             Finder Sync appex (sandboxed) — badges + context menu
├── FileLoreQuickLook/              Quick Look appex (sandboxed) — media+note split preview
├── TetherCore/                     local Swift package (module name INTENTIONALLY legacy)
│   ├── Sources/TetherCore/         Note, NoteStore, BookmarkResolver, LinkDetector,
│   │                               SearchEngine, BatchNoteService, MarkdownExporter,
│   │                               MediaPaneView/MediaPreview/LetterboxedImageView,
│   │                               ImageFitGeometry
│   └── Tests/TetherCoreTests/      9 test files, 76 tests (swift-testing)
├── windows/
│   ├── src/FileLore.Core/          net8.0 library: Note, NoteStore (ADS), NoteIndex
│   │                               (FindFirstStreamW enumeration), NoteSearch,
│   │                               LinkResolver, MarkdownExporter (mirrors Mac)
│   ├── src/FileLore.App/           WPF net8.0-windows app (zero NuGet deps)
│   ├── src/FileLore.M1Proof/       minimal console proof: ADS note survives rename/move
│   ├── tools/                      Install/Uninstall/Diagnose cmd + VM automation ps1 helpers
│   ├── dist-assets/                README-WINDOWS.txt + demo.wmv for the release zip
│   └── README.md                   Windows user + developer doc (selftests, versioning)
├── website/                        React+TS+Vite+Tailwind+shadcn marketing site
│   ├── src/sections/               Hero, Features, HowItWorks, AICreators, DemoVideo,
│   │                               DownloadCTA, Support, Footer, Nav
│   ├── src/config.ts               download URLs/sizes, DONATE_URL (ko-fi placeholder)
│   └── public/                     screenshots/, filelore-demo.mp4, downloads/ (gitignored)
├── tools/make_menubar_icon.py      generates the branded quill menu-bar icon
├── README.md                       Mac product doc (architecture, usage, limitations)
├── SPEC.md                         original product spec (written under the name "Tether")
├── SHORTCUTS.md                    Mac keyboard-shortcut cheat sheet
├── logo.png                        source logo (app icon, badge glyph, site assets derive from it)
└── .scratch/                       untracked working area (~500 MB of captures/scripts) — ignore
```

---

## 3. Data format (cross-platform, byte-compatible)

Envelope, stored as JSON:

```json
{
  "version": 1,
  "note": {
    "body": "…",
    "tags": ["…"],
    "links": [
      {
        "id": "uuid",
        "bookmark": "base64…",
        "displayName": "…",
        "relativePathHint": "…",
        "path": "C:\\…",        // Windows-added (additive)
        "size": 12345,          // Windows-added (additive)
        "added": 782000000.0    // Windows-added (additive)
      }
    ],
    "created": 782000000.0,
    "modified": 782000001.0
  }
}
```

- `created`/`modified` are **doubles: seconds since 2001-01-01T00:00:00Z** (Apple
  reference date). On the Swift side this is just `JSONEncoder`'s default
  `.deferredToDate` strategy — `NoteStore.swift` sets no explicit strategy.
- **Compatibility rule: additive keys only.** Windows adds `path`/`size`/`added`
  to link entries; Swift `Codable` ignores unknown keys, so both platforms read
  each other's payloads. Never rename/remove/change the type of an existing key.
- `version` exists for future payload migrations; unknown newer versions are
  rejected loudly (Mac) — bump deliberately.

**Storage:**

| Platform | Mechanism | Name |
|---|---|---|
| macOS | extended attribute | `com.filelore.note` (legacy `com.tether.note` is read as fallback and migrated on save/delete) |
| Windows | NTFS alternate data stream | `<path>:filelore.note` |

Consequences: notes survive rename/move on the same volume; they are lost when
copying across volumes, zipping, or through most cloud sync. Windows:
**non-NTFS locations (network shares, mapped drives, FAT32/exFAT, Parallels
`\\Mac\Home`) cannot hold notes** — `NoteStore.IsSupportedPath` returns a
friendly guard reason instead of failing, and search skips those folders.

**Links:**

- macOS: `LinkedFile.bookmark` is a **security-scoped bookmark** (base64 `Data`
  in JSON) — resolves by file identity, survives rename/move on the volume;
  broken links get an NSOpenPanel relink flow.
- Windows: `bookmark` is a placeholder; `LinkResolver` resolves by absolute
  `path`, then **same-folder fallback** (link target moved/renamed together
  with the noted file's folder is still found), else a red "Link broken —
  relink?" state with a Relink button.

---

## 4. macOS app

- **Bundle IDs:** `com.filelore.app`, `com.filelore.app.QuickLook`,
  `com.filelore.app.FinderSync` (verified in `project.pbxproj`).
- **URL scheme:** `filelore://` (`filelore://open?path=…`, `filelore://batch?ref=…`).
- **Signing:** ad-hoc (`CODE_SIGN_IDENTITY = "-"`, no team), personal use.
- **Sandboxing:** main app **unsandboxed** (must read/write xattrs on arbitrary
  files); both appexes sandboxed (`app-sandbox` + `files.user-selected.read-only`).
- **Deployment target:** macOS 15.0; Swift 5 language mode; built with Xcode 26.

### Features (all present in `FileLore/`)

- Note editor (`NoteEditorView.swift`) with **media peek** (`MediaPreviewView.swift`
  wrapping TetherCore's `MediaPaneView`): AVPlayerView for video/audio,
  letterboxed aspect-fit images, PDFView, text preview, icon fallback.
- Tag pills (`TagPillEditor.swift`) + pinned tags (`PinnedTagsStore.swift`,
  UserDefaults-backed).
- Search window (⇧⌘F global, `SearchView.swift` + `SearchEngine.swift`):
  ranked name > tags > body, snippets, tag-chip AND filters, multi-select,
  **batch Markdown export** (`MarkdownExporter.swift`, grouped by tag).
- Templates (`NoteTemplates.swift`), quick copy, per-note Markdown export.
- Batch tagging (`BatchEditView.swift` + `BatchNoteService.swift`): multi-drop
  and a Services/Finder route; body modes add/replace/only-if-empty.
- Menu bar dropdown (`RecentFilesMenu.swift`, `ShortcutsPanelView.swift`):
  10 recents, pinned-tag submenus, shortcuts panel; branded quill icon
  generated by `tools/make_menubar_icon.py`.
- Global hotkeys (`GlobalShortcut.swift`, `HotKeyManager.swift`, Carbon,
  signature `FLOR`): **⌥T** opens note for the Finder selection (via
  AppleScript — triggers a one-time "control Finder" permission prompt),
  **⇧⌘F** search. Both customizable in Settings; defaults resettable.
- Launch at login via `SMAppService.mainApp` (`SettingsView.swift`) — no helper
  bundle needed because the app is unsandboxed.
- Drop zone window (`DropZoneView.swift`), single-instance; centralized routing
  in `WindowRouter.swift`. Commit `a7bf586` fixed stray duplicated drop-zone
  windows on Finder-open/Services/URL routes — **do not regress this**.
- Right-click **Services verb** "Open FileLore Note" (declared in
  `FileLore/Info.plist`), plus Finder Sync context menu items.
- Dock-icon launch opens exactly one main window (double-window-on-launch fix —
  preserve it).

### Finder badge architecture (the tricky part)

The sandboxed Finder Sync extension **cannot read xattrs** (EPERM), so it
cannot decide what to badge on its own. Bridge:

1. Unsandboxed main app (`BadgeRegistryBridge.swift`) rebuilds
   `badge-registry.json` (entries: `path`, `dev`, `ino`, `updatedAt`) from
   `known-files.json` re-validated with live `NoteStore.hasNote` checks.
2. Written atomically to `~/Library/Application Support/FileLore/badge-registry.json`
   **and mirrored into the extension container**
   `~/Library/Containers/com.filelore.app.FinderSync/Data/badge-registry.json`.
3. Each bridge write posts Darwin notification `com.filelore.app.badgesChanged`.
4. The extension (`BadgeRegistryReader.swift`) reloads on mtime change or the
   notification and **proactively badges every registry path** (and clears
   stale ones); lookup order on Finder's ask: (dev,ino) → standardized path →
   sandboxed xattr read (last resort) → clear.

Badge limits (macOS, not bugs): badges render only in Finder **icon (⌘1) and
list (⌘2) views** — never column/gallery.

**Environment gotcha:** CleanMyMac5's FinderSync extension starved ours. It is
disabled with `pluginkit -e ignore -i com.macpaw.CleanMyMac5.FinderSyncExtension`.
Verified state: `pluginkit -m | grep -i filelore` shows both appexes with `+`.

### Quick Look (`FileLoreQuickLook/`)

- The appex **can** read xattrs inside its sandbox (verified) — unlike FinderSync.
- **macOS 26 reserves common UTIs** (mp4/mov/jpg/png/mp3/pdf/txt) for Apple's
  generators; our media+note split preview only fires for types with no system
  previewer (PSD, MKV, Markdown, dynamic UTIs). Spacebar on common media keeps
  the default player — expected, not a bug.
- `qlmanage -p` **cannot dispatch third-party appexes on macOS 26** — test via a
  custom QLPreviewPanel host instead.

### macOS 26 Tahoe environment notes

- Menu bar items collapse behind the **» chevron** — users must drag the icon
  out or enable it via System Settings → Menu Bar.
- After the Tether→FileLore rename (commit `bd101e2`), macOS keyed several
  things by bundle ID, so they reset once: extension enablement, Finder
  Automation permission, custom hotkeys (UserDefaults), Service shortcut,
  login item. Documented in `README.md` §Rename migration.

### Tests

```sh
cd TetherCore && swift test     # 76 tests, 0 failures (verified)
```

(Note: `README.md`'s build-order checklist still says "51 unit tests" — stale;
the real count is 76.)

---

## 5. Windows app (`windows/`, v0.6.0)

- `src/FileLore.Core/` — net8.0 library: `Note.cs` (System.Text.Json with the
  additive link keys), `NoteStore.cs` (ADS read/write + `IsSupportedPath`
  friendly guard), `NoteIndex.cs` (`FindFirstStreamW`/`FindNextStreamW` stream
  enumeration for search), `NoteSearch.cs`, `LinkResolver.cs`,
  `MarkdownExporter.cs` (mirrors the Mac exporter's shape).
- `src/FileLore.App/` — WPF `net8.0-windows`, **zero NuGet packages**, references
  only FileLore.Core. Self-contained single-file publish. Features: editor with
  media peek (`MediaElement` video/audio, WIC images, `IShellItemImageFactory`
  shell-thumbnail fallback for e.g. PSD; **no inline PDF** — documented gap),
  linked files UI, batch window + drop zone, templates, per-note + batch
  Markdown export, pinned tags, search window, tray (recents, pinned tags,
  version label above Exit), settings in `%LOCALAPPDATA%\FileLore\`
  (`settings.json`, `recents.json`, `app.log`).
- Global hotkeys **Ctrl+Alt+T / Ctrl+Alt+F** via `RegisterHotKey`
  (`HotkeyManager.cs`, defaults in `Settings.cs`); rebindable in Settings.
  RegisterHotKey fails in session 0 — hotkey selftest needs an interactive session.
- `src/FileLore.M1Proof/` — console proof that an ADS note survives rename and
  folder move.
- Explorer multi-select → Explorer spawns one process per file; instances 2..N
  forward paths to the first instance over named pipe
  `FileLore.SingleInstance.Paths` (`InstanceMessenger.cs`) + ~1.5 s debounce →
  ONE batch window. The pipe also carries `CMD SHOW-DROPZONE`: launching with
  no arguments opens the drop zone (first instance) or raises it on the
  already-running instance (second instance exits after sending the command);
  `--tray` autostart stays silent. Startup/busy feedback is the animated
  `SplashWindow` (never covers the first-run single-file extraction/JIT —
  that precedes any WPF window).
- Version source of truth: `src/FileLore.App/AppVersion.cs` (`Number = "0.6.0"`,
  `BuildDate`) — also bump `<Version>` in `FileLore.App.csproj` and the
  hardcoded string at the top of `tools/Install-FileLore.cmd`.

### Installer (`windows/tools/Install-FileLore.cmd`)

Per-user, no admin: installs to `%LOCALAPPDATA%\FileLore`, HKCU context-menu
verb, HKCU Run key (tray autostart), Desktop + Start Menu shortcuts. Every
`reg add` is verified with a `reg query` read-back (`[OK]`/`[FAIL]`), upgrades
report OLD vs NEW exe date, and it offers an Explorer restart (`/q` prints a
note instead). `FileLore-Diagnose.cmd` collects field diagnostics (no admin)
into `FileLore-Diagnose.txt` on the Desktop.

**cmd-script lessons (do not relearn):** `%`-arg re-expansion ate `"%1"` (fixed
with `%%%%1`); stray parens in `echo` inside blocks; parse-time `%var%`
expansion inside `if (...)` blocks.

### Selftests (headless verification, all PASS on both RIDs)

```bat
FileLore.exe --selftest <name> <resultFile>
:: names: netpath | search | links | batch | export | templates | pins | hotkeys
:: (bare "--selftest <resultFile> <path> <body> <tagsCsv>" = save round-trip)
:: writes PASS/FAIL lines to resultFile; exit code 0 = pass
:: settings tests snapshot-restore settings.json; hotkeys needs interactive session
```

### Known Mac-parity gaps

Explorer badges · Explorer preview pane / Quick Look integration · inline PDF
in the editor · SmartScreen/code signing · modern Win11 top-level context menu
(M4, via MSIX) · Mac↔Windows template sync (templates are per-device).

---

## 6. Build / test / deploy — macOS

```sh
# tests
cd TetherCore && swift test

# build (Debug or Release)
xcodebuild -project FileLore.xcodeproj -scheme FileLore -configuration Debug \
  -destination 'platform=macOS' build

# deploy a Release build (the user runs the /Applications copy):
xcodebuild -project FileLore.xcodeproj -scheme FileLore -configuration Release \
  -destination 'platform=macOS' build
# then, from the build products directory:
rm -rf /Applications/FileLore.app
cp -R FileLore.app /Applications/FileLore.app
qlmanage -r cache
killall FileLore FileLoreFinderSync 2>/dev/null
open /Applications/FileLore.app
# verify extensions registered:
pluginkit -m | grep -i filelore    # expect: + QuickLook and + FinderSync
```

First launch on a fresh machine: right-click → Open (Gatekeeper bypass for
ad-hoc signature), then enable both extensions in System Settings → Privacy &
Security → Extensions.

---

## 7. Build / deploy — Windows via the Parallels bridge (CRITICAL cheat sheet)

**VM:** "Windows 11" (Parallels, ARM64, Win11 24H2, user `fm`, Parallels Tools
installed, **Secure Boot OFF** — verified `False`; leave it off after a
firmware-mismatch boot failure incident).

**`prlctl exec` rules (each one cost debugging time):**

- Command and args are **separate argv items** — a single quoted combined
  string fails with exit 2.
- Wrap a `cmd /c` payload in bash **single** quotes.
- Commands run as `nt authority\system`, not as user `fm`.
- stdout is sometimes swallowed → redirect to a guest file and `type` it.
- **Never use `timeout`** under prlctl.

```sh
# sanity check (verified working)
prlctl list -a
prlctl exec "Windows 11" cmd /c 'C:\dotnet\dotnet.exe --version'   # 8.0.423
```

**.NET SDK:** 8.0.423 at `C:\dotnet\dotnet.exe` — **not on PATH**, and apphost
exes can't find it → always publish **self-contained**.

**Sync source into the VM** (the `\\Mac\Home` share works as SYSTEM; **never
build on the share** — non-NTFS, breaks ADS assumptions and is slow):

```sh
prlctl exec "Windows 11" cmd /c 'robocopy "\\Mac\Home\Documents\Tether\windows" C:\filelore /MIR /NFL /NDL /NP /XD bin obj'
```

**Build/publish** (win-arm64 for the VM itself; win-x64 for the release —
verify the exe PE machine is 0x8664):

```bat
C:\dotnet\dotnet.exe publish C:\filelore\src\FileLore.App\FileLore.App.csproj ^
  -c Release -r win-arm64 --self-contained true ^
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true
```

**Run a GUI app as the desktop user** (prlctl exec is session-0 SYSTEM; use
Task Scheduler to get an interactive `fm` session). **2026-07-20 gotcha:
schtasks-created tasks NEVER RUN in this VM** — schtasks defaults to
`DisallowStartIfOnBatteries=true` and the VM reports as on-battery (task
queues, instance "launched", action never starts; service restart + VM
reboot don't help). Use the PowerShell ScheduledTasks module with
`-AllowStartIfOnBatteries -DontStopIfGoingOnBatteries` instead — helper:
`.scratch/vm/runas-fm.ps1` (registers an Interactive-principal task as fm
and starts it):

```sh
prlctl exec "Windows 11" powershell -NoProfile -ExecutionPolicy Bypass \
  -File "\\Mac\Home\Documents\Tether\.scratch\vm\runas-fm.ps1" \
  -TaskName T1 -Payload '"C:\path\FileLore.exe"'
```

More in-session helpers in `.scratch/vm/`: `splash-watch.ps1` (window
watcher + screenshots), `search-dump.ps1` (raise window by title + dump its
text via UIA), `edit-and-save.ps1` (UIA tag edit + Save in the editor),
`shot.ps1` (console-hidden screenshot).

**Screenshots:** use the in-session `windows/tools/front-capture.ps1` —
`prlctl capture` shows a stale framebuffer.

**Read an ADS note by hand:** `more < "C:\path\file:filelore.note"`.

**VM quirks:**

- The VM **auto-pauses** ("Pause Windows when possible") after ~1 min idle —
  `prlctl resume "Windows 11"` and run `prlctl exec` in the SAME shell
  command, or it pauses again between calls.
- Parallels Shared Profile makes fm's Documents/Downloads **Mac network
  folders** (non-NTFS → notes unsupported there). Test notes on
  `C:\FileLoreTest` (this is also the Windows app's default search root).
- The VM has **no H.264 decoder** — MediaElement video playback can't be
  verified there; video UI verification needs the user's real Intel PC.

**Deploy to the VM:** `taskkill /f /im FileLore.exe` → copy new exe → relaunch
tray via the schtasks pattern above.

**Release zip:** self-contained win-x64 `FileLore.exe` + `Install-FileLore.cmd`
+ `Uninstall-FileLore.cmd` + `FileLore-Diagnose.cmd` + `README-WINDOWS.txt`
(assets in `windows/dist-assets/`) → `website/public/downloads/FileLore-Windows-x64.zip`
(that directory is gitignored; stale duplicate folders there are Finder junk).

The user tests on the Mac GUI and on a **real Intel Windows PC at work** —
the VM is for build/smoke only.

---

## 8. Website (`website/`)

- Scaffolded with the Kimi Work `webapp-building` skill (0-origin scaffold;
  `template-info.md` records Node 20, Tailwind v3.4.19, Vite v7.2.4, shadcn
  theme with 40+ components). Stock Vite `README.md` is still the template's.
- Sections live in `src/sections/`; all site constants (download URLs + sizes,
  `DONATE_URL` = `https://ko-fi.com/REPLACE_ME` placeholder to replace before
  shipping) live in `src/config.ts`.
- `public/screenshots/` are real captures from the live app;
  `public/filelore-demo.mp4` exists and is embedded by `src/sections/DemoVideo.tsx`
  (a better user-recorded video may replace it — see roadmap).
- `public/downloads/` is gitignored — release zips are dropped there locally.

```sh
cd website
npm run build     # tsc -b && vite build — validates the site
```

**Preview convention (Kimi Work):** never leave a dev server running; end with
a single Markdown link `[FileLore](http://localhost:7100/)` preceded by the
project path as inline code. Don't touch ports 3000/7100 listeners you didn't
start.

---

## 9. Git & workflow

- Repo root = workspace root; single branch `main`; short imperative commit
  messages (e.g. `a7bf586 Fix stray drop-zone windows on Finder open/Services/URL routes`).
- **Current HEAD (verified):** `7a80167 Windows: version visibility, hardened installer, FileLore-Diagnose remote diagnostics` (2026-07-20).
- Recent history (oldest→newest themes): Mac M1 core + extensions → search/batch/
  export → rename Tether→FileLore (`bd101e2`) → badges/menu-bar/pinned-tags →
  media peek + marketing site → drop-zone fix (`a7bf586`) → Windows M1 proof →
  M2 editor/tray → M3 search/hotkeys → netpath guard → x64 release → M5 Mac
  parity (`bbd23d9`) → installer/diagnostics hardening (HEAD).
- Implementation is done by Kimi Work subagents; the user tests by hand
  (Mac GUI + real Intel Windows PC). Keep changes surgical and verified; the
  user is the QA gate.
- Untracked: `.scratch/` (large working area), `tools/__pycache__/` — leave alone.

## 10. Pending roadmap

1. **M4 (Windows):** code signing (SmartScreen), modern Win11 top-level context
   menu via MSIX, slimmer installer.
2. **Public site deploy:** needs hosting account + domain; replace
   `DONATE_URL` ko-fi placeholder in `website/src/config.ts`.
3. **Demo video:** a demo mp4 is already embedded; the user may record a
   final one himself to replace `website/public/filelore-demo.mp4`.
4. Possible: Windows Explorer badges, PDF preview on Windows, Mac↔Windows
   template sync.

---

## 11. Verification notes (what was checked, when this file was written)

| Claim | How verified | Result |
|---|---|---|
| 76 Swift tests | ran `cd TetherCore && swift test` | ✅ 76 passed, 0 failures |
| Bundle IDs, ad-hoc signing, macOS 15 target | grepped `project.pbxproj` | ✅ |
| URL scheme `filelore` | `FileLore/Info.plist` | ✅ |
| xattr names + legacy fallback | `TetherCore/.../NoteStore.swift` | ✅ |
| ADS stream name, IsSupportedPath, FindFirstStreamW | `windows/src/FileLore.Core/*.cs` | ✅ |
| Additive link keys path/size/added | `windows/src/FileLore.Core/Note.cs` | ✅ |
| Windows version 0.6.0 | `AppVersion.cs` + csproj `<Version>` | ✅ |
| Selftest names | `SelfTest.cs` dispatch switch | ✅ |
| Ctrl+Alt+T / Ctrl+Alt+F defaults | `Settings.cs` (`DefaultOpenSelection`/`DefaultSearch`) | ✅ |
| VM "Windows 11" running, dotnet 8.0.423 | `prlctl list` + `prlctl exec … dotnet --version` | ✅ |
| Secure Boot off | `Confirm-SecureBootUEFI` → `False` | ✅ |
| pluginkit state | `pluginkit -m` — FileLore appexes `+`, CleanMyMac5 FinderSync `-` | ✅ |
| HEAD commit | `git log` → `7a80167` | ✅ |

**Corrections made vs the original brief:** (1) `README.md`'s "51 unit tests"
is stale — actual 76. (2) The demo video is not purely pending —
`website/public/filelore-demo.mp4` exists and is already embedded; the roadmap
item is a *replacement* recording. (3) `JSONEncoder` uses no explicit date
strategy — the seconds-since-2001 doubles come from the default
`.deferredToDate`.
