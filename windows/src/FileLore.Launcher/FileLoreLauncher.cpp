// ============================================================================
//  FileLoreLauncher.cpp — native first-run launcher ("FileLore.exe").
//
//  Why this exists: the real app (FileLoreApp.exe) is a self-contained
//  single-file .NET 8 binary. On a cold first launch Windows can spend up to
//  a minute on one-time bundle extraction + Defender scan before ANY WPF
//  window can exist — the in-app splash cannot cover that gap. This tiny
//  native exe starts instantly, shows a branded "getting ready" window,
//  launches FileLoreApp.exe from the same folder, and closes itself the
//  moment the app shows its first visible window (or exits without one —
//  e.g. a second instance that forwarded to the single-instance pipe).
//
//  Pure Win32, no ATL/MFC, /MT static CRT → zero runtime dependencies.
//  Build with build-launcher.cmd (x64 + arm64).
// ============================================================================
#include <windows.h>
#include <shellapi.h>
#include <math.h>

// ---- brand palette (website tailwind "fl" scale + the WPF splash) ----------
#define COL_BG      RGB(0xFD, 0xF7, 0xEC)   // fl-50  warm cream
#define COL_BORDER  RGB(0xF2, 0xE3, 0xC6)   // splash card border
#define COL_INK     RGB(0x17, 0x12, 0x08)   // ink    wordmark
#define COL_MSG     RGB(0x44, 0x44, 0x44)   // splash message gray
#define COL_SUB     RGB(0x8A, 0x8A, 0x84)   // splash secondary gray
#define COL_ACCENT  RGB(0xEB, 0x96, 0x1E)   // fl-500 brand orange

// ---- layout (logical units @96 DPI, scaled by the system DPI) --------------
static const int kWinW = 420, kWinH = 252;

static const UINT_PTR kTimerId = 1;
static const UINT     kTickMs = 16;             // ~60 fps animation
static const DWORD    kMaxWaitMs = 300000;      // give up after 5 minutes

static HINSTANCE g_inst;
static HWND      g_hwnd;
static HANDLE    g_hProcess;
static DWORD     g_pid;
static DWORD     g_startTick;
static int       g_angle;                       // spinner head angle (degrees)
static BYTE      g_alpha;                       // layered-window opacity
static bool      g_fadingOut;
static volatile LONG g_launchState;             // 0=idle 1=launching 2=ok 3=failed
static int       g_launchError;                 // 0=none 1=FileLoreApp.exe missing 2=CreateProcess failed
static DWORD     g_lastError;
static int       g_exitCode;
static int       g_dpi = 96;
static HPEN      g_segPens[12];                 // spinner fade ramp, head→tail

static int S(int v) { return MulDiv(v, g_dpi, 96); }

// ---- child-process launch ----------------------------------------------------

// Points past argv[0] in GetCommandLineW (respects a quoted exe path),
// so the remainder — original quoting intact — can be appended verbatim.
static LPCWSTR SkipArgv0(LPCWSTR cmd)
{
    while (*cmd == L' ' || *cmd == L'\t') cmd++;
    if (*cmd == L'"')
    {
        cmd++;
        while (*cmd && *cmd != L'"') cmd++;
        if (*cmd == L'"') cmd++;
    }
    else
    {
        while (*cmd && *cmd != L' ' && *cmd != L'\t') cmd++;
    }
    return cmd;
}

static bool HasFlag(int argc, LPWSTR* argv, LPCWSTR flag)
{
    for (int i = 1; i < argc; i++)
        if (lstrcmpiW(argv[i], flag) == 0) return true;
    return false;
}

// Any argument starting with the given prefix (case-insensitive), e.g.
// Velopack's lifecycle hooks: --veloapp-install 0.8.0, --veloapp-updated ...
static bool HasArgWithPrefix(int argc, LPWSTR* argv, LPCWSTR prefix)
{
    size_t n = lstrlenW(prefix);
    for (int i = 1; i < argc; i++)
        if (CompareStringOrdinal(argv[i], (int)n, prefix, (int)n, TRUE) == CSTR_EQUAL)
            return true;
    return false;
}

