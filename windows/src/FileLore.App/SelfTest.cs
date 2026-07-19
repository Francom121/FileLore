using System.IO;
using FileLore.Core;

namespace FileLore.App;

/// <summary>
/// Headless verification hook that drives the exact same save path as the
/// editor's Save button (<see cref="NoteEditorService.Save"/>), so milestone
/// verification can prove the write path end-to-end without UI automation.
///
/// Usage: FileLore.exe --selftest &lt;resultFile&gt; &lt;targetPath&gt; &lt;body&gt; &lt;tagsCsv&gt;
///
/// Writes human-readable PASS/FAIL lines to &lt;resultFile&gt; (the app is a
/// GUI-subsystem binary, so console output is not reliable). Exit code 0 =
/// all checks passed. Leaves a note on the target file so the GUI editor can
/// be pointed at the same file afterwards to demonstrate the load path.
/// </summary>
internal static class SelfTest
{
    private static bool ApproxEq(DateTime a, DateTime b) => Math.Abs((a - b).TotalMilliseconds) < 1.0;

    public static int Run(string[] args)
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
}
