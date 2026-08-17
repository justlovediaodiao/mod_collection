#include <windows.h>

#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <wchar.h>

#include "mod_loader_api.h"

namespace rtss {
bool set_fps_limit(uint32_t fps, char* message, size_t message_size);
}

namespace {

constexpr uint32_t MENU_FPS = 60;
constexpr uint32_t GAMEPLAY_FPS = 120;
constexpr DWORD CHECK_INTERVAL_MS = 300;

constexpr wchar_t MENU_OPEN_FUNCTION[] =
    L"/Game/UI/Scripts/ui_script_menu_base.ui_script_menu_base_C:MenuOpen";
constexpr wchar_t MENU_CLOSE_FUNCTION[] =
    L"/Game/UI/Scripts/ui_script_menu_base.ui_script_menu_base_C:MenuClose";
constexpr wchar_t HOOK_ID[] = L"borderlands4_dynamic_fps";

using IsSdkInitialized = bool (*)();

struct CallbackInner;

struct CallbackVTable {
    void (*destroy)(CallbackInner*);
    bool (*call)(CallbackInner*, void*);
};

struct CallbackInner {
    volatile const CallbackVTable* vtable;
    LONG menu_open;
};

struct DLLSafeCallback {
    CallbackInner* inner;
};

using AddHook = bool (*)(const wchar_t* function, size_t function_size,
                         uint8_t type, const wchar_t* identifier,
                         size_t identifier_size, DLLSafeCallback* callback);

struct PluginState {
    mod_log_fn log{};
    volatile LONG menu_open{1};
    uint32_t current_fps{UINT32_MAX};
    bool rtss_warning_logged{};
};

PluginState g_state;

template <typename T>
void load_export(HMODULE module, const char* name, T& destination) {
    const auto address = GetProcAddress(module, name);
    static_assert(sizeof(destination) == sizeof(address));
    memcpy(&destination, &address, sizeof(destination));
}

void log(const wchar_t* message) {
    if (g_state.log != nullptr) {
        g_state.log(message);
    }
}

void log(const char* message) {
    wchar_t wide_message[256]{};
    if (MultiByteToWideChar(CP_ACP, 0, message, -1, wide_message,
                            static_cast<int>(sizeof(wide_message) /
                                             sizeof(wide_message[0]))) > 0) {
        log(wide_message);
    }
}

HMODULE load_unrealsdk() {
    wchar_t path[MAX_PATH]{};
    const DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) {
        return nullptr;
    }

    wchar_t* filename = wcsrchr(path, L'\\');
    if (filename == nullptr) {
        return nullptr;
    }
    ++filename;

    constexpr wchar_t relative_path[] = L"Plugins\\unrealsdk.dll";
    const size_t remaining = MAX_PATH - static_cast<size_t>(filename - path);
    if (wcslen(relative_path) + 1 > remaining) {
        return nullptr;
    }
    wcscpy_s(filename, remaining, relative_path);
    return LoadLibraryW(path);
}

void destroy_callback(CallbackInner*) {}

bool run_callback(CallbackInner* callback, void*) {
    InterlockedExchange(&g_state.menu_open, callback->menu_open);
    return false;
}

const CallbackVTable CALLBACK_VTABLE = {destroy_callback, run_callback};
CallbackInner OPEN_CALLBACK = {&CALLBACK_VTABLE, 1};
CallbackInner CLOSE_CALLBACK = {&CALLBACK_VTABLE, 0};

bool add_menu_hook(AddHook add_hook, const wchar_t* function,
                   CallbackInner* callback) {
    DLLSafeCallback wrapper{callback};
    return add_hook(function, wcslen(function), 0, HOOK_ID,
                    (sizeof(HOOK_ID) / sizeof(HOOK_ID[0])) - 1, &wrapper);
}

DWORD WINAPI worker(void*) {
    const HMODULE sdk = load_unrealsdk();
    if (sdk == nullptr) {
        log(L"[BL4 Dynamic FPS] Failed to load Plugins\\unrealsdk.dll");
        return 1;
    }

    IsSdkInitialized is_sdk_initialized{};
    AddHook add_hook{};
    load_export(sdk, "_unrealsdk_export__is_initialized",
                is_sdk_initialized);
    load_export(sdk, "_unrealsdk_export__add_hook", add_hook);
    if (is_sdk_initialized == nullptr || add_hook == nullptr) {
        log(L"[BL4 Dynamic FPS] Incompatible unrealsdk.dll");
        return 1;
    }

    while (!is_sdk_initialized()) {
        Sleep(CHECK_INTERVAL_MS);
    }

    if (!add_menu_hook(add_hook, MENU_OPEN_FUNCTION, &OPEN_CALLBACK) ||
        !add_menu_hook(add_hook, MENU_CLOSE_FUNCTION, &CLOSE_CALLBACK)) {
        log(L"[BL4 Dynamic FPS] Failed to install menu hooks");
        return 1;
    }

    log(L"[BL4 Dynamic FPS] Initialized");

    for (;;) {
        const bool menu_open =
            InterlockedCompareExchange(&g_state.menu_open, 0, 0) != 0;
        const uint32_t target_fps = menu_open ? MENU_FPS : GAMEPLAY_FPS;
        if (target_fps != g_state.current_fps) {
            char message[256]{};
            if (rtss::set_fps_limit(target_fps, message, sizeof(message))) {
                g_state.current_fps = target_fps;
                g_state.rtss_warning_logged = false;
                log(message);
            } else if (!g_state.rtss_warning_logged) {
                g_state.rtss_warning_logged = true;
                log(message);
            }
        }
        Sleep(CHECK_INTERVAL_MS);
    }
}

} // namespace

extern "C" __declspec(dllexport) void MOD_LOADER_CALL
on_mod_load(mod_log_fn logger) {
    g_state.log = logger;
    const HANDLE thread = CreateThread(nullptr, 0, worker, nullptr, 0, nullptr);
    if (thread != nullptr) {
        CloseHandle(thread);
    } else {
        log(L"[BL4 Dynamic FPS] Failed to create worker thread");
    }
}

extern "C" BOOL WINAPI DllMain(HMODULE module, DWORD reason, void*) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(module);
    }
    return TRUE;
}
