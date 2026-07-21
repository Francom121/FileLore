FileLore for Windows (x64)
==========================
Sticky notes for your files. Notes travel with the file: rename it,
move it to another folder - the note stays attached.

What's in this download
-----------------------
  FileLore.exe            the app (single file, nothing to extract)
  Install-FileLore.cmd    per-user installer - NO admin rights needed
  Uninstall-FileLore.cmd  removes FileLore cleanly
  FileLore-Diagnose.cmd   diagnostics collector - writes a report to
                          your Desktop when something's wrong
  README-WINDOWS.txt      this file

Install (2 minutes)
-------------------
1. Unzip this download somewhere (Downloads is fine).
2. Double-click Install-FileLore.cmd.
3. If Windows SmartScreen pops up ("Windows protected your PC"):
   click "More info", then "Run anyway".
   (The app isn't code-signed yet, so Windows is just being careful.)
4. That's it. FileLore starts in the system tray and comes back
   every time you sign in.

Already installed an older version?
  Just run Install-FileLore.cmd from this new zip - it replaces the
  app, keeps your notes and settings, and you're done. No need to
  uninstall first.

  FIRST LAUNCH can take up to a minute (one-time self-extraction +
  Windows scan). Later launches are fast.

Use it
------
- Right-click any file  ->  "Show more options"  ->  "FileLore Note"
  (on Windows 10 the verb shows directly in the right-click menu)
  Select SEVERAL files and do the same - one batch window opens and
  sets the note body and tags on all of them at once.
- Ctrl+Alt+T  opens a note for the file selected in Explorer
- Ctrl+Alt+F  searches all your notes
- Drop files onto the Desktop shortcut, or onto the drop zone
  (double-click the Desktop shortcut, or tray menu ->
  "New note / batch…"): one file opens its note, several open
  the batch window.

Inside the note editor
----------------------
- Media peek: video/audio plays right beside your note (play, scrub,
  volume); images show aspect-fit; other formats show a large
  thumbnail or icon.
- Linked files: drag files onto the editor (or click "Add files…") to
  attach reference photos, scripts, anything. Click a row to open it;
  click x to remove. If a linked file goes missing you get a red
  "Link broken - relink?" state with a Relink button. (A file moved
  together with the noted file's folder is still found automatically.)
- Templates: pick one from the Templates dropdown to prefill an EMPTY
  note (ships with "AI Generation"; add your own via "Manage
  templates…"). Templates live on this PC only - they don't sync
  from the Mac app.
- Export… saves the note as Markdown, matching the Mac export.

Search window
-------------
- Right-click any tag chip to pin it - pinned tags sit on top with a
  pin glyph and filter with one click.
- Ctrl/Shift-click to multi-select results, then Export… writes ONE
  Markdown document (grouped by tag when the selection spans 2+ tags,
  like the Mac) and reveals it in Explorer.
- Tray menu -> "Pinned Tags" lists noted files per pinned tag.

Make it yours
-------------
- Tray menu -> Settings… rebinds both global hotkeys: click a box,
  press a combo, Save. Conflicts keep the previous binding.
- Tray menu -> "Keyboard Shortcuts…" lists every shortcut (always
  shows your current bindings).

Good to know
------------
- Notes need local NTFS drives (internal or USB disks formatted NTFS).
  Network shares, OneDrive-only placeholders, FAT32/exFAT cards and
  NAS folders can't hold notes - FileLore will tell you politely.
- Notes live inside the file itself (NTFS alternate data streams),
  so there is no database to back up; the files ARE the storage.
- No admin rights are ever needed. Everything installs under
  %LOCALAPPDATA%\FileLore and your own registry hive (HKCU).
- The Windows app doesn't render PDFs inline in the editor (the Mac
  app does) - PDFs show their icon instead.

Uninstall
---------
1. Double-click Uninstall-FileLore.cmd.
2. It stops the app, removes the right-click verb, autostart and
   shortcuts, and deletes the program files.
3. It asks before deleting your tiny settings/recents files - your
   notes live with your files and are never touched.

Troubleshooting
---------------
- "FileLore Note" missing from the right-click menu?
  1. On Windows 11 it's inside "Show more options" first - the verb
     lives in the classic menu.
  2. Restart Explorer so it picks up the new menu entry:
     Ctrl+Shift+Esc -> find "Windows Explorer" -> Restart
     (or just sign out and back in).
  3. Re-run Install-FileLore.cmd and look for [FAIL] lines - it now
     double-checks every registry entry it writes and reports them.
  4. Still stuck? Double-click FileLore-Diagnose.cmd (in this zip, or
     from the download page). It writes FileLore-Diagnose.txt to your
     Desktop and opens it - share that file for help.
- Which version am I running? Look at the bottom of the FileLore tray
  menu (right-click the quill icon) - the version and build date are
  shown just above "Exit". Or run "FileLore.exe --version".
- Hotkeys not working? Make sure the FileLore tray icon is running
  (double-click the Desktop shortcut, or sign out and back in).
- Reinstalling over an old copy is fine: just run Install again - it
  tells you which build it's replacing ("Replacing build from <date>").

https://github.com/fm/filelore  -  thanks for trying FileLore!