// Launches FileLoreApp.exe (same folder) with our original arguments.
// Pure mechanics — no UI; failure details land in g_launchError/g_lastError
// so the caller's thread can decide how to report them.
static bool LaunchRealApp()
{
    WCHAR dir[MAX_PATH];
    GetModuleFileNameW(NULL, dir, MAX_PATH);
    WCHAR* slash = wcsrchr(dir, L'\\');
    if (slash) *slash = 0;

    WCHAR appPath[MAX_PATH];
    wsprintfW(appPath, L"%s\\FileLoreApp.exe", dir);

    if (GetFileAttributesW(appPath) == INVALID_FILE_ATTRIBUTES)
    {
        g_launchError = 1;
        return false;
    }

    WCHAR cmdline[32768];
    wsprintfW(cmdline, L"\"%s\"%s", appPath, SkipArgv0(GetCommandLineW()));

    STARTUPINFOW si = {};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi = {};
    if (!CreateProcessW(NULL, cmdline, NULL, NULL, FALSE, 0, NULL, dir, &si, &pi))
    {
        g_launchError = 2;
        g_lastError = GetLastError();
        return false;
    }
    g_hProcess = pi.hProcess;
    g_pid = pi.dwProcessId;
    CloseHandle(pi.hThread);
    return true;
}

// The windowed path launches the app on a WORKER thread: CreateProcess of the
// 160+ MB single-file exe can block for many seconds while Defender scans a
// brand-new unsigned binary, and blocking the UI thread would freeze the
// launcher window mid-fade — exactly the dead-air gap this exe exists to
// cover. The worker records the outcome in g_launchState.
static DWORD WINAPI LaunchWorker(LPVOID)
{
    if (LaunchRealApp())
    {
        g_startTick = GetTickCount();
        InterlockedExchange(&g_launchState, 2);
    }
    else
    {
        InterlockedExchange(&g_launchState, 3);
    }
    return 0;
}

static void ShowLaunchError()
{
    if (g_launchError == 1)
        MessageBoxW(NULL,
            L"FileLoreApp.exe was not found next to FileLore.exe.\n\n"
            L"The download was only partly extracted \u2014 unzip the whole "
            L"FileLore download folder and try again.",
            L"FileLore", MB_ICONERROR | MB_OK);
    else
    {
        WCHAR msg[256];
        wsprintfW(msg, L"Windows could not start FileLoreApp.exe (error %lu).\n\n"
                       L"Try re-downloading FileLore.", g_lastError);
        MessageBoxW(NULL, msg, L"FileLore", MB_ICONERROR | MB_OK);
    }
}

// ---- window-visible detection ------------------------------------------------

static BOOL CALLBACK FindAppWindow(HWND hwnd, LPARAM lParam)
{
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid == (DWORD)lParam && IsWindowVisible(hwnd))
    {
        // Any visible top-level window of the app (its own branded splash,
        // drop zone, editor, …) means the handoff is complete.
        return FALSE;
    }
    return TRUE;
}

static bool AppWindowIsUp()
{
    return EnumWindows(FindAppWindow, (LPARAM)g_pid) == FALSE;
}

// ---- painting ----------------------------------------------------------------

static void DrawSpinSegment(HDC dc, int cx, int cy, int rOuter, int rInner,
                            double deg, HPEN pen)
{
    double rad = deg * 3.14159265358979 / 180.0;
    double c = cos(rad), s = sin(rad);
    HPEN old = (HPEN)SelectObject(dc, pen);
    MoveToEx(dc, cx + (int)(rInner * c + 0.5), cy + (int)(rInner * s + 0.5), NULL);
    LineTo(dc,   cx + (int)(rOuter * c + 0.5), cy + (int)(rOuter * s + 0.5));
    SelectObject(dc, old);
}

