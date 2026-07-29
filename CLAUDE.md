# FileLore — Project Context for AI Assistants

> **This repository is PUBLIC** (github.com/Francom121/FileLore). Everything in
> it — including this file — is visible to anyone. The prlctl/VM cheat-sheet
> (§7) is owner-machine-specific but harmless and useful; keep it.
> **Never commit secrets**: no API keys of any kind (e.g. ElevenLabs-type
> service keys), and never the Sparkle EdDSA **private** key (§6 — it lives in
> the login keychain / `.scratch/sparkle/`, both gitignored).
>
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
| Windows app (C# WPF, .NET 8) | v0.8.0 | `windows/` |
| Marketing site (React+TS+Vite+Tailwind+shadcn) | live at https://filelore.netlify.app | `website/` |

Primary use case: attaching AI-generation prompts, model info, and reference
links to generated media files.

**Where to look for what:**

- Change note storage/format → `TetherCore/Sources/TetherCore/Note.swift` + `NoteStore.swift` (Mac) and `windows/src/FileLore.Core/Note.cs` + `NoteStore.cs` (Windows) — **always change both, additively**.
- macOS app UI/behavior → `FileLore/*.swift` (one file per feature; names are self-describing).
- Windows app UI/behavior → `windows/src/FileLore.App/` (WPF) — core logic in `windows/src/FileLore.Core/`.
- In-repo docs: `README.md` (public front door — both platforms), `windows/README.md` (Windows product + dev doc), `SPEC.md` (original spec), `SHORTCUTS.md` (Mac shortcut cheat sheet), `CONTRIBUTING.md`, `SECURITY.md`.

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
│   └── Tests/TetherCoreTests/      10 test files, 84 tests (XCTest)
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
├── README.md                       public repo front door (features, format, build, both platforms)
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
cd TetherCore && swift test     # 84 tests, 0 failures (verified, XCTest)
```

(The pre-rewrite root `README.md` said "51 unit tests" — long stale; the
public README now states the correct count.)

---

## 5. Windows app (`windows/`, v0.8.0)

- **Two-exe layout (0.7.1):** the shipped `FileLore.exe` is a tiny native
  Win32 **launcher** (`src/FileLore.Launcher/`, ~200 KB, no ATL/MFC, `/MT`
  static CRT, x64+ARM64 via `build-launcher.cmd`, deps kernel32/user32/
  gdi32/shell32 only). It instantly shows a borderless layered "Getting
  FileLore ready…" card (brand cream/orange, GDI comet spinner, fade
  in/out), launches `FileLoreApp.exe` (same folder, args forwarded
  verbatim) **on a worker thread** — Defender's first-scan of the ~180 MB
  app can block CreateProcess for many seconds and must never stall the
  card — then waits: app shows its first visible top-level window
  (EnumWindows by PID) → fade out; app exits windowless (single-instance
  forward) → close; 5-min failsafe. `--tray` = launch + exit immediately;
  `--version`/`-v`/`--selftest` = wait + propagate exit code, no card.
  Since 0.8.0 the launcher is also **Velopack's mainExe**: any
  `--veloapp-*` arg → headless pass-through (wait + propagate exit code),
  so install/update/uninstall hooks run through it while post-install and
  post-update relaunches get the branded card for free.
  Installer: right-click verb + shortcuts → launcher; Run-key autostart →
  `FileLoreApp.exe --tray` DIRECTLY (no card at login). The WPF app is
  `<AssemblyName>FileLoreApp</AssemblyName>` and publishes with
  `<PublishReadyToRun>true</PublishReadyToRun>` in the csproj (cuts JIT
  warmup jank; exe 162 → 178 MB, still single-file).
- `src/FileLore.Core/` — net8.0 library: `Note.cs` (System.Text.Json with the
  additive link keys), `NoteStore.cs` (ADS read/write + `IsSupportedPath`
  friendly guard), `NoteIndex.cs` (`FindFirstStreamW`/`FindNextStreamW` stream
  enumeration for search), `NoteSearch.cs`, `LinkResolver.cs`,
  `MarkdownExporter.cs` (mirrors the Mac exporter's shape).
- `src/FileLore.App/` — WPF `net8.0-windows`, **one NuGet package** (Velopack
  1.2.0 for auto-update — the zero-dependency era ended with 0.8.0), references
  only FileLore.Core otherwise. Self-contained single-file publish. Features: editor with
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
  that precedes any WPF window; the native launcher card covers that gap).
- Version source of truth: `src/FileLore.App/AppVersion.cs` (`Number = "0.8.0"`,
  `BuildDate`) — also bump `<Version>` in `FileLore.App.csproj`, the
  hardcoded string at the top of `tools/Install-FileLore.cmd` (legacy), and the
  VERSIONINFO in `src/FileLore.Launcher/FileLoreLauncher.rc`.
- **Explorer overlay badge (0.7.0):** `src/FileLore.Overlay/` — no-ATL C++
  `IShellIconOverlayIdentifier` DLL (`/MT` static CRT, deps only
  kernel32/ole32/advapi32, x64+ARM64 via `build-overlay.cmd`; CLSID
  `{7F3C1A2E-9B4D-4E5F-A6C7-1D2E3F4A5B6C}` shared with
  `BadgeRegistration.cs`). `IsMemberOf` = native port of
  `NoteIndex.HasNoteStream`. Opt-in from Settings ("Show badges in
  Explorer"): HKLM registration is the app's ONE elevated step
  (`tools/Register-FileLoreOverlay.cmd` via ShellExecute `runas`), key name
  ` FileLore` with ONE leading space (alphabetical priority vs the ~15
  overlay limit, OneDrive convention); `GetPriority` returns 0. Settings
  also shows a read-only slot-position warning when >14 handlers push us
  out. Live refresh (`ShellBadgeRefresh.cs`, hooked to `NoteEvents`):
  `SHCNE_UPDATEITEM` + debounced `Shell.Application` `Refresh()` on open
  Explorer windows showing the noted file's folder — **measured on Win11
  23H2: every SHChangeNotify variant (PATHW/IDLIST/FLUSHNOWAIT/ATTRIBUTES/
  UPDATEDIR/same-path RENAMEITEM) fails to make Explorer re-run IsMemberOf
  for an already-displayed item; only a folder refresh (F5 /
  IWebBrowserApp.Refresh) does.** New badges appear via the folder's
  change-notification revalidation; removals need the Refresh() path.
  Uninstaller offers the elevated unregistration first (Explorer holds the
  DLL mapped until restarted).

### Auto-update (0.8.0, Velopack — MIT license)

- **Layout:** packId `FileLore` → `%LOCALAPPDATA%\FileLore\` (same folder the
  app already used for settings — intentional). `Update.exe` + `current\`
  (launcher `FileLore.exe` = Velopack mainExe, `FileLoreApp.exe`,
  `FileLoreOverlay.dll`, Register/Unregister cmds, `sq.version`) +
  `packages\`. `current\` is a STABLE path across updates → HKCU verb,
  Run-key autostart and HKLM overlay registration never need re-pointing.
- **Hooks** (`VelopackApp.Build()` in the explicit `App.Main`; App.xaml must
  be a **Page**, not an ApplicationDefinition, or the compiler generates a
  duplicate `Main` → CS0111 — setting `<StartupObject>` alone does NOT fix
  it): after install/update `ShellIntegration.Install` (idempotent)
  rewrites the verb + Run key, **rescues `settings.json`/`recents.json`
  from Velopack's rollback dir** (Setup WIPES the install folder on
  install-over-legacy; the hook runs BEFORE the rollback dir is deleted —
  verified in the migration test), cleans legacy 0.7.x flat files; before
  uninstall it removes verb + Run value.
- **Feed (self-hosted static HTTPS, officially supported):**
  `https://filelore.netlify.app/releases/win-x64/` and `.../win-arm64/`,
  each with `releases.win.json` + legacy `RELEASES` +
  `FileLore-x.y.z-full.nupkg` (+ delta nupkgs once a second release exists —
  deltas are plain files, so static hosting suffices). The app picks the
  dir by `RuntimeInformation.ProcessArchitecture`; `FILELORE_UPDATE_URL`
  env var overrides it (testing). Mac feed for comparison:
  `/releases/appcast.xml` (Sparkle).
- **UX (`Updates.cs`):** 6-hour-throttled silent background check on startup
  (state in `update-state.json`, downloads only — Velopack applies on next
  launch), tray balloon when staged, tray menu **Check for Updates…** +
  conditional **Restart to update to X**, branded `UpdateWindow`
  (checking → downloading % → Restart now/Later; up-to-date; offline
  error), Updates section in the Settings window.
  `ApplyUpdatesAndRestart` cleans tray/pipe first.
- **Migration:** 0.7.x zip users download Setup.exe ONE last time; install
  over the legacy folder migrates settings + registration automatically
  (rollback-dir rescue). From there, updates are automatic.
- **Gotchas:** Velopack Setup shows a modal overwrite/repair dialog when
  installing over a non-empty dir (5-min timeout → cancel, exit 0 without
  installing; real users just click Update — tests used `--silent`). vpk
  CLI needs `DOTNET_ROOT` set for its apphost. vpk-created files are
  readable only by SYSTEM/Admins on the VM — `icacls <outdir> /grant
  "BUILTIN\Users":(OI)(CI)RX /T` after every repack.

### Installer (`windows/tools/Install-FileLore.cmd` — LEGACY zip flow)

Per-user, no admin: installs to `%LOCALAPPDATA%\FileLore`, HKCU context-menu
verb, HKCU Run key (tray autostart), Desktop + Start Menu shortcuts.
**Superseded for end users by the Velopack Setup.exe (0.8.0) — kept for
reference and dev installs.** Every
`reg add` is verified with a `reg query` read-back (`[OK]`/`[FAIL]`), upgrades
report OLD vs NEW exe date, and it offers an Explorer restart (`/q` prints a
note instead). `FileLore-Diagnose.cmd` collects field diagnostics (no admin)
into `FileLore-Diagnose.txt` on the Desktop.

**cmd-script lessons (do not relearn):** `%`-arg re-expansion ate `"%1"` (fixed
with `%%%%1`); stray parens in `echo` inside blocks; parse-time `%var%`
expansion inside `if (...)` blocks.

### Selftests (headless verification, all PASS on both RIDs)

```bat
FileLoreApp.exe --selftest <name> <resultFile>
:: names: netpath | search | links | batch | export | templates | pins | hotkeys
:: (bare "--selftest <resultFile> <path> <body> <tagsCsv>" = save round-trip)
:: writes PASS/FAIL lines to resultFile; exit code 0 = pass
:: settings tests snapshot-restore settings.json; hotkeys needs interactive session
:: (0.7.1: run against FileLoreApp.exe; the FileLore.exe launcher forwards
:: --selftest headlessly, but direct is simpler)
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

### Auto-updates (Sparkle 2.x)

The app ships Sparkle 2.9.4 (SPM package `sparkle-project/Sparkle`,
`upToNextMajorVersion` from 2.0.0), linked ONLY into the app target — never
into the QuickLook/FinderSync extensions. The app is NOT sandboxed, so Sparkle
uses its standard integration (no XPC services).

- `SUFeedURL` = `https://filelore.netlify.app/releases/appcast.xml`,
  `SUPublicEDKey` = the EdDSA public key (both in `FileLore/Info.plist`).
- Automatic periodic checks: Sparkle's default (on). Manual check:
  "Check for Updates…" in the FileLore app menu (after About) and in the
  menu-bar dropdown (above Quit). Both wired to
  `FileLore/UpdaterController.swift` (`SPUStandardUpdaterController`).

**Versioning scheme:** app `MARKETING_VERSION` (e.g. 1.1.0) +
`CURRENT_PROJECT_VERSION` (integer build number, e.g. 2), set in the FileLore
target's build settings; `FileLore/Info.plist` reads them via
`$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`. The QuickLook and
FinderSync extensions hardcode the SAME version+build in their own
Info.plists — bump all three together (Xcode warns otherwise). Sparkle
compares `CFBundleVersion` (the integer).

**EdDSA keys:** the private key lives in this Mac's login keychain
("Private key for signing Sparkle updates", created by Sparkle's
`generate_keys`). A backup copy is at `.scratch/sparkle/eddsa-private-key.pem`
(gitignored — NEVER commit it). Losing the private key = existing users can
never update again (signature verification would fail); you'd have to ship a
manually-downloaded release with a new key pair. Note: `sign_update` reading
the key from the keychain triggers a password prompt (the keychain ACL only
trusts the unsigned `generate_keys` binary), so always sign with the key
FILE: `sign_update <zip> .scratch/sparkle/eddsa-private-key.pem`.

**Release runbook (Mac):**

```sh
# 1. Bump version: MARKETING_VERSION + CURRENT_PROJECT_VERSION in the FileLore
#    target build settings (both configs), and the same values hardcoded in
#    FileLoreQuickLook/Info.plist and FileLoreFinderSync/Info.plist.

# 2. Build + deploy the Release build to /Applications (commands above).

# 3. Zip the app (layout: FileLore.app at zip root):
ditto -c -k --sequesterRsrc --keepParent FileLore.app FileLore-macOS.zip

# 4. Sign the zip (Sparkle bin is under
#    ~/Library/Developer/Xcode/DerivedData/FileLore-*/SourcePackages/artifacts/sparkle/Sparkle/bin):
sign_update FileLore-macOS.zip .scratch/sparkle/eddsa-private-key.pem
#    → prints sparkle:edSignature="..." length="..."

# 5. Edit website/public/releases/appcast.xml: add an <item> with the new
#    sparkle:version / sparkle:shortVersionString / edSignature / length.
#    Copy the zip to website/public/releases/FileLore-<version>.zip and to
#    website/public/downloads/FileLore-macOS.zip (front-page download).
#    Update DOWNLOAD_SIZE in website/src/config.ts.

# 6. Rebuild + restage the site zip, owner drags it to Netlify
#    (delete the old zip first — zip update semantics keep stale entries):
cd website && npm run build
rm -f ~/Desktop/FileLore-website.zip
cd dist && zip -qr ~/Desktop/FileLore-website.zip . \
  -x '.DS_Store' '*/.DS_Store'
unzip -l ~/Desktop/FileLore-website.zip | grep -E 'Setup|releases.win.json'  # verify payloads

# 7. Existing apps see the update within 24h (or via Check for Updates…).
```

Local end-to-end test (evidence in `.scratch/sparkle/`): serve a test appcast
with `python3 -m http.server 8123` over a copy of `website/public/releases/`
whose enclosure URL is rewritten to localhost, run an OLD build with
`defaults write com.filelore.app SUFeedURL http://localhost:8123/releases/appcast.xml`,
trigger Check for Updates…, install, confirm the relaunched version, then
`defaults delete com.filelore.app SUFeedURL`.

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
verify the exe PE machine is 0x8664). Produces `FileLoreApp.exe`
(R2R comes from the csproj since 0.7.1); build the native launcher
(`FileLore.exe`) separately with `src\FileLore.Launcher\build-launcher.cmd`:

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
- **The display sleeps on battery (~5 min) and the GDI framebuffer FREEZES**
  — in-session screenshots (`CopyFromScreen`) then return the last frame
  forever (byte-identical PNGs look like "nothing happened"). Fix once:
  `powercfg /change monitor-timeout-dc 0` (+`-ac 0`); wake before captures
  by jiggling the cursor (`SetCursorPos` loop). Telltale: two screenshots
  with identical sha256.
