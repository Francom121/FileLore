# Contributing to FileLore

Thanks for your interest! FileLore is a small two-platform project maintained
by one person — friendly, low-ceremony contributions are very welcome.

## Reporting bugs

Open an issue using the **bug report** template. The most helpful things to
include:

- **Platform** (macOS or Windows) and OS version
- **App version** (Mac: FileLore menu → About; Windows: tray menu — the
  version is shown above Exit, or run `FileLoreApp.exe --version`)
- **Where the file lives** — local drive, external/USB drive, iCloud, network
  share. Notes depend on filesystem metadata (xattr on macOS, NTFS ADS on
  Windows), so a lot of edge cases only happen on specific volume types.
- On **Windows**, you can attach the diagnostics bundle: run
  `FileLore-Diagnose.cmd` (no admin needed) — it writes
  `FileLore-Diagnose.txt` to your Desktop.
- Steps to reproduce, what you expected, what actually happened.

## Suggesting features

Use the **feature request** template. One idea per issue keeps things
actionable.

## Setting up a dev environment

See the **Build from source** section of the [README](README.md):

- **macOS:** Xcode, folder-synced project — open `FileLore.xcodeproj` and
  build. Run `cd TetherCore && swift test` before touching core logic.
- **Windows:** .NET 8 SDK, `dotnet publish` from `windows/`; MSVC Build Tools
  only if you're working on the native launcher or Explorer overlay.

## The one hard rule

**The note JSON format is cross-platform-sacred.** The macOS app
(`TetherCore/Sources/TetherCore/Note.swift`) and the Windows app
(`windows/src/FileLore.Core/Note.cs`) read each other's notes byte-for-byte.
That only works if format changes are:

- **additive only** — you may add new keys; never rename, remove, or change
  the type of an existing key
- **coordinated across both apps** — if a change affects the format, both
  implementations must handle it (adding a key that one platform writes and
  the other ignores is fine; that's exactly how the Windows `path`/`size`/
  `added` link keys work)

If you're unsure whether your idea touches the format, ask in an issue first.

## Code style (light-touch)

- **Swift:** core logic belongs in `TetherCore`, not the app target — and
  changes there need tests (`swift test`, currently 84 tests, must stay
  green). Keep files one-feature-per-file like the existing layout.
- **C#:** match the existing patterns — the app has zero NuGet dependencies
  and we'd like to keep it that way; core logic lives in `FileLore.Core`.
- **Commits:** short, imperative summaries like the existing history
  (e.g. `Fix stray drop-zone windows on Finder open/Services/URL routes`).

## A note on secrets

Never commit API keys or signing material. The Sparkle EdDSA **private** key
and any third-party API keys must stay out of the repo — the public keys in
the repo are fine.

Thanks again — every bug report and PR makes FileLore better. 🪶
