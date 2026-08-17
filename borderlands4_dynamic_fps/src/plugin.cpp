#include <windows.h>

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "mod_loader_api.h"
#include "streamline_api.h"

namespace rtss {
bool set_fps_limit(uint32_t fps, char* message, size_t message_size);
}

namespace {

constexpr uint32_t FRAME_GENERATION_OFF_FPS = 60;
constexpr uint32_t FRAME_GENERATION_ON_FPS = 120;
constexpr DWORD CHECK_INTERVAL_MS = 300;
constexpr uint32_t MAIN_VIEWPORT = 0;

mod_log_fn g_log{};

template <typename T>
void load_export(HMODULE module, const char* name, T& destination) {
    const auto address = GetProcAddress(module, name);
    static_assert(sizeof(destination) == sizeof(address));
    memcpy(&destination, &address, sizeof(destination));
}

void log(const char* message) {
    if (g_log != nullptr) {
        g_log(message);
    }
}

streamline::DLSSGGetState initialize_dlssg() {
    static streamline::DLSSGGetState get_state{};
    static bool failure_logged = false;
    if (get_state != nullptr) {
        return get_state;
    }

    const HMODULE module = GetModuleHandleW(L"sl.interposer.dll");
    streamline::GetFeatureFunction get_feature_function{};
    if (module != nullptr) {
        load_export(module, "slGetFeatureFunction", get_feature_function);
    }

    void* address{};
    const bool initialized =
        get_feature_function != nullptr &&
        get_feature_function(streamline::FEATURE_DLSS_G,
                             "slDLSSGGetState", address) ==
            streamline::Result::ok &&
        address != nullptr;
    if (!initialized) {
        if (!failure_logged) {
            failure_logged = true;
            log("[BL4 Dynamic FPS] NVIDIA DLSS-G is not initialized");
        }
        return nullptr;
    }

    static_assert(sizeof(get_state) == sizeof(address));
    memcpy(&get_state, &address, sizeof(get_state));
    log("[BL4 Dynamic FPS] NVIDIA DLSS-G initialized");
    return get_state;
}

bool is_frame_generation_active() {
    const streamline::DLSSGGetState get_state = initialize_dlssg();
    if (get_state == nullptr) {
        return false;
    }

    streamline::ViewportHandle viewport{MAIN_VIEWPORT};
    streamline::DLSSGState state;
    return get_state(viewport, state, nullptr) == streamline::Result::ok &&
           state.status == 0 && state.num_frames_actually_presented > 1;
}

DWORD WINAPI worker(void*) {
    log("[BL4 Dynamic FPS] Initialized");
    uint32_t current_fps = UINT32_MAX;
    bool rtss_warning_logged = false;

    for (;;) {
        const uint32_t target_fps = is_frame_generation_active()
                                        ? FRAME_GENERATION_ON_FPS
                                        : FRAME_GENERATION_OFF_FPS;
        if (target_fps != current_fps) {
            char message[256]{};
            if (rtss::set_fps_limit(target_fps, message, sizeof(message))) {
                current_fps = target_fps;
                rtss_warning_logged = false;
                log(message);
            } else if (!rtss_warning_logged) {
                rtss_warning_logged = true;
                log(message);
            }
        }
        Sleep(CHECK_INTERVAL_MS);
    }
}

} // namespace

extern "C" __declspec(dllexport) void MOD_LOADER_CALL
on_mod_load(mod_log_fn logger) {
    g_log = logger;
    const HANDLE thread = CreateThread(nullptr, 0, worker, nullptr, 0, nullptr);
    if (thread != nullptr) {
        CloseHandle(thread);
    } else {
        log("[BL4 Dynamic FPS] Failed to create worker thread");
    }
}

extern "C" BOOL WINAPI DllMain(HMODULE module, DWORD reason, void*) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(module);
    }
    return TRUE;
}
