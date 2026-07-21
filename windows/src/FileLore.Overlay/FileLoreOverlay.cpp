// FileLoreOverlay — IShellIconOverlayIdentifier for FileLore.
//
// A tiny no-ATL in-proc COM server (~200 lines) that makes Windows Explorer
// paint a small FileLore badge on files carrying a note. A note lives in the
// NTFS alternate data stream ":filelore.note:$DATA" (see NoteStore.cs), so
// IsMemberOf() replicates the FindFirstStreamW check from NoteIndex.cs
// (HasNoteStream) in native code — no .NET, statically linked CRT, so the
// DLL has zero runtime dependencies inside explorer.exe.
//
// Registration (opt-in, one-time ADMIN step — the ShellIconOverlayIdentifiers
// enumeration key is HKLM-only):
//   HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\
//       ShellIconOverlayIdentifiers\ FileLore   <-- ONE LEADING SPACE
//       (default) = {CLSID}
// The leading space is the alphabetical-priority convention OneDrive uses so
// the overlay survives the system-wide ~15-overlay limit. GetPriority()
// returns 0 for the same reason. tools\Register-FileLoreOverlay.cmd writes
// the key elevated and then calls SHChangeNotify(SHCNE_ASSOCCHANGED).
//
// Refresh: the app calls SHChangeNotify(SHCNE_UPDATEITEM) on every note
// save/delete (ShellBadgeRefresh.cs, hooked to NoteEvents), so badges appear
// and disappear without a manual folder refresh.
//
// Build: see build-overlay.cmd in this folder (x64 + ARM64, /MT, no ATL).

#include <windows.h>
#include <shlobj.h>
#include <stdio.h>
#include <new>

// {7F3C1A2E-9B4D-4E5F-A6C7-1D2E3F4A5B6C}  FileLore icon overlay handler
static const CLSID CLSID_FileLoreOverlay =
    { 0x7f3c1a2e, 0x9b4d, 0x4e5f, { 0xa6, 0xc7, 0x1d, 0x2e, 0x3f, 0x4a, 0x5b, 0x6c } };

static const WCHAR kOverlayKeyName[] = L" FileLore"; // ONE LEADING SPACE — priority convention
static const WCHAR kNoteStreamSuffix[] = L":filelore.note:$DATA";

static HMODULE g_hModule = nullptr;
static LONG    g_cLock   = 0;

// Resolve our own icon resource (IDI=1, embedded from app.ico) as the overlay
// icon. GetOverlayInfo is called once per Explorer process.
static void ModulePath(PWCHAR buf, DWORD cch)
{
    DWORD n = GetModuleFileNameW(g_hModule, buf, cch);
    if (n == 0 || n >= cch) { buf[0] = L'\0'; }
}

