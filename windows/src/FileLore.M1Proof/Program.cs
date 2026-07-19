using System.Text.Json;
using FileLore.Core;

// FileLore-Windows milestone 1 proof:
// a note stored in an NTFS Alternate Data Stream survives a file rename
// and a folder move on the same volume. Runs against C:\FileLoreTest with
// a clean slate every run. Exit code 0 = all steps passed, 1 = failure.

const string TestRoot = @"C:\FileLoreTest";
const string SubDir = @"C:\FileLoreTest\subfolder";

string fileV1 = Path.Combine(TestRoot, "clip.mp4");
string fileV2 = Path.Combine(TestRoot, "clip v2.mp4");
string fileMoved = Path.Combine(SubDir, "clip v2.mp4");
string plainFile = Path.Combine(TestRoot, "plain.txt");

int failures = 0;

void Pass(string step) => Console.WriteLine($"PASS: {step}");
void Fail(string step, string why)
{
    Console.WriteLine($"FAIL: {step} :: {why}");
    failures++;
}

var canonOptions = new JsonSerializerOptions { WriteIndented = true };
// Canonical deep-equality: same values → identical JSON text (date converter
// is attribute-based, so formatting is options-independent).
string Canonical(Note n) => JsonSerializer.Serialize(n, canonOptions);

int Finish()
{
    if (failures == 0)
    {
        Console.WriteLine("ALL PROOF STEPS PASSED");
        return 0;
    }
    Console.WriteLine($"PROOF FAILED ({failures} failing step(s))");
    return 1;
}

try
{
    // ---- clean slate ------------------------------------------------------
    if (Directory.Exists(TestRoot))
        Directory.Delete(TestRoot, recursive: true);
    Directory.CreateDirectory(TestRoot);

    var payload = new byte[64 * 1024];
    Random.Shared.NextBytes(payload);
    File.WriteAllBytes(fileV1, payload);
    Console.WriteLine($"setup: {fileV1} created ({payload.Length} random bytes)");

    // ---- step 1: write a note, read it back --------------------------------
    var note = new Note
    {
        Body = "Prompt: cinematic product shot, warm light",
        Tags = new List<string> { "demo", "m1" },
        Links = new List<LinkedFile>
        {
            new LinkedFile
            {
                Id = Guid.Parse("11111111-2222-3333-4444-555555555555"),
                Bookmark = "m1-placeholder-bookmark"u8.ToArray(),
                DisplayName = "storyboard.png",
                RelativePathHint = "storyboard.png",
            }
        },
        // whole-second timestamps round-trip exactly through the
        // seconds-since-2001 double encoding
        Created = new DateTime(2025, 1, 15, 10, 30, 0, DateTimeKind.Utc),
        Modified = new DateTime(2025, 1, 15, 10, 30, 0, DateTimeKind.Utc),
    };

    var writeStart = DateTime.UtcNow;
    NoteStore.Write(fileV1, note);
    var writeEnd = DateTime.UtcNow;

    var r1 = NoteStore.Read(fileV1);
    bool step1 = r1 is not null
        && r1.Body == note.Body
        && r1.Tags.SequenceEqual(note.Tags)
        && r1.Links.Count == 1
        && r1.Links[0].Id == note.Links[0].Id
        && r1.Links[0].Bookmark.SequenceEqual(note.Links[0].Bookmark)
        && r1.Links[0].DisplayName == note.Links[0].DisplayName
        && r1.Links[0].RelativePathHint == note.Links[0].RelativePathHint
        && r1.Created == note.Created
        && r1.Modified >= writeStart && r1.Modified <= writeEnd; // Write refreshes Modified, like the Mac store

    if (!step1 || r1 is null)
    {
        Fail("write note + read-back", r1 is null ? "Read returned null" : "field mismatch after read-back");
        return Finish();
    }
    Pass("write note to clip.mp4 + read-back matches (body, tags, link entry, created; modified refreshed by Write)");

    string canon1 = Canonical(r1);

    // ---- step 2: rename the file -------------------------------------------
    File.Move(fileV1, fileV2);
    var r2 = NoteStore.Read(fileV2);
    if (r2 is not null && Canonical(r2) == canon1 && !NoteStore.HasNote(fileV1))
        Pass("rename clip.mp4 -> 'clip v2.mp4': note reads identically (old path has no note)");
    else
        Fail("rename", r2 is null ? "note lost after rename" : "note content changed by rename");
    if (r2 is null) return Finish();

    // ---- step 3: move the file into a subfolder -----------------------------
    Directory.CreateDirectory(SubDir);
    File.Move(fileV2, fileMoved);
    var r3 = NoteStore.Read(fileMoved);
    if (r3 is not null && Canonical(r3) == canon1)
        Pass("move into C:\\FileLoreTest\\subfolder\\: note reads identically");
    else
        Fail("folder move", r3 is null ? "note lost after move" : "note content changed by move");
    if (r3 is null) return Finish();

    // ---- step 4: raw stream proof on the moved file --------------------------
    var raw = NoteStore.ReadRawBytes(fileMoved);
    if (raw is not null && raw.Length > 0 && NoteStore.HasNote(fileMoved))
    {
        Console.WriteLine($"proof: stream \"{NoteStore.StreamName}\" on moved file = {raw.Length} bytes, payload:");
        Console.WriteLine(System.Text.Encoding.UTF8.GetString(raw));
        Pass($"HasNote + raw stream bytes readable on moved file ({raw.Length} bytes)");
    }
    else
    {
        Fail("stream proof", "no readable stream bytes on moved file");
    }

    // ---- step 5: negative case ----------------------------------------------
    File.WriteAllText(plainFile, "this file never gets a note");
    if (!NoteStore.HasNote(plainFile) && NoteStore.Read(plainFile) is null)
        Pass("negative: never-noted file plain.txt reports HasNote=false, Read=null");
    else
        Fail("negative case", "plain.txt unexpectedly reports a note");

    // ---- step 6: delete -------------------------------------------------------
    NoteStore.Delete(fileMoved);
    if (!NoteStore.HasNote(fileMoved))
        Pass("Delete removes the note stream from the moved file");
    else
        Fail("delete", "note stream still present after Delete");

    return Finish();
}
catch (Exception ex)
{
    Fail("unhandled exception", ex.ToString());
    return Finish();
}