- **`robocopy /MIR` re-syncs wipe `out\` build dirs** (the Mac side has
  none) — either rebuild after each sync or add `/XD bin obj out`.
- `runas-fm.ps1 -Payload` chokes on payloads containing spaces through
  prlctl argv — point it at a `.cmd` on the share whose path has no spaces.
- VS Build Tools 2022 (MSVC 14.44, x64+ARM64, Win11 SDK 10.0.22621) are
  now installed at `C:\Program Files (x86)\Microsoft Visual Studio\2022\
  BuildTools` (installed via `vs_BuildTools.exe --quiet --wait`; the VM
  has no winget).

**Deploy to the VM:** `taskkill /f /im FileLoreApp.exe` + `taskkill /f /im
FileLore.exe` → copy new exes → relaunch tray via the schtasks pattern above.

**Release (0.8.0 Velopack flow):** publish per RID (`win-x64` + `win-arm64`),
copy launcher + `FileLoreOverlay.dll` + Register/Unregister cmds into the
pack dir, then `vpk pack` per RID (vpk 1.2.0 at `C:\vpk\vpk.exe`, **prefix
`set DOTNET_ROOT=C:\dotnet&`** or its apphost can't find the runtime):

```bat
set DOTNET_ROOT=C:\dotnet& C:\vpk\vpk.exe pack -u FileLore -v 0.8.0 ^
  -p C:\velopack\pack-x64 -e FileLore.exe -o C:\velopack\feed\win-x64 ^
  -r win-x64 --packTitle FileLore --packAuthors FileLore ^
  --icon C:\filelore\src\FileLore.App\app.ico ^
  --splashImage C:\filelore\src\FileLore.App\Resources\icon-256.png --yes