class CFileLoreOverlay : public IShellIconOverlayIdentifier
{
public:
    // ---- IUnknown ----------------------------------------------------------
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override
    {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IShellIconOverlayIdentifier)
        {
            *ppv = static_cast<IShellIconOverlayIdentifier*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override  { return (ULONG)InterlockedIncrement(&_cRef); }
    STDMETHODIMP_(ULONG) Release() override
    {
        LONG n = InterlockedDecrement(&_cRef);
        if (n == 0) delete this;
        return (ULONG)n;
    }

    // ---- IShellIconOverlayIdentifier --------------------------------------
    STDMETHODIMP IsMemberOf(PCWSTR pwszPath, DWORD dwAttrib) override
    {
        // Explorer calls this for EVERY item in EVERY viewed folder — keep it
        // fast and never let anything escape across the COM boundary.
        if (!pwszPath || (dwAttrib & FILE_ATTRIBUTE_DIRECTORY)) return S_FALSE;

        wchar_t target[MAX_PATH * 2 + 8];
        size_t len = wcsnlen_s(pwszPath, MAX_PATH * 2);
        if (len == 0) return S_FALSE;
        const wchar_t* path = pwszPath;

        // \\?\ prefix for long paths (mirrors NoteIndex.ExtendedPath).
        if (len > 250 && wcsncmp(pwszPath, L"\\\\?\\", 4) != 0)
        {
            if (len + 5 > ARRAYSIZE(target)) return S_FALSE;
            wcscpy_s(target, L"\\\\?\\");
            wcscat_s(target, ARRAYSIZE(target), pwszPath);
            path = target;
        }

        WIN32_FIND_STREAM_DATA fsd;
        HANDLE h = FindFirstStreamW(path, FindStreamInfoStandard, &fsd, 0);
        if (h == INVALID_HANDLE_VALUE) return S_FALSE;
        BOOL found = FALSE;
        do
        {
            // cStreamName looks like ":filelore.note:$DATA"
            if (_wcsicmp(fsd.cStreamName, kNoteStreamSuffix) == 0) { found = TRUE; break; }
        } while (FindNextStreamW(h, &fsd));
        FindClose(h);
        return found ? S_OK : S_FALSE;
    }

    STDMETHODIMP GetOverlayInfo(PWSTR pwszIconFile, int cchMax, int* pIndex, DWORD* pdwFlags) override
    {
        if (!pwszIconFile || !pIndex || !pdwFlags || cchMax <= 0) return E_POINTER;
        ModulePath(pwszIconFile, (DWORD)cchMax);
        if (pwszIconFile[0] == L'\0') return E_FAIL;
        *pIndex = 0;                       // first icon in the DLL
        *pdwFlags = ISIOI_ICONFILE | ISIOI_ICONINDEX;
        return S_OK;
    }

    STDMETHODIMP GetPriority(int* pPriority) override
    {
        if (!pPriority) return E_POINTER;
        *pPriority = 0;                    // highest — the 15-overlay limit is real
        return S_OK;
    }

private:
    LONG _cRef = 1;
};

class COverlayFactory : public IClassFactory
{
public:
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override
    {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IClassFactory) { *ppv = this; AddRef(); return S_OK; }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override  { return 2; }  // static lifetime
    STDMETHODIMP_(ULONG) Release() override { return 1; }
    STDMETHODIMP CreateInstance(IUnknown* pOuter, REFIID riid, void** ppv) override
    {
        if (!ppv) return E_POINTER;
        *ppv = nullptr;
        if (pOuter) return CLASS_E_NOAGGREGATION;
        CFileLoreOverlay* p = new (std::nothrow) CFileLoreOverlay();
        if (!p) return E_OUTOFMEMORY;
        HRESULT hr = p->QueryInterface(riid, ppv);
        p->Release();
        return hr;
    }
    STDMETHODIMP LockServer(BOOL fLock) override
    {
        if (fLock) InterlockedIncrement(&g_cLock); else InterlockedDecrement(&g_cLock);
        return S_OK;
    }
};

static COverlayFactory g_Factory;

extern "C" {

BOOL WINAPI DllMain(HINSTANCE hInst, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        g_hModule = hInst;
        DisableThreadLibraryCalls(hInst);
    }
    return TRUE;
}

HRESULT STDAPICALLTYPE DllGetClassObject(REFCLSID rclsid, REFIID riid, LPVOID* ppv)
{
    if (rclsid != CLSID_FileLoreOverlay) return CLASS_E_CLASSNOTAVAILABLE;
    return g_Factory.QueryInterface(riid, ppv);
}

HRESULT STDAPICALLTYPE DllCanUnloadNow()
{
    return g_cLock == 0 ? S_OK : S_FALSE;
}

// Self-registration helpers — used by regsvr32 only if someone calls it
// directly; the supported path is Register-FileLoreOverlay.cmd which writes
// the keys itself (HKCR CLSID + HKLM overlay key with the leading space).
static HRESULT SetRegKey(HKEY root, PCWSTR sub, PCWSTR name, PCWSTR value)
{
    HKEY h;
    if (RegCreateKeyExW(root, sub, 0, nullptr, 0, KEY_WRITE, nullptr, &h, nullptr) != ERROR_SUCCESS)
        return E_FAIL;
    LONG rc = RegSetValueExW(h, name, 0, REG_SZ,
        (const BYTE*)value, (DWORD)((wcslen(value) + 1) * sizeof(WCHAR)));
    RegCloseKey(h);
    return rc == ERROR_SUCCESS ? S_OK : E_FAIL;
}

HRESULT STDAPICALLTYPE DllRegisterServer()
{
    wchar_t path[MAX_PATH * 2];
    ModulePath(path, ARRAYSIZE(path));
    wchar_t clsid[64];
    if (!StringFromGUID2(CLSID_FileLoreOverlay, clsid, ARRAYSIZE(clsid))) return E_FAIL;

    wchar_t sub[256];
    swprintf_s(sub, L"SOFTWARE\\Classes\\CLSID\\%s", clsid);
    if (FAILED(SetRegKey(HKEY_LOCAL_MACHINE, sub, nullptr, L"FileLore icon overlay"))) return E_FAIL;
    wchar_t inproc[320];
    swprintf_s(inproc, L"%s\\InprocServer32", sub);
    if (FAILED(SetRegKey(HKEY_LOCAL_MACHINE, inproc, nullptr, path))) return E_FAIL;
    if (FAILED(SetRegKey(HKEY_LOCAL_MACHINE, inproc, L"ThreadingModel", L"Apartment"))) return E_FAIL;

    wchar_t overlay[384];
    swprintf_s(overlay,
        L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\ShellIconOverlayIdentifiers\\%s",
        kOverlayKeyName);
    return SetRegKey(HKEY_LOCAL_MACHINE, overlay, nullptr, clsid);
}

HRESULT STDAPICALLTYPE DllUnregisterServer()
{
    wchar_t clsid[64];
    if (!StringFromGUID2(CLSID_FileLoreOverlay, clsid, ARRAYSIZE(clsid))) return E_FAIL;
    wchar_t sub[256];
    swprintf_s(sub, L"SOFTWARE\\Classes\\CLSID\\%s\\InprocServer32", clsid);
    RegDeleteKeyW(HKEY_LOCAL_MACHINE, sub);
    swprintf_s(sub, L"SOFTWARE\\Classes\\CLSID\\%s", clsid);
    RegDeleteKeyW(HKEY_LOCAL_MACHINE, sub);

    wchar_t overlay[384];
    swprintf_s(overlay,
        L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\ShellIconOverlayIdentifiers\\%s",
        kOverlayKeyName);
    RegDeleteKeyW(HKEY_LOCAL_MACHINE, overlay);
    return S_OK;
}

} // extern "C"
