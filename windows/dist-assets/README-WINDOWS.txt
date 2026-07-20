FileLore for Windows (x64)
==========================
Sticky notes for your files. Notes travel with the file: rename it,
move it to another folder - the note stays attached.

What's in this download
-----------------------
  FileLore.exe            the app (single file, nothing to extract)
  Install-FileLore.cmd    per-user installer - NO admin rights needed
  Uninstall-FileLore.cmd  removes FileLore cleanly
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

Use it
------
- Right-click any file  ->  "Show more options"  ->  "FileLore Note"
  (on Windows 10 the verb shows directly in the right-click menu)
- Ctrl+Alt+T  opens a note for the file selected in Explorer
- Ctrl+Alt+F  searches all your notes
- Desktop and Start Menu shortcuts are created too.

Good to know
------------
- Notes need local NTFS drives (internal or USB disks formatted NTFS).
  Network shares, OneDrive-only placeholders, FAT32/exFAT cards and
  NAS folders can't hold notes - FileLore will tell you politely.
- Notes live inside the file itself (NTFS alternate data streams),
  so there is no database to back up; the files ARE the storage.
- No admin rights are ever needed. Everything installs under
  %LOCALAPPDATA%\FileLore and your own registry hive (HKCU).

Uninstall
---------
1. Double-click Uninstall-FileLore.cmd.
2. It stops the app, removes the right-click verb, autostart and
   shortcuts, and deletes the program files.
3. It asks before deleting your tiny settings/recents files - your
   notes live with your files and are never touched.

Troubleshooting
---------------
- "FileLore Note" missing from the menu? On Windows 11 click
  "Show more options" first - the verb lives in the classic menu.
- Hotkeys not working? Make sure the FileLore tray icon is running
  (double-click the Desktop shortcut, or sign out and back in).
- Reinstalling over an old copy is fine: just run Install again.

https://github.com/fm/filelore  -  thanks for trying FileLore!