```

Ship `releases.win.json` + `RELEASES` + nupkg(s) →
`website/public/releases/win-<rid>/` (gitignored) and
`FileLore-win-Setup.exe` → `website/public/downloads/FileLore-Windows-Setup-<arch>.exe`;
update sizes in `website/src/config.ts`, rebuild the site, restage the
deploy zip (**delete ~/Desktop/FileLore-website.zip before re-zipping —
zip update semantics keep stale entries**). Verify with `unzip -l` that the
Setup + feeds are inside and the retired `FileLore-Windows-x64.zip` is not.

**Local update-feed testing:** serve `C:\velopack\feed` over HTTP as fm —
one-time `netsh http add urlacl url=http://+:8123/ user=fm`, then
`.scratch/vm/httpserve.ps1` (HttpListener, streams files, logs requests +
errors) via `feed.cmd` through runas-fm; point the app at it with
`FILELORE_UPDATE_URL=http://localhost:8123/win-arm64` and delete
`update-state.json` to beat the 6h throttle. After ANY repack:
`icacls C:\velopack\feed /grant "BUILTIN\Users":(OI)(CI)RX /T` — vpk output
is SYSTEM-only and the feed server 500s on the nupkg otherwise (the generic
HttpListener catch masked this as a bare 500 until exceptions were logged).
Tray-menu/UpdateWindow automation helpers: `.scratch/vm/tray-click.ps1`
(UIA: overflow = `TopLevelWindowForOverflowXamlIsland`, right-click via
`SetCursorPos`+`mouse_event` at BoundingRectangle center —
GetClickablePoint throws on Win11 tray buttons; WPF ContextMenu items are
desktop-descendant MenuItems, NOT `#32768`), `shot-updates-window.ps1`
(minimize Terminal windows + foreground target + capture).

