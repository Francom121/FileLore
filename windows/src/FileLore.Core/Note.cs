using System.Text.Json;
using System.Text.Json.Serialization;

namespace FileLore.Core;

/// <summary>
/// Serializes <see cref="DateTime"/> exactly the way the Mac app's
/// <c>JSONEncoder</c> serializes Swift <c>Date</c> by default
/// (<c>DateEncodingStrategy.deferredToDate</c>): a JSON number of seconds
/// since the Apple reference date 2001-01-01T00:00:00Z. Keeping the same
/// wire format means notes written by the Windows build remain parseable
/// by the macOS app and vice versa.
/// </summary>
public sealed class AppleReferenceDateJsonConverter : JsonConverter<DateTime>
{
    private static readonly DateTime Epoch = new(2001, 1, 1, 0, 0, 0, DateTimeKind.Utc);

    public override DateTime Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        => Epoch.AddSeconds(reader.GetDouble());

    public override void Write(Utf8JsonWriter writer, DateTime value, JsonSerializerOptions options)
        => writer.WriteNumberValue((value.ToUniversalTime() - Epoch).TotalSeconds);
}

/// <summary>
/// A file referenced from a note. Mirrors <c>LinkedFile</c> in
/// TetherCore/Sources/TetherCore/Note.swift: same JSON property names,
/// same semantics. Intentional deviation: on macOS <c>bookmark</c> holds a
/// security-scoped bookmark blob; NTFS has no such concept, so on Windows
/// this is an opaque payload reserved for a future Windows link scheme
/// (M1 stores placeholder bytes). JSON shape is unaffected (base64 string).
/// </summary>
public sealed class LinkedFile
{
    [JsonPropertyName("id")]
    public Guid Id { get; set; }

    /// <summary>Opaque link payload; base64 in JSON, matching Swift <c>Data</c> encoding.</summary>
    [JsonPropertyName("bookmark")]
    public byte[] Bookmark { get; set; } = Array.Empty<byte>();

    [JsonPropertyName("displayName")]
    public string DisplayName { get; set; } = "";

    [JsonPropertyName("relativePathHint")]
    public string RelativePathHint { get; set; } = "";
}

/// <summary>
/// A sticky note attached to a file. Mirrors <c>Note</c> in
/// TetherCore/Sources/TetherCore/Note.swift: on macOS it lives in the
/// <c>com.filelore.note</c> xattr, on Windows in the
/// <c>filelore.note</c> NTFS alternate data stream.
/// </summary>
public sealed class Note
{
    [JsonPropertyName("body")]
    public string Body { get; set; } = "";

    [JsonPropertyName("tags")]
    public List<string> Tags { get; set; } = new();

    [JsonPropertyName("links")]
    public List<LinkedFile> Links { get; set; } = new();

    [JsonPropertyName("created")]
    [JsonConverter(typeof(AppleReferenceDateJsonConverter))]
    public DateTime Created { get; set; } = DateTime.UtcNow;

    [JsonPropertyName("modified")]
    [JsonConverter(typeof(AppleReferenceDateJsonConverter))]
    public DateTime Modified { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// Versioned JSON envelope persisted as the ADS payload, mirroring
/// <c>NoteEnvelope</c> on macOS, so future payload migrations can detect
/// what they are reading.
/// </summary>
public sealed class NoteEnvelope
{
    public const int CurrentVersion = 1;

    [JsonPropertyName("version")]
    public int Version { get; set; } = CurrentVersion;

    [JsonPropertyName("note")]
    public Note Note { get; set; } = new();
}
