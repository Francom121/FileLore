using System.IO;
using FileLore.Core;

namespace FileLore.App;

/// <summary>
/// Headless verification hooks that drive the exact same code paths as the
/// UI, so milestone verification can prove behavior end-to-end without UI
/// automation.
///
/// Usage:
///   FileLore.exe --selftest &lt;resultFile&gt; &lt;targetPath&gt; &lt;body&gt; &lt;tagsCsv&gt;
///     — save-path round-trip (same path as the editor's Save button).
///   FileLore.exe --selftest search &lt;resultFile&gt;
///     — builds a fixture tree under C:\FileLoreTest\sidx, then exercises
///     NoteIndex.Scan and NoteSearch.Matches exactly as the search window
///     does (enumeration, skips, text search, tag-chip filters).
///   FileLore.exe --selftest netpath &lt;resultFile&gt;
///     — exercises the unsupported-location guard: a UNC path
///     (\\Mac\Home\Downloads, reachable from the VM via Parallels Shared
///     Folders) must be detected as unsupported, fail saves with the
///     friendly message (never the raw ADS path), and be skipped as a
///     search root; a normal NTFS path must stay supported and writable.
///   FileLore.exe --selftest links &lt;resultFile&gt;
///     — linked files: write note with 2 links → read back; linked file
///     moved into the noted file's folder → same-folder fallback resolves;
///     deleted name → broken state; Relink rebinds the path.
///   FileLore.exe --selftest batch &lt;resultFile&gt;
///     — BatchNoteService over 3 NTFS files + 1 UNC file: body Set /
///     Append, tags Add / Replace, unsupported skipped with reason.
///   FileLore.exe --selftest export &lt;resultFile&gt;
///     — golden-compare per-note and batch Markdown exports (headers, tag
///     grouping, linked-files block, Noted line); prints both outputs.
///   FileLore.exe --selftest templates|pins|hotkeys &lt;resultFile&gt;
///     — settings round-trips: template CRUD, pinned tags, hotkey rebind
///     (persisted; old combo unregistered — see app.log evidence).
///
/// Writes human-readable PASS/FAIL lines to &lt;resultFile&gt; (the app is a
/// GUI-subsystem binary, so console output is not reliable). Exit code 0 =
/// all checks passed. Tests that mutate settings.json snapshot and restore
/// it, so a selftest run never disturbs the real app settings.
/// </summary>
internal static class SelfTest
{
    private static bool ApproxEq(DateTime a, DateTime b) => Math.Abs((a - b).TotalMilliseconds) < 1.0;

    public static int Run(string[] args)
    {
        if (args.Length >= 3)
        {
            switch (args[1])
            {
                case "search": return RunSearch(args[2]);
                case "netpath": return RunNetPath(args[2]);
                case "links": return RunLinks(args[2]);
                case "batch": return RunBatch(args[2]);
                case "export": return RunExport(args[2]);
                case "templates": return RunTemplates(args[2]);
                case "pins": return RunPins(args[2]);
                case "hotkeys": return RunHotkeys(args[2]);
            }
        }
        return RunSavePath(args);
    }

    // ======================= shared harness =======================

    /// <summary>Collects PASS/FAIL lines and writes the result file.</summary>
    private sealed class CheckRun
    {
        private readonly List<string> _lines = new();
        private int _failures;

        public void Pass(string s) => _lines.Add("PASS: " + s);
        public void Fail(string s) { _lines.Add("FAIL: " + s); _failures++; }
        public void Info(string s) => _lines.Add(s);

        public int Finish(string resultFile)
        {
            _lines.Add(_failures == 0 ? "SELFTEST PASSED" : $"SELFTEST FAILED ({_failures} failing check(s))");
            try { File.WriteAllLines(resultFile, _lines); }
            catch { /* GUI-subsystem app: if the result file is unwritable there is nowhere to report */ }
            return _failures == 0 ? 0 : 1;
        }
    }

    /// <summary>Snapshots settings.json and restores it on Dispose.</summary>
    private sealed class SettingsBackup : IDisposable
    {
        private readonly string? _original;

        public SettingsBackup()
        {
            try { _original = File.Exists(Settings.StoragePath) ? File.ReadAllText(Settings.StoragePath) : null; }
            catch { _original = null; }
        }