static void Paint(HWND hwnd)
{
    PAINTSTRUCT ps;
    HDC dc = BeginPaint(hwnd, &ps);

    RECT rc;
    GetClientRect(hwnd, &rc);
    int w = rc.right, h = rc.bottom;

    HDC mem = CreateCompatibleDC(dc);
    HBITMAP bmp = CreateCompatibleBitmap(dc, w, h);
    HBITMAP oldBmp = (HBITMAP)SelectObject(mem, bmp);

    // Card background + hairline border (matches the WPF splash card).
    HBRUSH bg = CreateSolidBrush(COL_BG);
    HPEN border = CreatePen(PS_SOLID, 1, COL_BORDER);
    HBRUSH oldBrush = (HBRUSH)SelectObject(mem, bg);
    HPEN oldPen = (HPEN)SelectObject(mem, border);
    RoundRect(mem, 0, 0, w, h, S(16), S(16));
    SelectObject(mem, oldBrush);
    SelectObject(mem, oldPen);
    DeleteObject(bg);
    DeleteObject(border);

    SetBkMode(mem, TRANSPARENT);

    // Icon.
    int iconSize = S(52);
    HICON icon = (HICON)LoadImageW(g_inst, MAKEINTRESOURCEW(1), IMAGE_ICON,
                                   iconSize, iconSize, LR_DEFAULTCOLOR);
    if (!icon) icon = LoadIconW(g_inst, MAKEINTRESOURCEW(1));
    if (icon) DrawIconEx(mem, (w - iconSize) / 2, S(22), icon, iconSize, iconSize,
                         0, NULL, DI_NORMAL);
    if (icon) DestroyIcon(icon);

    // Wordmark + status lines.
    HFONT fTitle = CreateFontW(-MulDiv(19, g_dpi, 72), 0, 0, 0, FW_SEMIBOLD,
                               FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                               OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                               CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    HFONT fMsg = CreateFontW(-MulDiv(12, g_dpi, 72), 0, 0, 0, FW_NORMAL,
                             FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                             OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                             CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    HFONT fSub = CreateFontW(-MulDiv(10, g_dpi, 72), 0, 0, 0, FW_NORMAL,
                             FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                             OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                             CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");

    RECT tr;
    HFONT oldFont = (HFONT)SelectObject(mem, fTitle);
    SetTextColor(mem, COL_INK);
    SetRect(&tr, 0, S(82), w, S(82) + S(30));
    DrawTextW(mem, L"FileLore", -1, &tr, DT_CENTER | DT_SINGLELINE | DT_VCENTER);

    SelectObject(mem, fMsg);
    SetTextColor(mem, COL_MSG);
    SetRect(&tr, 0, S(114), w, S(114) + S(20));
    DrawTextW(mem, L"Getting FileLore ready\u2026", -1, &tr,
              DT_CENTER | DT_SINGLELINE | DT_VCENTER);

    // Spinner: 12-segment arc, alpha ramp head→tail (brand orange → cream).
    int cx = w / 2, cy = S(168);
    for (int k = 0; k < 12; k++)
        DrawSpinSegment(mem, cx, cy, S(15), S(9), (double)(g_angle - k * 18),
                        g_segPens[k]);

    SelectObject(mem, fSub);
    SetTextColor(mem, COL_SUB);
    SetRect(&tr, S(30), S(206), w - S(30), h - S(10));
    DrawTextW(mem,
              L"First launch takes about a minute while Windows prepares the app.",
              -1, &tr, DT_CENTER | DT_WORDBREAK | DT_TOP);

    SelectObject(mem, oldFont);
    DeleteObject(fTitle);
    DeleteObject(fMsg);
    DeleteObject(fSub);

    BitBlt(dc, 0, 0, w, h, mem, 0, 0, SRCCOPY);
    SelectObject(mem, oldBmp);
    DeleteObject(bmp);
    DeleteDC(mem);
    EndPaint(hwnd, &ps);
}

// ---- window procedure --------------------------------------------------------

static void SetOpacity(BYTE a)
{
    SetLayeredWindowAttributes(g_hwnd, 0, a, LWA_ALPHA);
}

static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    switch (msg)
    {
    case WM_TIMER:
    {
        // Spinner advances ~6 deg/frame → one revolution about every second.
        g_angle = (g_angle + 6) % 360;

        // Fade-in runs from the very first tick and never waits on the app
        // launch (which happens on a worker thread — see LaunchWorker).
        if (!g_fadingOut && g_alpha < 255)
        {
            g_alpha = (BYTE)min(255, g_alpha + 24);
            SetOpacity(g_alpha);
        }

        LONG st = InterlockedCompareExchange(&g_launchState, 0, 0);
        if (st == 0)
        {
            // Second tick: kick off the worker that CreateProcess()es the app.
            static int s_warmup = 0;
            if (++s_warmup >= 2)
            {
                InterlockedExchange(&g_launchState, 1);
                HANDLE h = CreateThread(NULL, 0, LaunchWorker, NULL, 0, NULL);
                if (h) CloseHandle(h);
                else InterlockedExchange(&g_launchState, 3);  // can't even spawn the worker
            }
        }
        else if (!g_fadingOut)
        {
            if (st == 3)
            {
                // App could not be started at all — nothing to wait for;
                // the error dialog is shown after the window closes.
                g_exitCode = 2;
                g_fadingOut = true;
            }
            else if (st == 2)
            {
                // ~100 ms cadence: is the app up yet, or gone for good?
                static int s_phase = 0;
                if (++s_phase >= 6)
                {
                    s_phase = 0;
                    bool exited = WaitForSingleObject(g_hProcess, 0) == WAIT_OBJECT_0;
                    // Exited without ever showing a window = single-instance
                    // forward (or a headless failure) — nothing left to cover.
                    // A visible window = handoff complete, step aside.
                    if (exited || AppWindowIsUp() ||
                        GetTickCount() - g_startTick > kMaxWaitMs)
                        g_fadingOut = true;
                }
            }
        }

        if (g_fadingOut)
        {
            if (g_alpha > 24)
            {
                g_alpha = (BYTE)(g_alpha - 24);           // gentle fade-out
                SetOpacity(g_alpha);
            }
            else
            {
                DestroyWindow(hwnd);
                return 0;
            }
        }

        InvalidateRect(hwnd, NULL, FALSE);
        return 0;
    }

    case WM_PAINT:
        Paint(hwnd);
        return 0;

    case WM_ERASEBKGND:
        return 1;

    case WM_NCHITTEST:  // the card is draggable (no caption)
    {
        LRESULT hit = DefWindowProcW(hwnd, msg, wp, lp);
        return hit == HTCLIENT ? HTCAPTION : hit;
    }

    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

static void CreateSpinnerPens()
{
    for (int k = 0; k < 12; k++)
    {
        // k=0 is the head (full brand orange), k=11 fades into the cream bg.
        double f = (11.0 - k) / 11.0;
        f = f * f;  // ease the ramp so the tail dissolves smoothly
        BYTE r = (BYTE)(GetRValue(COL_BG) + (GetRValue(COL_ACCENT) - GetRValue(COL_BG)) * f + 0.5);
        BYTE g = (BYTE)(GetGValue(COL_BG) + (GetGValue(COL_ACCENT) - GetGValue(COL_BG)) * f + 0.5);
        BYTE b = (BYTE)(GetBValue(COL_BG) + (GetBValue(COL_ACCENT) - GetBValue(COL_BG)) * f + 0.5);
        g_segPens[k] = CreatePen(PS_SOLID, S(4), RGB(r, g, b));
    }
}

static bool ShowLauncherWindow()
{
    g_dpi = GetDeviceCaps(GetDC(NULL), LOGPIXELSY);

    WNDCLASSW wc = {};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = g_inst;
    wc.lpszClassName = L"FileLoreLauncher";
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    RegisterClassW(&wc);

    CreateSpinnerPens();

    int w = S(kWinW), h = S(kWinH);
    RECT work;
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    int x = work.left + (work.right - work.left - w) / 2;
    int y = work.top + (work.bottom - work.top - h) / 2;

    g_hwnd = CreateWindowExW(
        WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW,
        wc.lpszClassName, L"FileLore", WS_POPUP,
        x, y, w, h, NULL, NULL, g_inst, NULL);
    if (!g_hwnd) return false;

    HRGN rgn = CreateRoundRectRgn(0, 0, w + 1, h + 1, S(16), S(16));
    SetWindowRgn(g_hwnd, rgn, TRUE);   // system owns the region now

    g_alpha = 0;
    SetOpacity(0);
    ShowWindow(g_hwnd, SW_SHOW);
    UpdateWindow(g_hwnd);
    SetTimer(g_hwnd, kTimerId, kTickMs, NULL);
    return true;
}

// ---- entry point --------------------------------------------------------------

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE, LPWSTR, int)
{
    g_inst = inst;
    SetProcessDPIAware();

    int argc = 0;
    LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv) return 2;

    // Headless pass-throughs: never show the launcher window for modes that
    // can't produce one themselves.
    //   --tray            autostart at login: silent by design; the tray app
    //                     keeps running, so don't wait on it either.
    //   --version / -v    prints the version and exits (diagnostics).
    //   --selftest        headless verification; propagate the exit code.
    //   --veloapp-*       Velopack lifecycle hooks (0.8.0+: the launcher is
    //                     Velopack's --mainExe). Forward headlessly and
    //                     propagate the exit code: the WPF app runs the hook
    //                     (registry verb / Run key refresh, legacy cleanup)
    //                     and exits within Velopack's 15-30 s budget.
    bool tray = HasFlag(argc, argv, L"--tray");
    bool headless = HasFlag(argc, argv, L"--version") ||
                    HasFlag(argc, argv, L"-v") ||
                    HasFlag(argc, argv, L"--selftest") ||
                    HasArgWithPrefix(argc, argv, L"--veloapp-");
    LocalFree(argv);

    if (tray)
    {
        if (!LaunchRealApp()) { ShowLaunchError(); return 2; }
        CloseHandle(g_hProcess);
        return 0;
    }

    if (headless)
    {
        if (!LaunchRealApp()) { ShowLaunchError(); return 2; }
        WaitForSingleObject(g_hProcess, INFINITE);
        DWORD code = 1;
        GetExitCodeProcess(g_hProcess, &code);
        CloseHandle(g_hProcess);
        return (int)code;
    }

    if (!ShowLauncherWindow())
    {
        // Window failed — still babysit the child so a stuck process doesn't
        // leave the user staring at nothing without explanation.
        if (LaunchRealApp())
        {
            WaitForSingleObject(g_hProcess, INFINITE);
            CloseHandle(g_hProcess);
        }
        else ShowLaunchError();
        return 0;
    }

    // The window is up; the app itself is launched by a worker thread kicked
    // off from the second timer tick (see WM_TIMER / LaunchWorker), so
    // Defender's first-scan of the big exe can never stall our first paint.

    MSG msg;
    while (GetMessageW(&msg, NULL, 0, 0) > 0)
    {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    if (g_hProcess) CloseHandle(g_hProcess);
    for (int k = 0; k < 12; k++)
        if (g_segPens[k]) DeleteObject(g_segPens[k]);
    if (g_exitCode == 2) ShowLaunchError();
    return g_exitCode;
}