The user tests on the Mac GUI and on a **real Intel Windows PC at work** —
the VM is for build/smoke only.

---

## 8. Website (`website/`)

- Scaffolded with the Kimi Work `webapp-building` skill (0-origin scaffold;
  `template-info.md` records Node 20, Tailwind v3.4.19, Vite v7.2.4, shadcn
  theme with 40+ components). Stock Vite `README.md` is still the template's.
- Sections live in `src/sections/`; all site constants (download URLs + sizes,
  `DONATE_URL` = `https://ko-fi.com/filelore`) live in `src/config.ts`.
- `public/screenshots/` are real captures from the live app;
  `public/filelore-demo.mp4` exists and is embedded by `src/sections/DemoVideo.tsx`
  (a better user-recorded video may replace it — see roadmap).
- `public/downloads/` and `public/releases/win-x64|win-arm64/` are
  gitignored — release artifacts (macOS zip + appcast, Windows Setup exes,
  Velopack feeds) are dropped there locally.

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
- **Current HEAD (verified):** `f446a85 Docs: Velopack architecture, release runbook, VM feed-testing cheat sheet` (2026-07-28).
- Recent history (oldest→newest themes): Mac M1 core + extensions → search/batch/
  export → rename Tether→FileLore (`bd101e2`) → badges/menu-bar/pinned-tags →
  media peek + marketing site → drop-zone fix (`a7bf586`) → Windows M1 proof →
  M2 editor/tray → M3 search/hotkeys → netpath guard → x64 release → M5 Mac
  parity (`bbd23d9`) → installer/diagnostics hardening → Windows 0.8.0 Velopack
  auto-update + Setup distribution (`f446a85` series).
