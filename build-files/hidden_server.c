/*
 * NetArchServer.exe - window-less starter for NetArch Designer's server.
 *
 * The real server (NetArchServerCore.exe) is a console program, so Windows
 * opens a black cmd window whenever it starts. This small GUI-subsystem
 * program starts it instead:
 *
 *   NetArchServer.exe            -> runs "NetArchServerCore.exe serve" with NO window
 *   NetArchServer.exe serve ...  -> same, no window
 *   NetArchServer.exe <command>  -> CLI commands (status, migrate, backup, ...):
 *                                   output goes to the cmd window you typed it in,
 *                                   or to a new console if started without one.
 *
 * It waits for the server and returns its exit code, so the scheduled task's
 * "restart on failure" keeps working.
 */
#define WIN32_LEAN_AND_MEAN
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <wchar.h>

#define CORE_NAME L"NetArchServerCore.exe"

/* Return pointer to the arguments after the program name in a command line. */
static const wchar_t *skip_program_name(const wchar_t *p)
{
    if (*p == L'"') {
        p++;
        while (*p && *p != L'"') p++;
        if (*p == L'"') p++;
    } else {
        while (*p && *p != L' ' && *p != L'\t') p++;
    }
    while (*p == L' ' || *p == L'\t') p++;
    return p;
}

static int first_arg_is_serve(const wchar_t *args)
{
    if (*args == L'\0') return 1; /* no arguments -> serve */
    if (_wcsnicmp(args, L"serve", 5) == 0 &&
        (args[5] == L'\0' || args[5] == L' ' || args[5] == L'\t'))
        return 1;
    if (_wcsnicmp(args, L"\"serve\"", 7) == 0) return 1;
    return 0;
}

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE hPrev, PWSTR pCmd, int nShow)
{
    (void)hInst; (void)hPrev; (void)pCmd; (void)nShow;

    wchar_t self[MAX_PATH * 2];
    DWORD n = GetModuleFileNameW(NULL, self, (DWORD)(sizeof(self) / sizeof(self[0])));
    if (n == 0 || n >= sizeof(self) / sizeof(self[0])) return 3;
    wchar_t *slash = wcsrchr(self, L'\\');
    if (!slash) return 3;
    *(slash + 1) = L'\0';

    wchar_t core[MAX_PATH * 2];
    _snwprintf(core, sizeof(core) / sizeof(core[0]), L"%s%s", self, CORE_NAME);
    core[sizeof(core) / sizeof(core[0]) - 1] = L'\0';

    const wchar_t *args = skip_program_name(GetCommandLineW());
    int serve = first_arg_is_serve(args);

    if (GetFileAttributesW(core) == INVALID_FILE_ATTRIBUTES) {
        if (!serve)
            MessageBoxW(NULL, L"NetArchServerCore.exe was not found next to NetArchServer.exe.\n"
                              L"Please re-run the NetArch Designer setup.",
                        L"NetArch Designer", MB_ICONERROR | MB_OK);
        return 2;
    }

    size_t len = wcslen(core) + wcslen(args) + 16;
    wchar_t *cmd = (wchar_t *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, len * sizeof(wchar_t));
    if (!cmd) return 3;
    if (*args == L'\0')
        _snwprintf(cmd, len, L"\"%s\" serve", core);
    else
        _snwprintf(cmd, len, L"\"%s\" %s", core, args);

    DWORD flags;
    if (serve) {
        flags = CREATE_NO_WINDOW;              /* hidden console: no window at all */
    } else if (AttachConsole(ATTACH_PARENT_PROCESS)) {
        flags = 0;                              /* share the cmd/PowerShell window it was typed in */
    } else {
        flags = CREATE_NEW_CONSOLE;             /* double-clicked with arguments: show output */
    }

    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    ZeroMemory(&pi, sizeof(pi));
    si.cb = sizeof(si);

    if (!CreateProcessW(core, cmd, NULL, NULL, FALSE, flags, NULL, self, &si, &pi)) {
        if (!serve)
            MessageBoxW(NULL, L"Could not start NetArchServerCore.exe.", L"NetArch Designer",
                        MB_ICONERROR | MB_OK);
        return 4;
    }
    CloseHandle(pi.hThread);
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 1;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    return (int)code;
}
