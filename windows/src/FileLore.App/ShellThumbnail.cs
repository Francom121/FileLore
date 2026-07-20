using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media.Imaging;

namespace FileLore.App;

/// <summary>
/// Shell-provided thumbnails and icons via <c>IShellItemImageFactory</c>
/// (raw P/Invoke, no NuGet packages). Used for linked-file rows (32px), as
/// the preview for image formats WIC can't decode (e.g. PSD, 256px), and as
/// the large-icon fallback for files with no media preview.
/// </summary>
public static class ShellThumbnail
{
    private const uint SiigbfResizeToFit = 0x00;
    private const uint SiigbfThumbnailOnly = 0x08;
    private const uint SiigbfIconOnly = 0x04;

    /// <summary>
    /// Best-effort thumbnail for <paramref name="path"/> at
    /// <paramref name="sizePx"/>×<paramref name="sizePx"/>: a real thumbnail
    /// when the shell has one, otherwise the file's icon. Returns
    /// <c>null</c> only when the shell can't produce anything at all.
    /// The result is frozen and safe to use on the UI thread.
    /// </summary>
    public static BitmapSource? Get(string path, int sizePx, bool thumbnailOnly = false)
    {
        IntPtr hBitmap = IntPtr.Zero;
        IShellItemImageFactory? factory = null;
        try
        {
            var iid = new Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"); // IID_IShellItemImageFactory
            int hr = SHCreateItemFromParsingName(path, IntPtr.Zero, iid, out factory);
            if (hr != 0 || factory is null) return null;

            var size = new SIZE { cx = sizePx, cy = sizePx };
            hr = factory.GetImage(size, thumbnailOnly ? SiigbfThumbnailOnly : SiigbfResizeToFit, out hBitmap);
            if (hr != 0 && thumbnailOnly)
                hr = factory.GetImage(size, SiigbfIconOnly, out hBitmap); // no thumbnail → icon
            if (hr != 0 || hBitmap == IntPtr.Zero) return null;

            var bmp = Imaging.CreateBitmapSourceFromHBitmap(
                hBitmap, IntPtr.Zero, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            bmp.Freeze();
            return bmp;
        }
        catch
        {
            return null; // shell failures must never break the UI
        }
        finally
        {
            if (hBitmap != IntPtr.Zero) DeleteObject(hBitmap);
            if (factory is not null) Marshal.ReleaseComObject(factory);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SIZE { public int cx; public int cy; }

    [ComImport]
    [Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItemImageFactory
    {
        [PreserveSig]
        int GetImage(SIZE size, uint flags, out IntPtr phbm);
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int SHCreateItemFromParsingName(
        [MarshalAs(UnmanagedType.LPWStr)] string pszPath,
        IntPtr pbc,
        [MarshalAs(UnmanagedType.LPStruct)] Guid riid,
        out IShellItemImageFactory ppv);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeleteObject(IntPtr hObject);
}