- Implementation is done by Kimi Work subagents; the user tests by hand
  (Mac GUI + real Intel Windows PC). Keep changes surgical and verified; the
  user is the QA gate.
- Untracked: `.scratch/` (large working area), `tools/__pycache__/` — leave alone.

## 10. Pending roadmap

1. **M4 (Windows):** code signing (SmartScreen), modern Win11 top-level context
   menu via MSIX, slimmer installer.
2. **Public site deploy: DONE** — live at https://filelore.netlify.app
   (owner drags the built zip to Netlify; see §6 runbook). The ko-fi URL in
   `website/src/config.ts` is set to `https://ko-fi.com/filelore`.
3. **Demo video:** a demo mp4 is already embedded; the user may record a
   final one himself to replace `website/public/filelore-demo.mp4`.
4. Possible: Windows Explorer badges, PDF preview on Windows, Mac↔Windows
   template sync.

---

## 11. Verification notes (what was checked, when this file was written)

| Claim | How verified | Result |
|---|---|---|
| 84 Swift tests (XCTest, 10 files) | ran `cd TetherCore && swift test` | ✅ 84 passed, 0 failures |
| Bundle IDs, ad-hoc signing, macOS 15 target | grepped `project.pbxproj` | ✅ |
| URL scheme `filelore` | `FileLore/Info.plist` | ✅ |
| xattr names + legacy fallback | `TetherCore/.../NoteStore.swift` | ✅ |
| ADS stream name, IsSupportedPath, FindFirstStreamW | `windows/src/FileLore.Core/*.cs` | ✅ |
| Additive link keys path/size/added | `windows/src/FileLore.Core/Note.cs` | ✅ |
| Windows version 0.8.0 | `AppVersion.cs` + csproj `<Version>` + launcher RC | ✅ |
| Velopack 0.8.0→0.8.1 rehearsal (VM, local feed) | app.log: `0.8.1 available` → `downloaded` → `velo restarted after update: 0.8.1`; `--version` → 0.8.1; uninstall entry DisplayVersion 0.8.1 | ✅ |
| Verb/Run-key/overlay/settings survive update | `query-fm-reg.ps1` (verb + Run → stable `current\`), dir listing, settings.json pinnedTags intact | ✅ |
| Legacy 0.7.1 zip → Velopack migration | app.log `migration: restored settings.json/recents.json from rollback dir` + registry re-checks | ✅ |
| No-update + offline update paths | screenshots `update-uptodate.png` / `update-offline.png`; app.log graceful `HttpRequestException` lines | ✅ |
| Note content loads after update | editor on noted `plain.txt` shows `plain refresh test` (`note-editor2.png`) | ✅ |
| Delta package generation | `FileLore-0.8.1-delta.nupkg` 163 KB vs 69 MB full | ✅ (local HTTP fetch used full; delta exercised by generation + Velopack selection logic) |
| x64/arm64 PE machine types | `pe-machine.ps1`: x64 pack all 0x8664, arm64 all 0xAA64 | ✅ |
| Website deploy zip contents | `unzip -l`: both Setup exes + both `releases/win-*` feeds, no stale `FileLore-Windows-x64.zip`, no `.DS_Store` | ✅ |
| Selftest names | `SelfTest.cs` dispatch switch | ✅ |
| Ctrl+Alt+T / Ctrl+Alt+F defaults | `Settings.cs` (`DefaultOpenSelection`/`DefaultSearch`) | ✅ |
| VM "Windows 11" running, dotnet 8.0.423 | `prlctl list` + `prlctl exec … dotnet --version` | ✅ |
| Secure Boot off | `Confirm-SecureBootUEFI` → `False` | ✅ |
| pluginkit state | `pluginkit -m` — FileLore appexes `+`, CleanMyMac5 FinderSync `-` | ✅ |
| HEAD commit | `git log` → `f446a85` | ✅ |

**Corrections made vs earlier versions of this file:** (1) test counts were
repeatedly stale — the verified count is now **84 tests (XCTest, 10 files)**;
the old root `README.md`'s "51 unit tests" is gone with the public rewrite.
(2) The demo video is not purely pending —
`website/public/filelore-demo.mp4` exists and is already embedded; the roadmap
item is a *replacement* recording. (3) `JSONEncoder` uses no explicit date
strategy — the seconds-since-2001 doubles come from the default
`.deferredToDate`. (4) The marketing site is deployed, not pending.
