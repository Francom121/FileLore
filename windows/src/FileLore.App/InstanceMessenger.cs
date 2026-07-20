using System.IO;
using System.IO.Pipes;
using System.Text;

namespace FileLore.App;

/// <summary>
/// Tiny named-pipe protocol that ties Explorer multi-select into one
/// window. Right-clicking N files fires N FileLore.exe invocations; the
/// first instance owns the mutex and runs <see cref="StartServer"/>,
/// instances 2..N forward their file path through
/// <see cref="TrySend"/> and exit. The first instance debounce-collects
/// (~1.5 s) all paths — its own argument included — and opens ONE batch
/// window (or the editor for a single file).
///
/// Wire format: one UTF-8 line "PATH &lt;full path&gt;\n" from client to
/// server, one "OK\n" line back. Anything malformed is dropped.
/// </summary>
public static class InstanceMessenger
{
    public const string PipeName = "FileLore.SingleInstance.Paths";
    private const string Prefix = "PATH ";

    private static volatile bool _stopping;

    /// <summary>
    /// Secondary-instance side: deliver <paramref name="path"/> to the
    /// primary instance. Retries briefly because the primary may still be
    /// setting up its pipe when Explorer launches several processes at
    /// once. Returns false when no server answered in time.
    /// </summary>
    public static bool TrySend(string path, int timeoutMs = 6000)
    {
        var deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        while (DateTime.UtcNow < deadline)
        {
            try
            {
                using var client = new NamedPipeClientStream(".", PipeName, PipeDirection.InOut);
                client.Connect(800);
                byte[] payload = Encoding.UTF8.GetBytes(Prefix + path + "\n");
                client.Write(payload, 0, payload.Length);
                client.Flush();
                // Wait for the ack so the path is never lost silently.
                var buffer = new byte[8];
                int read = client.Read(buffer, 0, buffer.Length);
                return read >= 2 && buffer[0] == (byte)'O' && buffer[1] == (byte)'K';
            }
            catch (TimeoutException) { /* server busy → retry until deadline */ }
            catch (IOException) { /* pipe not ready / broken → retry until deadline */ }
            catch (UnauthorizedAccessException) { return false; }
            Thread.Sleep(120);
        }
        AppLog.Write("InstanceMessenger.TrySend timed out for " + path);
        return false;
    }

    /// <summary>
    /// Primary-instance side: accepts path deliveries on a background
    /// thread until <see cref="StopServer"/>. Each accepted path is
    /// reported on a thread-pool thread; the callee marshals to the UI.
    /// </summary>
    public static void StartServer(Action<string> onPath)
    {
        _stopping = false;
        var thread = new Thread(() => ServerLoop(onPath))
        {
            IsBackground = true,
            Name = "FileLore.InstanceMessenger",
        };
        thread.Start();
    }

    public static void StopServer() => _stopping = true;

    private static void ServerLoop(Action<string> onPath)
    {
        while (!_stopping)
        {
            NamedPipeServerStream? server = null;
            try
            {
                server = new NamedPipeServerStream(
                    PipeName, PipeDirection.InOut, NamedPipeServerStream.MaxAllowedServerInstances,
                    PipeTransmissionMode.Byte, PipeOptions.None);
                server.WaitForConnection();
                var accepted = server; // pass by value: server is nulled below
                server = null; // ownership moved to the handler
                Task.Run(() => HandleConnection(accepted, onPath));
            }
            catch (Exception ex)
            {
                server?.Dispose();
                AppLog.Write("InstanceMessenger server: " + ex.Message);
                Thread.Sleep(250); // don't spin on persistent errors
            }
        }
    }

    private static void HandleConnection(NamedPipeServerStream connection, Action<string> onPath)
    {
        using (connection)
        {
            try
            {
                string? line = ReadLine(connection, maxBytes: 64 * 1024);
                if (line is not null && line.StartsWith(Prefix, StringComparison.Ordinal))
                {
                    string path = line[Prefix.Length..].Trim();
                    if (path.Length > 0)
                    {
                        connection.Write(new byte[] { (byte)'O', (byte)'K', (byte)'\n' }, 0, 3);
                        connection.Flush();
                        AppLog.Write("InstanceMessenger received: " + path);
                        onPath(path);
                    }
                }
            }
            catch (Exception ex)
            {
                AppLog.Write("InstanceMessenger connection: " + ex.Message);
            }
        }
    }

    private static string? ReadLine(Stream stream, int maxBytes)
    {
        var bytes = new List<byte>();
        var one = new byte[1];
        while (bytes.Count < maxBytes)
        {
            int read = stream.Read(one, 0, 1);
            if (read == 0) return null; // client went away
            if (one[0] == (byte)'\n') break;
            bytes.Add(one[0]);
        }
        return Encoding.UTF8.GetString(bytes.ToArray());
    }
}
