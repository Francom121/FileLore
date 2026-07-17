# Tether — Mac File Sticky Notes App — Project Spec

**Tagline:** Notes that stay tethered to your files — through renames, moves, and everything else.

## Overview

A macOS app that lets you attach a "sticky note" to any file (videos, photos, documents, etc.) without needing a separate database. The note travels with the file — surviving renames and folder moves on the same drive — and can be viewed instantly via Quick Look (spacebar) or a Finder badge.

Primary use case: attaching AI generation prompts, model info, and reference links directly to output files (e.g. a generated video clip) so the creative process is never disconnected from the result.

## Core Architecture

### Where notes live

- Notes are stored as a custom extended attribute on the file itself (e.g. `com.username.stickynote`), the same underlying mechanism macOS uses for Finder Comments.
- This means notes are NOT stored in a separate database/file — they live on the file's own metadata, so they survive renames and moves as long as the file stays on the same drive/volume.

### Linked files (photos, reference images, etc.)

- Notes can link to other local files (e.g. a reference photo sitting in the same folder as a generated video).
- These links use security-scoped bookmarks (not plain file paths), so they resolve based on the file's identity on the volume rather than a literal path string.
- Survives: renaming the linked file, renaming/moving its folder, moving it to a different folder — as long as it stays on the same drive.
- Breaks: moving to a different drive/volume, deleting and recreating a file with the same name, some iCloud Drive sync edge cases.
- Broken link handling: if a linked file can't be resolved, show "Link broken — relink?" in the note UI instead of failing silently, with a simple relink flow (pick the file again).

## Core Features

1. **Creating a note** — Small app icon (Dock or menu bar) — drag a file onto it to attach a note. Popup window with a text field for the note. Save writes the note as an extended attribute on the file.
2. **Editing a note** — Same popup, but pre-filled with existing note content if one already exists. Save overwrites the existing extended attribute.
3. **Viewing a note** — Quick Look extension: press spacebar on the file in Finder → note appears as an overlay in the standard Quick Look preview. Finder Sync extension (badge): files with an attached note show a small badge icon in Finder, so annotated files are visible at a glance without opening anything.
4. **Links in notes** — Web links: plain text URLs auto-detected and made clickable in both the popup and Quick Look view. Local file links: drag a file (e.g. a reference photo) directly into the note popup to attach it as a linked item, shown as a thumbnail rather than a generic link icon. Single click on thumbnail → Quick Look preview. Double click → open in default app (e.g. Preview). No limit on number of linked files per note.
5. **Search** — A Spotlight-style search window to find notes by content (e.g. "which file did I use this prompt in?") across all tagged/known files.
6. **Tags / categories** — Add a tag field to notes (e.g. project/channel name) to filter and group related files. Useful for organizing across multiple concurrent projects.
7. **Note templates** — A "use template" option that pre-fills the note body with a reusable structure (Prompt / Model / Voice / Links). Should support saving/editing custom templates, not just one default.
8. **Quick copy** — One-click button to copy just the note's prompt/text content to clipboard, for quickly reusing a prompt in another tool (e.g. Runway, Seedance, Suno).
9. **Batch tagging / batch notes** — Select multiple files at once and apply the same tag (or same note) to all of them in one action.
10. **Menu bar quick access** — Menu bar dropdown showing recently-noted files, so notes can be glanced at without navigating back to the file in Finder.
11. **Export** — Export a single note (text + links) as a Markdown file — useful for pasting a prompt/process into show notes or a script doc.

## Technical Notes

Built in Swift/Xcode (not a simple Automator script) because:

- Finder Sync Extension (for badges) requires it.
- Quick Look Extension (for preview overlay) requires it.

Distribution:

- Personal use: no signing needed, right-click → Open once to bypass Gatekeeper.
- Sharing with a few people: same one-time Gatekeeper warning, acceptable for casual sharing.
- Wider distribution: requires an Apple Developer account ($99/year) to sign and notarize.
- Regardless of signing, Finder Sync and Quick Look extensions require a one-time manual approval in System Settings → Privacy & Security → Extensions.

## Suggested Build Order

1. Core read/write/edit engine for notes (extended attributes).
2. Drag-and-drop popup app for creating/editing notes (text only).
3. Security-scoped bookmark logic for linking local files (photos, etc.) + broken link/relink handling.
4. Web link auto-detection in note text.
5. Quick Look extension (note overlay on spacebar preview).
6. Finder Sync extension (badge icon on noted files).
7. Tags/categories + search.
8. Templates + quick copy.
9. Batch tagging.
10. Menu bar quick-access panel.
11. Markdown export.
