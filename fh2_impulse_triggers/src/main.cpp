#include "mod_loader_api.h"

#include <windows.h>
#include <roapi.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Gaming.Input.h>

#include <cstdio>
#include <cstring>

namespace {

using winrt::Windows::Gaming::Input::Gamepad;

mod_log_fn g_log = nullptr;

void log(const char* message) {
    if (g_log) {
        g_log(message);
    }
}

struct GameVibration {
    float left;
    float right;
    float left_trigger;
    float right_trigger;
};
static_assert(sizeof(GameVibration) == 16);

using VibrationSetter = HRESULT(WINAPI*)(void*, const GameVibration*);
VibrationSetter g_original_setter = nullptr;

BYTE* find_aob(BYTE* base, const BYTE* pattern, size_t length, bool executable) {
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    const auto* pe = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
    const auto* section = IMAGE_FIRST_SECTION(pe);
    for (WORD index = 0; index < pe->FileHeader.NumberOfSections; ++index, ++section) {
        const DWORD flags = section->Characteristics;
        if ((flags & IMAGE_SCN_MEM_READ) == 0 ||
            ((flags & IMAGE_SCN_MEM_EXECUTE) != 0) != executable ||
            (!executable && (flags & IMAGE_SCN_MEM_WRITE) != 0)) {
            continue;
        }
        BYTE* begin = base + section->VirtualAddress;
        const size_t size = section->Misc.VirtualSize;
        if (size < length) {
            continue;
        }
        for (size_t offset = 0; offset <= size - length; ++offset) {
            if (std::memcmp(begin + offset, pattern, length) == 0) {
                return begin + offset;
            }
        }
    }
    return nullptr;
}

HRESULT WINAPI capture_vibration(void* controller, const GameVibration* value) {
    if (!value) {
        return g_original_setter(controller, value);
    }
    {
        // Keep WinRT initialized for this calling thread's use of the mod.
        thread_local const HRESULT initialization = [] {
            HRESULT result = RoInitialize(RO_INIT_MULTITHREADED);
            if (result == RPC_E_CHANGED_MODE) {
                result = RoInitialize(RO_INIT_SINGLETHREADED);
            }
            return result;
        }();
        if (SUCCEEDED(initialization)) {
            thread_local Gamepad gamepad{nullptr};
            try {
                if (!gamepad) {
                    const auto gamepads = Gamepad::Gamepads();
                    if (gamepads.Size() > 0) {
                        gamepad = gamepads.GetAt(0);
                    }
                }
            } catch (...) {
            }

            if (gamepad) {
                try {
                    gamepad.Vibration({value->left, value->right,
                                       value->left_trigger, value->right_trigger});
                } catch (...) {
                    // Reacquire next time, without switching this call to the original function.
                    gamepad = nullptr;
                }
                return S_OK;
            }
        }
    }
    return g_original_setter(controller, value);
}

const char* install_vibration_hook() {
    auto* base = reinterpret_cast<BYTE*>(GetModuleHandleW(nullptr));
    constexpr BYTE setter_aob[]{0x48, 0x8b, 0xc4, 0x48, 0x89, 0x58, 0x08, 0x57,
                                0x48, 0x81, 0xec, 0xb0, 0, 0, 0};
    BYTE* setter = find_aob(base, setter_aob, sizeof(setter_aob), true);
    if (!setter) {
        return "vibration function AOB not found";
    }
    BYTE* vtable_slot = find_aob(base, reinterpret_cast<const BYTE*>(&setter), sizeof(setter), false);
    if (!vtable_slot) {
        return "vibration vtable slot not found";
    }
    g_original_setter = reinterpret_cast<VibrationSetter>(setter);

    auto* slot = reinterpret_cast<void**>(vtable_slot);
    DWORD old_protection;
    if (!VirtualProtect(slot, sizeof(void*), PAGE_READWRITE, &old_protection)) {
        return "failed to make the vibration hook writable";
    }
    *slot = reinterpret_cast<void*>(&capture_vibration);
    DWORD ignored;
    VirtualProtect(slot, sizeof(void*), old_protection, &ignored);
    return nullptr;
}

} // namespace

extern "C" __declspec(dllexport) void MOD_LOADER_CALL on_mod_load(mod_log_fn logger) {
    g_log = logger;
    if (const char* error = install_vibration_hook()) {
        char message[256];
        std::snprintf(message, sizeof(message), "fh2_impulse_triggers: %s", error);
        log(message);
        return;
    }
    log("fh2_impulse_triggers: vibration hook installed");
}

BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(module);
    }
    return TRUE;
}