        public void Dispose()
        {
            try
            {
                if (_original is null)
                {
                    if (File.Exists(Settings.StoragePath)) File.Delete(Settings.StoragePath);
                }
                else
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(Settings.StoragePath)!);
                    File.WriteAllText(Settings.StoragePath, _original);
                }
            }
            catch { /* best effort restore */ }
        }
    }

    // ======================= links =======================

    /// <summary>
    /// Linked files: 2 links written → read back; one linked file moved into
    /// the noted file's folder → same-folder fallback; a link at a deleted
    /// name → broken; Relink rebinds; body/tag saves preserve links.
    /// </summary>
    private static int RunLinks(string resultFile)
    {
        var r = new CheckRun();
        string root = @"C:\FileLoreTest\st-links";
        string away = @"C:\FileLoreTest\st-links-away";
        string noted = Path.Combine(root, "clip.mp4");
        string refA = Path.Combine(root, "refA.png");
        string refBAway = Path.Combine(away, "refB.png");
        string refBLocal = Path.Combine(root, "refB.png");

        try
        {
            foreach (string dir in new[] { root, away })
            {
                if (Directory.Exists(dir)) Directory.Delete(dir, recursive: true);
                Directory.CreateDirectory(dir);
            }
            File.WriteAllBytes(noted, new byte[] { 1, 2, 3 });
            File.WriteAllBytes(refA, new byte[] { 4, 5, 6 });
            File.WriteAllBytes(refBAway, new byte[] { 7, 8, 9 });

            // 1) write a note with 2 links → read back
            var note = new Note { Body = "link test", Tags = new List<string> { "lt" } };
            note.Links.Add(LinkResolver.CreateLink(refA));
            note.Links.Add(LinkResolver.CreateLink(refBAway));
            NoteStore.Write(noted, note);

            var read = NoteStore.Read(noted);
            if (read is not null && read.Links.Count == 2
                && read.Links.All(l => l.Id != Guid.Empty && l.Path is not null && l.Size > 0))
            {
                r.Pass("note written with 2 links reads back (id/path/size present)");
            }
            else r.Fail("link read-back broken");

            if (read is not null && read.Links[0].Path == refA && read.Links[0].DisplayName == "refA.png"
                && read.Links[0].RelativePathHint == "refA.png" && read.Links[0].Bookmark.Length == 0)
                r.Pass("link record fields: path, displayName, relativePathHint, empty bookmark placeholder");
            else r.Fail("link record fields wrong");

            // 2) both resolve via their absolute path
            if (read is not null
                && LinkResolver.Resolve(read.Links[0], noted) == refA
                && LinkResolver.Resolve(read.Links[1], noted) == refBAway)
                r.Pass("both links resolve via their absolute path");
            else r.Fail("direct-path resolution broken");

            // 3) refB moves into the noted file's folder (the main real-world
            //    case: reference photo moved together with the video's folder)
            //    → stale absolute path, same-folder fallback resolves.
            File.Move(refBAway, refBLocal);
            Directory.Delete(away);
            if (read is not null && LinkResolver.Resolve(read.Links[1], noted) == refBLocal)
                r.Pass("moved-together link resolves via same-folder fallback (displayName)");
            else r.Fail("same-folder fallback broken");

            // 4) a link whose target is gone everywhere → broken state
            string gone = Path.Combine(root, "gone.png");
            File.WriteAllBytes(gone, new byte[] { 1 });
            var broken = LinkResolver.CreateLink(gone);
            File.Delete(gone);
            if (LinkResolver.Resolve(broken, noted) is null)
                r.Pass("deleted target reports broken state");
            else r.Fail("broken state not detected");

            // 5) Relink rebinds path + display name, keeps the id
            Guid idBefore = broken.Id;
            LinkResolver.Relink(broken, refA);
            if (broken.Id == idBefore && LinkResolver.Resolve(broken, noted) == refA
                && broken.DisplayName == "refA.png")
                r.Pass("Relink rebinds path (id stable, name refreshed)");
            else r.Fail("Relink did not rebind");

            // 6) body/tag saves never drop links
            NoteEditorService.Save(noted, "body edit", new[] { "t1" });
            var after = NoteStore.Read(noted);
            if (after is not null && after.Links.Count == 2 && after.Body == "body edit")
                r.Pass("body/tags save preserves links");
            else r.Fail("save dropped links");
        }
        catch (Exception ex)
        {
            r.Fail("exception: " + ex);
        }
        finally
        {
            try { if (Directory.Exists(root)) Directory.Delete(root, recursive: true); } catch { }
            try { if (Directory.Exists(away)) Directory.Delete(away, recursive: true); } catch { }
        }
        return r.Finish(resultFile);
    }

    // ======================= batch =======================

    /// <summary>
    /// Batch notes/tags over 3 NTFS files + 1 UNC file: Set + Add applies to
    /// all three; Append adds without clobbering; Replace swaps tags; the
    /// UNC file is skipped with the network reason; empty inputs are no-ops.
    /// </summary>
    private static int RunBatch(string resultFile)
    {
        var r = new CheckRun();
        string root = @"C:\FileLoreTest\st-batch";
        const string unc = @"\\Mac\Home\Downloads\__fl_batch.tmp";
        var files = new[] { "b1.mp4", "b2.mp4", "b3.mp4" }.Select(f => Path.Combine(root, f)).ToArray();

        try
        {
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
            Directory.CreateDirectory(root);
            foreach (string f in files) File.WriteAllBytes(f, new byte[] { 1 });
            File.WriteAllText(unc, "batch selftest fixture");

            // 1) body Set + tags Add across all 3; UNC skipped with reason
            var results = BatchNoteService.Apply(
                files.Concat(new[] { unc }).ToArray(),
                "hello batch", BatchBodyMode.Set, new[] { "btag" }, BatchTagMode.Add);
            if (results.Count(x => x.Succeeded) == 3)
                r.Pass("3 files updated");
            else r.Fail($"expected 3 successes, got {results.Count(x => x.Succeeded)}");

            var uncResult = results.Last();
            if (uncResult.Skipped && uncResult.Reason is not null
                && uncResult.Reason.Contains("network or shared folder", StringComparison.OrdinalIgnoreCase))
                r.Pass($"unsupported 4th (UNC) skipped with reason: \"{uncResult.Reason}\"");
            else r.Fail("UNC file not skipped with reason");

            bool allCarry = files.All(f =>
            {
                var n = NoteStore.Read(f);
                return n is not null && n.Body == "hello batch" && n.Tags.Contains("btag");
            });
            if (allCarry) r.Pass("all 3 carry body + tag after Set/Add");
            else r.Fail("Set/Add did not reach all files");

            // 2) Append adds without clobbering
            BatchNoteService.Apply(files, "more", BatchBodyMode.Append,
                Array.Empty<string>(), BatchTagMode.Add);
            bool appended = files.All(f => NoteStore.Read(f)?.Body == "hello batch\n\nmore");
            if (appended) r.Pass("Append adds without clobbering (blank-line separated)");
            else r.Fail("Append clobbered or malformed bodies");

            // 3) tags Replace swaps the set
            BatchNoteService.Apply(files, null, BatchBodyMode.Set,
                new[] { "x1", "x2" }, BatchTagMode.Replace);
            bool replaced = files.All(f =>
            {
                var n = NoteStore.Read(f);
                return n is not null && n.Tags.SequenceEqual(new[] { "x1", "x2" })
                    && n.Body == "hello batch\n\nmore";
            });
            if (replaced) r.Pass("Replace swaps tags; null body leaves bodies untouched");
            else r.Fail("Replace or body-guard misbehaved");

            // 4) empty inputs are no-ops (Set can never wipe a blank field)
            BatchNoteService.Apply(files, "", BatchBodyMode.Set,
                Array.Empty<string>(), BatchTagMode.Replace);
            bool untouched = files.All(f =>
            {
                var n = NoteStore.Read(f);
                return n is not null && n.Body == "hello batch\n\nmore" && n.Tags.Count == 2;
            });
            if (untouched) r.Pass("empty body/tags inputs leave notes untouched");
            else r.Fail("empty-input guard failed");

            // 5) summary line shape
            string summary = BatchNoteService.Summarize(results);
            if (summary.Contains("3 notes updated") && summary.Contains("1 skipped"))
                r.Pass($"summary line: \"{summary}\"");
            else r.Fail($"unexpected summary: \"{summary}\"");
        }
        catch (Exception ex)
        {
            r.Fail("exception: " + ex);
        }
        finally
        {
            try { if (Directory.Exists(root)) Directory.Delete(root, recursive: true); } catch { }
            try { File.Delete(unc); } catch { /* share unreachable etc. */ }
        }
        return r.Finish(resultFile);
    }

    // ======================= export =======================

    /// <summary>
    /// Golden-compare the per-note and batch Markdown exports. The expected
    /// documents are hand-built here; only the volatile export-date stamp
    /// comes from the exporter itself. Both outputs are printed verbatim.
    /// </summary>
    private static int RunExport(string resultFile)
    {
        var r = new CheckRun();
        string root = @"C:\FileLoreTest\st-export";
        string clipA = Path.Combine(root, "clipA.mp4");
        string clipB = Path.Combine(root, "clipB.mp4");
        string plain = Path.Combine(root, "plain.txt");
        string refPng = Path.Combine(root, "ref.png");
        var noted = new DateTime(2025, 1, 15, 12, 0, 0, DateTimeKind.Local); // → "Jan 15, 2025"

        try
        {
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
            Directory.CreateDirectory(root);
            foreach (string f in new[] { clipA, clipB, plain, refPng }) File.WriteAllBytes(f, new byte[] { 1 });

            var noteA = new Note
            {
                Body = "Prompt: a red panda",
                Tags = new List<string> { "prompt", "video" },
                Created = noted,
            };
            noteA.Links.Add(LinkResolver.CreateLink(refPng));
            NoteStore.Write(clipA, noteA);
            var noteB = new Note { Body = "second clip", Tags = new List<string> { "video" }, Created = noted };
            NoteStore.Write(clipB, noteB);
            var notePlain = new Note { Body = "no tags here", Created = noted };
            NoteStore.Write(plain, notePlain);

            // ---------- per-note export: golden compare ----------
            string expectedSingle =
                $"# clipA.mp4\n**File:** {clipA}\n**Tags:** #prompt #video" +
                "\n\nPrompt: a red panda" +
                $"\n\n**Linked files:**\n- ref.png — {refPng}" +
                "\n\n*Noted Jan 15, 2025*\n";
            string actualSingle = MarkdownExporter.Markdown(noteA, "clipA.mp4", clipA);
            r.Info("---- per-note export ----");
            r.Info(actualSingle);
            if (actualSingle == expectedSingle)
                r.Pass("per-note export matches golden (header, File, Tags, body, links, Noted)");
            else
                r.Fail("per-note export mismatch:\nEXPECTED:\n" + expectedSingle + "\nACTUAL:\n" + actualSingle);

            // broken link renders "(broken link)"
            var noteBroken = new Note { Created = noted };
            var gone = LinkResolver.CreateLink(Path.Combine(root, "gone.png"));
            File.Delete(Path.Combine(root, "gone.png"));
            noteBroken.Links.Add(gone);
            string brokenOut = MarkdownExporter.Markdown(noteBroken, "x.mp4", clipA);
            if (brokenOut.Contains("- gone.png (broken link)"))
                r.Pass("broken link renders \"(broken link)\"");
            else r.Fail("broken-link rendering wrong:\n" + brokenOut);

            // ---------- batch export: grouped (≥2 tags) ----------
            var items = new List<MarkdownExporter.ExportItem>
            {
                new(noteA, "clipA.mp4", clipA),
                new(noteB, "clipB.mp4", clipB),
                new(notePlain, "plain.txt", plain),
            };
            string stamp = MarkdownExporter.ExportDateString();
            string entryA =
                $"### clipA.mp4\n**File:** {clipA}\n**Tags:** #prompt #video" +
                "\n\nPrompt: a red panda" +
                $"\n\n**Linked files:**\n- ref.png — {refPng}" +
                "\n\n*Noted Jan 15, 2025*\n\n---";
            string entryB =
                $"### clipB.mp4\n**File:** {clipB}\n**Tags:** #video" +
                "\n\nsecond clip" +
                "\n\n*Noted Jan 15, 2025*\n\n---";
            string entryPlain =
                $"### plain.txt\n**File:** {plain}" +
                "\n\nno tags here" +
                "\n\n*Noted Jan 15, 2025*\n\n---";
            string expectedBatch =
                $"# FileLore Export — {stamp}" +
                $"\n\n## #prompt\n\n{entryA}" +
                $"\n\n## #video\n\n{entryB}" +
                $"\n\n## Untagged\n\n{entryPlain}\n";
            string actualBatch = MarkdownExporter.BatchMarkdown(items);
            r.Info("---- batch export (grouped) ----");
            r.Info(actualBatch);
            if (actualBatch == expectedBatch)
                r.Pass("batch export matches golden (## #tag groups, ### entries, Untagged last, --- rules)");
            else
                r.Fail("batch export mismatch:\nEXPECTED:\n" + expectedBatch + "\nACTUAL:\n" + actualBatch);

            // ---------- batch export: flat (single tag across selection) ----------
            string actualFlat = MarkdownExporter.BatchMarkdown(new List<MarkdownExporter.ExportItem>
            {
                new(noteB, "clipB.mp4", clipB),
                new(notePlain, "plain.txt", plain),
            });
            string expectedFlat =
                $"# FileLore Export — {stamp}" +
                $"\n\n## clipB.mp4\n**File:** {clipB}\n**Tags:** #video" +
                "\n\nsecond clip" +
                "\n\n*Noted Jan 15, 2025*\n\n---" +
                $"\n\n## plain.txt\n**File:** {plain}" +
                "\n\nno tags here" +
                "\n\n*Noted Jan 15, 2025*\n\n---\n";
            if (actualFlat == expectedFlat)
                r.Pass("flat export (1 tag) matches golden (## entries, no tag groups)");
            else
                r.Fail("flat export mismatch:\nEXPECTED:\n" + expectedFlat + "\nACTUAL:\n" + actualFlat);
        }
        catch (Exception ex)
        {
            r.Fail("exception: " + ex);
        }
        finally
        {
            try { if (Directory.Exists(root)) Directory.Delete(root, recursive: true); } catch { }
        }
        return r.Finish(resultFile);
    }

    // ======================= templates =======================

    private static int RunTemplates(string resultFile)
    {
        var r = new CheckRun();
        using var backup = new SettingsBackup();
        try
        {
            // fresh state → ships with exactly the AI Generation default
            try { if (File.Exists(Settings.StoragePath)) File.Delete(Settings.StoragePath); } catch { }
            var defaults = Settings.LoadTemplates();
            if (defaults.Count == 1 && defaults[0].Name == "AI Generation"
                && defaults[0].Body == "Prompt:\n\nModel:\n\nVoice:\n\nLinks:\n")
                r.Pass("default template \"AI Generation\" ships with the exact Mac body");
            else
                r.Fail($"unexpected defaults: {defaults.Count} template(s)");

            // add / persist
            Settings.SaveTemplates(new[]
            {
                new NoteTemplate { Name = "t1", Body = "b1" },
                new NoteTemplate { Name = "t2", Body = "b2" },
            });
            var loaded = Settings.LoadTemplates();
            if (loaded.Count == 2 && loaded[0].Name == "t1" && loaded[1].Body == "b2")
                r.Pass("templates persist to settings.json (2 saved, 2 loaded)");
            else r.Fail("template persistence broken");

            // edit
            var edit = Settings.LoadTemplates();
            edit[0] = new NoteTemplate { Name = "t1", Body = "b1-edited" };
            edit.Add(new NoteTemplate { Name = "t3", Body = "b3" });
            Settings.SaveTemplates(edit);
            loaded = Settings.LoadTemplates();
            if (loaded.Count == 3 && loaded[0].Body == "b1-edited" && loaded[2].Name == "t3")
                r.Pass("template edit + add round-trips");
            else r.Fail("template edit/add broken");

            // delete
            loaded.RemoveAt(1);
            Settings.SaveTemplates(loaded);
            loaded = Settings.LoadTemplates();
            if (loaded.Count == 2 && loaded.All(t => t.Name != "t2"))
                r.Pass("template delete persists");
            else r.Fail("template delete broken");

            r.Info("settings.json restored to pre-test state after the run");
        }
        catch (Exception ex)
        {
            r.Fail("exception: " + ex);
        }
        return r.Finish(resultFile);
    }

    // ======================= pins =======================

    private static int RunPins(string resultFile)
    {
        var r = new CheckRun();
        using var backup = new SettingsBackup();
        try
        {
            Settings.SavePinnedTags(Array.Empty<string>());

            Settings.PinTag("alpha");
            Settings.PinTag("beta");
            var pinned = Settings.LoadPinnedTags();
            if (pinned.Count == 2 && pinned[0] == "alpha" && pinned[1] == "beta")
                r.Pass("pin two tags → persisted in order");
            else r.Fail("pin persistence broken");

            Settings.PinTag("ALPHA"); // case-insensitive duplicate must not double
            pinned = Settings.LoadPinnedTags();
            if (pinned.Count == 2)
                r.Pass("duplicate pin (different casing) is a no-op");
            else r.Fail("duplicate pin added");

            Settings.UnpinTag("alpha");
            pinned = Settings.LoadPinnedTags();
            if (pinned.Count == 1 && pinned[0] == "beta")
                r.Pass("unpin removes exactly that tag");
            else r.Fail("unpin broken");

            // round-trip through the raw file to prove it is really persisted
            string json = File.ReadAllText(Settings.StoragePath);
            if (json.Contains("pinnedTags") && json.Contains("beta"))
                r.Pass("pinnedTags key present in settings.json");
            else r.Fail("pinnedTags missing from settings.json");
        }
        catch (Exception ex)
        {
            r.Fail("exception: " + ex);
        }
        return r.Finish(resultFile);
    }

    // ======================= hotkeys =======================

    private static int RunHotkeys(string resultFile)
    {
        var r = new CheckRun();
        using var backup = new SettingsBackup();
        try
        {
            // deliberately exotic combos so the test never collides with the
            // running tray instance (which owns Ctrl+Alt+T/F).
            var open = new HotkeyCombo(HotkeyCombo.ModControl | HotkeyCombo.ModAlt | HotkeyCombo.ModShift, 0x78);   // F9
            var search = new HotkeyCombo(HotkeyCombo.ModControl | HotkeyCombo.ModAlt | HotkeyCombo.ModShift, 0x79); // F10

            // parse/format round-trip
            if (open.ToString() == "Ctrl+Alt+Shift+F9"
                && HotkeyCombo.Parse("Ctrl+Alt+Shift+F9") is { } parsed
                && parsed.Modifiers == open.Modifiers && parsed.Key == open.Key)
                r.Pass("combo format/parse round-trip: \"Ctrl+Alt+Shift+F9\"");
            else r.Fail("combo format/parse broken");

            // persist
            Settings.SaveHotkeys(open, search);
            var (loadedOpen, loadedSearch) = Settings.LoadHotkeys();
            if (loadedOpen.ToString() == "Ctrl+Alt+Shift+F9" && loadedSearch.ToString() == "Ctrl+Alt+Shift+F10")
                r.Pass("rebind persisted to settings.json");
            else r.Fail("hotkey persistence broken");

            // live registration + rebind (old combo unregistered)
            var failures = new List<int>();
            using var mgr = new HotkeyManager();
            mgr.HotkeyFailed += id => failures.Add(id);
            mgr.Register(open, search);
            if (failures.Count == 0 && mgr.Registered.Count == 2
                && mgr.Registered[HotkeyManager.IdOpenSelection].ToString() == "Ctrl+Alt+Shift+F9")
                r.Pass("Register registers both custom combos");
            else r.Fail($"initial registration failed (failures={failures.Count})");

            var open2 = new HotkeyCombo(open.Modifiers, 0x7A);   // F11
            var search2 = new HotkeyCombo(open.Modifiers, 0x7B); // F12
            bool ok = mgr.Reregister(open2, search2);
            if (ok && mgr.Registered[HotkeyManager.IdOpenSelection].ToString() == "Ctrl+Alt+Shift+F11"
                && mgr.Registered[HotkeyManager.IdSearch].ToString() == "Ctrl+Alt+Shift+F12"
                && !mgr.Registered.Values.Any(c => c.Key is 0x78 or 0x79))
                r.Pass("Reregister swaps both combos; old chords unregistered");
            else r.Fail("reregister left stale chords");

            // evidence: the unregistration lines in app.log
            try
            {
                var tail = File.ReadLines(AppLog.StoragePath).Reverse().Take(30).Reverse()
                    .Where(l => l.Contains("UnregisterHotKey") || l.Contains("RegisterHotKey"));
                r.Info("app.log hotkey evidence:");
                foreach (string line in tail) r.Info("  " + line);
                if (tail.Any(l => l.Contains("UnregisterHotKey id 1")))
                    r.Pass("app.log shows the old combo unregistered");
                else
                    r.Fail("no UnregisterHotKey evidence in app.log");
            }
            catch { r.Info("(app.log unreadable for evidence lines)"); }
        }
        catch (Exception ex)
        {
            r.Fail("exception: " + ex);
        }
        return r.Finish(resultFile);
    }

    // ======================= netpath (unchanged) =======================

    /// <summary>
    /// Unsupported-location guard self-test. Uses a real UNC path
    /// (\\Mac\Home\Downloads — Parallels Shared Folders, reachable in the VM)
    /// and asserts: the location check flags it with the network reason,
    /// saving there surfaces the friendly message without ever naming the
    /// raw ":filelore.note" stream path, a UNC search root is skipped
    /// gracefully, and a normal NTFS path is unaffected.
    /// </summary>
    private static int RunNetPath(string resultFile)
    {
        var lines = new List<string>();
        int failures = 0;
        void Pass(string s) => lines.Add("PASS: " + s);
        void Fail(string s) { lines.Add("FAIL: " + s); failures++; }

        const string netFile = @"\\Mac\Home\Downloads\__fl_nettest.tmp";
        const string netRoot = @"\\Mac\Home\Downloads";
        const string localFile = @"C:\FileLoreTest\ok.tmp";

        try
        {
            File.WriteAllText(netFile, "netpath selftest fixture");
            Directory.CreateDirectory(Path.GetDirectoryName(localFile)!);
            File.WriteAllText(localFile, "ntfs selftest fixture");

            // 1) UNC path detected unsupported, with the network reason
            var (netOk, netReason) = NoteStore.IsSupportedPath(netFile);
            if (!netOk && netReason.Contains("network or shared folder", StringComparison.OrdinalIgnoreCase))
                Pass($"UNC path detected unsupported: \"{netReason}\"");
            else
                Fail($"UNC path check returned ok={netOk}, reason=\"{netReason}\"");

            // 2) save on the UNC path fails friendly: no exception escapes
            //    uncaught by callers, and the message never leaks the raw
            //    "<path>:filelore.note" ADS path or the OS syntax error
            try
            {
                NoteEditorService.Save(netFile, "must not persist", Array.Empty<string>());
                Fail("save on a network path unexpectedly succeeded");
            }
            catch (Exception ex)
            {
                bool friendly = ex.Message.Contains("network or shared folder", StringComparison.OrdinalIgnoreCase)
                             && ex.Message.Contains("move or copy the file", StringComparison.OrdinalIgnoreCase);
                bool rawLeaked = ex.Message.Contains(NoteStore.StreamName, StringComparison.OrdinalIgnoreCase)
                              || ex.Message.Contains("syntax is incorrect", StringComparison.OrdinalIgnoreCase);
                if (friendly && !rawLeaked)
                    Pass("save on network path surfaces the friendly message (no raw ADS path)");
                else
                    Fail($"save message not friendly: \"{ex.Message}\"");
            }

            // 3) a UNC search root is skipped gracefully instead of scanned
            var skipped = new List<string>();
            int found = NoteIndex.Scan(new[] { netRoot }, _ => { }, onRootStarted: null,
                CancellationToken.None, onRootSkipped: skipped.Add);
            if (found == 0 && skipped.Count == 1 && skipped[0].Contains("Skipped network folder"))
                Pass($"UNC search root skipped gracefully: \"{skipped[0]}\"");
            else
                Fail($"expected one graceful skip line for the UNC root, got {skipped.Count} (found={found})");

            // 4) a normal NTFS path still reports supported and saves
            var (localOk, localReason) = NoteStore.IsSupportedPath(localFile);
            if (localOk)
                Pass("local NTFS path still detected supported");
            else
                Fail($"local NTFS path reported unsupported: \"{localReason}\"");

            NoteEditorService.Save(localFile, "ntfs still works", new[] { "netpath" });
            var readBack = NoteStore.Read(localFile);
            if (readBack is not null && readBack.Body == "ntfs still works")
                Pass("save/read round-trip on local NTFS still works");
            else
                Fail("local NTFS round-trip broken");
            NoteStore.Delete(localFile);
        }
        catch (Exception ex)
        {
            Fail("exception: " + ex);
        }
        finally
        {
            try { File.Delete(netFile); } catch { /* share unreachable etc. */ }
            try { File.Delete(localFile); } catch { /* nowhere else to report */ }
        }

        lines.Add(failures == 0 ? "SELFTEST PASSED" : $"SELFTEST FAILED ({failures} failing check(s))");
        try { File.WriteAllLines(resultFile, lines); }
        catch { /* GUI-subsystem app: if the result file is unwritable there is nowhere to report */ }
        return failures == 0 ? 0 : 1;
    }

    // ======================= save-path (unchanged) =======================

    /// <summary>Save-path round-trip (M2 hook, unchanged semantics).</summary>
    private static int RunSavePath(string[] args)
    {
        string resultFile = args[1];
        string target = args[2];
        string body = args[3];
        var tags = args[4].Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        var lines = new List<string>();
        int failures = 0;
        void Pass(string s) => lines.Add("PASS: " + s);
        void Fail(string s) { lines.Add("FAIL: " + s); failures++; }

        try
        {
            if (!File.Exists(target))
            {
                Fail($"target file missing: {target}");
            }
            else
            {
                NoteStore.Delete(target); // clean slate

                // 1) save through the app's own save path, read back via FileLore.Core
                var saved1 = NoteEditorService.Save(target, body, tags);
                var r1 = NoteStore.Read(target);
                if (r1 is not null
                    && r1.Body == body
                    && r1.Tags.SequenceEqual(tags)
                    && ApproxEq(r1.Created, saved1.Created))
                {
                    Pass("NoteEditorService.Save round-trips body/tags/created through the ADS stream");
                }
                else
                {
                    Fail("round-trip mismatch after first save");
                }

                // 2) create-or-update: created preserved, modified refreshed
                Thread.Sleep(1100);
                var editedBody = body + " (edited)";
                var editedTags = tags.Concat(new[] { "edited" }).ToArray();
                NoteEditorService.Save(target, editedBody, editedTags);
                var r2 = NoteStore.Read(target);
                if (r2 is not null
                    && ApproxEq(r2.Created, saved1.Created)
                    && r2.Modified > saved1.Modified
                    && r2.Body == editedBody
                    && r2.Tags.SequenceEqual(editedTags))
                {
                    Pass("create-or-update preserves created, refreshes modified");
                }
                else
                {
                    Fail("update semantics broken (created/modified/body/tags)");
                }

                // 3) recents recorded by the save path
                var recents = Recents.Load();
                if (recents.Count > 0 && string.Equals(recents[0], target, StringComparison.OrdinalIgnoreCase))
                    Pass($"recents updated at {Recents.StoragePath}");
                else
                    Fail("recents missing target after save");
            }
        }
        catch (Exception ex)
        {
            Fail("exception: " + ex);
        }

        lines.Add(failures == 0 ? "SELFTEST PASSED" : $"SELFTEST FAILED ({failures} failing check(s))");
        try { File.WriteAllLines(resultFile, lines); }
        catch { /* GUI-subsystem app: if the result file is unwritable there is nowhere to report */ }
        return failures == 0 ? 0 : 1;
    }

    // ======================= search (unchanged) =======================

    /// <summary>
    /// Enumeration + search self-test. Builds a fixture tree
    /// (C:\FileLoreTest\sidx\{a\deep\b.mp4, c\img.png, plain.txt}), attaches
    /// notes through the app's own save path, then runs NoteIndex.Scan and
    /// NoteSearch.Matches with the same calls the search window uses.
    /// </summary>
    private static int RunSearch(string resultFile)
    {
        var lines = new List<string>();
        int failures = 0;
        void Pass(string s) => lines.Add("PASS: " + s);
        void Fail(string s) { lines.Add("FAIL: " + s); failures++; }

        string root = @"C:\FileLoreTest\sidx";
        string mp4 = Path.Combine(root, @"a\deep\b.mp4");
        string png = Path.Combine(root, @"c\img.png");
        string plain = Path.Combine(root, "plain.txt");

        try
        {
            // fixture tree, from scratch so stale notes can't skew the counts
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
            Directory.CreateDirectory(Path.GetDirectoryName(mp4)!);
            Directory.CreateDirectory(Path.GetDirectoryName(png)!);
            File.WriteAllBytes(mp4, new byte[] { 1, 2, 3 });
            File.WriteAllBytes(png, new byte[] { 4, 5, 6 });
            File.WriteAllText(plain, "no note here");

            NoteEditorService.Save(mp4, "alpha prompt zebra", new[] { "findme", "m3" });
            NoteEditorService.Save(png, "beta", new[] { "m3" });

            // 1) enumeration finds exactly the two noted files
            var found = new List<IndexedNote>();
            NoteIndex.Scan(new[] { root }, found.Add, onRootStarted: null, CancellationToken.None);
            if (found.Count == 2)
                Pass("enumeration finds exactly 2 noted files");
            else
                Fail($"expected 2 noted files, got {found.Count}");

            if (found.Any(n => string.Equals(n.Path, plain, StringComparison.OrdinalIgnoreCase)))
                Fail("plain.txt (no ADS note) was returned by enumeration");
            else
                Pass("plain.txt without a note is skipped");

            IndexedNote? byName(string name) =>
                found.FirstOrDefault(n => string.Equals(n.FileName, name, StringComparison.OrdinalIgnoreCase));
            if (byName("b.mp4") is not null && byName("img.png") is not null)
                Pass("both b.mp4 and img.png carry their notes into the index");
            else
                Fail("expected b.mp4 and img.png in the index");

            // 2) free-text search hits body, not the untagged/plain file
            var zebra = found.Where(n => NoteSearch.Matches(n, "zebra", Array.Empty<string>())).ToList();
            if (zebra.Count == 1 && string.Equals(zebra[0].FileName, "b.mp4", StringComparison.OrdinalIgnoreCase))
                Pass("search \"zebra\" matches only b.mp4");
            else
                Fail($"search \"zebra\" returned {zebra.Count} result(s)");

            // 3) tag-chip filters
            var m3 = found.Where(n => NoteSearch.Matches(n, null, new[] { "m3" })).ToList();
            if (m3.Count == 2)
                Pass("tag filter \"m3\" matches both notes");
            else
                Fail($"tag filter \"m3\" returned {m3.Count} result(s)");

            var findme = found.Where(n => NoteSearch.Matches(n, null, new[] { "findme" })).ToList();
            if (findme.Count == 1 && string.Equals(findme[0].FileName, "b.mp4", StringComparison.OrdinalIgnoreCase))
                Pass("tag filter \"findme\" matches only b.mp4");
            else
                Fail($"tag filter \"findme\" returned {findme.Count} result(s)");
        }
        catch (Exception ex)
        {
            Fail("exception: " + ex);
        }

        lines.Add(failures == 0 ? "SELFTEST PASSED" : $"SELFTEST FAILED ({failures} failing check(s))");
        try { File.WriteAllLines(resultFile, lines); }
        catch { /* nowhere else to report */ }
        return failures == 0 ? 0 : 1;
    }
}
