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
///
/// Writes human-readable PASS/FAIL lines to &lt;resultFile&gt; (the app is a
/// GUI-subsystem binary, so console output is not reliable). Exit code 0 =
/// all checks passed.
/// </summary>
internal static class SelfTest
{
    private static bool ApproxEq(DateTime a, DateTime b) => Math.Abs((a - b).TotalMilliseconds) < 1.0;

    public static int Run(string[] args)
    {
        if (args.Length >= 2 && args[1] == "search")
            return RunSearch(args[2]);
        if (args.Length >= 2 && args[1] == "netpath")
            return RunNetPath(args[2]);
        return RunSavePath(args);
    }

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
