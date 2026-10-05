#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <filesystem>
#include <iterator>
#include <string>
#include "MinHook.h"
#include "mod_loader_api.h"

namespace fs = std::filesystem;
static HMODULE g_self;
static mod_log_fn g_log;
static decltype(&SetWindowPos) g_set_window_pos;

static void log(const char* text) {
    if (g_log) g_log(text);
}

static bool own_window(HWND window) {
    DWORD pid = 0;
    GetWindowThreadProcessId(window, &pid);
    return pid == GetCurrentProcessId();
}

static BOOL WINAPI set_window_pos(HWND window, HWND after, int x, int y,
                                int width, int height, UINT flags) {
    if (after == HWND_TOPMOST && !(flags & SWP_NOZORDER) && own_window(window))
        after = HWND_NOTOPMOST;
    return g_set_window_pos(window, after, x, y, width, height, flags);
}

static BOOL CALLBACK clear_existing_topmost(HWND window, LPARAM) {
    if (own_window(window) && (GetWindowLongPtrW(window, GWL_EXSTYLE) & WS_EX_TOPMOST))
        g_set_window_pos(window, HWND_NOTOPMOST, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_ASYNCWINDOWPOS);
    return TRUE;
}

static bool install_window_hook() {
    const MH_STATUS status = MH_Initialize();
    if (status != MH_OK && status != MH_ERROR_ALREADY_INITIALIZED) {
        log("beatlink_auto: MinHook initialization failed");
        return false;
    }
    void* target = nullptr;
    if (MH_CreateHookApiEx(L"user32", "SetWindowPos",
            reinterpret_cast<void*>(&set_window_pos),
            reinterpret_cast<void**>(&g_set_window_pos), &target) != MH_OK) {
        log("beatlink_auto: failed to create SetWindowPos hook");
        return false;
    }
    if (MH_EnableHook(target) != MH_OK) {
        log("beatlink_auto: failed to enable SetWindowPos hook; retrying");
        MH_RemoveHook(target);
        return false;
    }
    // Handle windows created before the hook, once. Subsequent calls are hooked.
    EnumWindows(clear_existing_topmost, 0);
    log("beatlink_auto: SetWindowPos topmost hook installed");
    return true;
}

static fs::path module_path(HMODULE module) {
    std::wstring path(32768, L'\0');
    const DWORD length = GetModuleFileNameW(module, path.data(),
                                           static_cast<DWORD>(path.size()));
    if (!length || length >= path.size()) return {};
    path.resize(length);
    return fs::path(path);
}

static void start_connect() {
    const fs::path self = module_path(g_self);
    if (self.empty()) { log("beatlink_auto: cannot locate config.ini"); return; }
    const fs::path ini = self.parent_path() / L"config.ini";
    wchar_t configured[4096]{};
    GetPrivateProfileStringW(L"beatlink_auto", L"path", L"", configured,
        static_cast<DWORD>(std::size(configured)), ini.c_str());
    if (!configured[0]) {
        log("beatlink_auto: helper path not configured");
        return;
    }
    std::wstring command = L"\"" + std::wstring(configured) + L"\" " +
                           std::to_wstring(GetCurrentProcessId());
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(configured, command.data(), nullptr, nullptr, FALSE,
                        CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process)) {
        log("beatlink_auto: failed to start Connect helper");
        return;
    }
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    log("beatlink_auto: Connect helper started");
}

static DWORD WINAPI worker(void*) {
    start_connect();
    while (!install_window_hook()) {
        Sleep(1000);
    }
    return 0;
}

extern "C" __declspec(dllexport) void MOD_LOADER_CALL on_mod_load(mod_log_fn logger) {
    g_log = logger;
    const HANDLE thread = CreateThread(nullptr, 0, worker, nullptr, 0, nullptr);
    if (thread) CloseHandle(thread);
    else log("beatlink_auto: failed to create worker thread");
}

BOOL WINAPI DllMain(HINSTANCE self, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_self = self;
        DisableThreadLibraryCalls(self);
    }
    return TRUE;
}
