#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <tlhelp32.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <iterator>
#include <limits>
#include <string>
#include <unordered_map>
#include <vector>

#include "mod_loader_api.h"

extern "C" {
void RoadieProcessorDetour();
void RoadieOuterExitDetour();
void RoadieSetRotationDetour();
void RoadieMovementTypeDetour();

void* g_processor_return{};
void* g_outer_return{};
void* g_set_rotation_return{};
void* g_movement_rotation_return{};
uint32_t g_roadie_tuning_class_id{};
}

namespace {

constexpr char TARGET_CLASS[] =
    "CamBridge_ViewProcessor_SpeedLimits_RoadieRun_C";
constexpr char ROADIE_TUNING_CLASS[] =
    "FairlightMovementContextRoadieRunTuning";

constexpr char PROCESSOR_EXIT_SIGNATURE[] =
    "C4 E2 E1 B9 D1 C5 FB 11 51 10 C5 F8 77 4C 8D 9C 24 20 01 00 00";
constexpr std::ptrdiff_t PROCESSOR_EXIT_OFFSET = 10;

constexpr char OUTER_EXIT_SIGNATURE[] =
    "48 8B CB C5 F8 77 E8 ?? ?? ?? ?? C5 F8 77 4C 8D 9C 24 B8 01 00 00";
constexpr std::ptrdiff_t OUTER_EXIT_OFFSET = 11;

constexpr char SET_ROTATION_SIGNATURE[] =
    "48 8B C4 48 89 58 08 57 48 81 EC F0 00 00 00 C5 F8 29 70 E8 "
    "C5 FB 10 72 10 C5 F8 29 78 D8 C5 FB 10 7A 08";

constexpr char PRIMARY_SET_SIGNATURE[] =
    "48 8B 06 48 8D 55 F7 48 8B CE FF 90 E8 07 00 00 48 8B CE "
    "E8 ?? ?? ?? ?? 48 85 C0";
constexpr std::ptrdiff_t PRIMARY_SET_RETURN_OFFSET = 16;

constexpr char LIMITED_SET_SIGNATURE[] =
    "48 8B 07 48 8D 54 24 20 C5 FB 11 54 24 28 48 8B CF C5 F8 77 "
    "FF 90 E8 07 00 00 C5 F8 28 74 24 60";
constexpr std::ptrdiff_t LIMITED_SET_RETURN_OFFSET = 26;

constexpr char NAME_POOL_SIGNATURE[] =
    "48 8D 1D ?? ?? ?? ?? 0F 1F 00 41 8B 04 24 8B C8 C1 E9 10 "
    "0F B7 C0";

constexpr char MOVEMENT_ROTATION_PUSH_SIGNATURE[] =
    "48 89 5C 24 08 57 48 83 EC 20 48 8B D9 E8 D2 63 35 FF "
    "48 8B F8 48 85 C0 74 29 "
    "48 8B CB E8 ?? ?? ?? ?? 48 8B C8 48 8B D8 E8 ?? ?? ?? ?? "
    "48 8D 8F 30 01 00 00 E8 ?? ?? ?? ?? 8A D0 48 8B CB "
    "E8 ?? ?? ?? ?? 48 8B 5C 24 30";
constexpr std::ptrdiff_t MOVEMENT_ROTATION_PUSH_OFFSET = 57;

constexpr std::array<uint8_t, 11> PROCESSOR_BYTES{
    0xC5, 0xF8, 0x77, 0x4C, 0x8D, 0x9C, 0x24, 0x20, 0x01, 0x00, 0x00};
constexpr std::array<uint8_t, 11> OUTER_BYTES{
    0xC5, 0xF8, 0x77, 0x4C, 0x8D, 0x9C, 0x24, 0xB8, 0x01, 0x00, 0x00};
constexpr std::array<uint8_t, 7> SET_ROTATION_BYTES{
    0x48, 0x8B, 0xC4, 0x48, 0x89, 0x58, 0x08};
constexpr std::array<uint8_t, 5> MOVEMENT_ROTATION_PUSH_BYTES{
    0x8A, 0xD0, 0x48, 0x8B, 0xCB};

struct Rotator {
    double pitch;
    double yaw;
    double roll;
};

struct ProcessorThreadState {
    bool processor_pending{};
    double raw_delta_yaw{};
    double limited_delta_yaw{};
};

struct ControlRotationState {
    bool primary_valid{};
    double primary_yaw{};
};

struct HookSite {
    uint8_t* address{};
    size_t length{};
    const uint8_t* expected{};
    void* detour{};
    uint8_t* relay{};
    int32_t displacement{};
};

struct ResolvedAddresses {
    uint8_t* name_pool{};
    uint8_t* processor_exit{};
    uint8_t* outer_exit{};
    uint8_t* set_rotation{};
    uint8_t* movement_rotation_push{};
    uintptr_t primary_set_return{};
    uintptr_t limited_set_return{};
};

// The processor wrapper and outer commit are a synchronous call chain, so this
// state belongs to the executing thread. Controller commits share state keyed
// by controller, allowing cross-thread pairing without mixing local players.
thread_local ProcessorThreadState g_processor_state{};
SRWLOCK g_control_rotation_lock = SRWLOCK_INIT;
std::unordered_map<void*, ControlRotationState> g_control_rotation_states{};
mod_log_fn g_log{};
ResolvedAddresses g_addresses{};
uint32_t g_target_class_id{};

void log(const char* message) {
    if (g_log != nullptr) {
        g_log(message);
    }
}

template <typename... Args>
void logf(const char* format, Args... args) {
    char message[512]{};
    std::snprintf(message, sizeof(message), format, args...);
    log(message);
}

bool readable(const void* pointer, size_t size) {
    MEMORY_BASIC_INFORMATION info{};
    if (VirtualQuery(pointer, &info, sizeof(info)) != sizeof(info) ||
        info.State != MEM_COMMIT || (info.Protect & PAGE_GUARD) != 0 ||
        (info.Protect & PAGE_NOACCESS) != 0) {
        return false;
    }
    const uintptr_t begin = reinterpret_cast<uintptr_t>(pointer);
    const uintptr_t region_end =
        reinterpret_cast<uintptr_t>(info.BaseAddress) + info.RegionSize;
    return size <= region_end - begin;
}

bool name_equals(uint8_t* pool, uint32_t id, const char* expected) {
    const uint32_t block_index = id >> 16;
    const uint32_t byte_offset = (id & 0xFFFFu) * 2u;
    if (block_index > 8191 || !readable(pool + 0x10 + block_index * 8, 8)) {
        return false;
    }
    auto* block = *reinterpret_cast<uint8_t**>(
        pool + 0x10 + static_cast<size_t>(block_index) * 8);
    if (!readable(block + byte_offset, 2)) {
        return false;
    }
    const uint16_t header =
        *reinterpret_cast<const uint16_t*>(block + byte_offset);
    const size_t length = header >> 6;
    const bool wide = (header & 1u) != 0;
    if (length != std::strlen(expected)) {
        return false;
    }
    const uint8_t* text = block + byte_offset + 2;
    if (!readable(text, length * (wide ? 2 : 1))) {
        return false;
    }
    for (size_t index = 0; index < length; ++index) {
        if (wide) {
            const uint16_t character =
                reinterpret_cast<const uint16_t*>(text)[index];
            if (character != static_cast<uint8_t>(expected[index])) {
                return false;
            }
        } else if (text[index] != static_cast<uint8_t>(expected[index])) {
            return false;
        }
    }
    return true;
}

bool find_name_id(uint8_t* pool, const char* wanted, uint32_t& result) {
    if (!readable(pool, 0x20)) {
        return false;
    }
    const uint32_t current_block =
        *reinterpret_cast<const uint32_t*>(pool + 0x08);
    const uint32_t current_cursor =
        *reinterpret_cast<const uint32_t*>(pool + 0x0C);
    if (current_block > 8191 || current_cursor < 2 ||
        current_cursor > 0x20000) {
        return false;
    }

    const size_t wanted_length = std::strlen(wanted);
    for (uint32_t block_index = 0; block_index <= current_block;
         ++block_index) {
        auto* block = *reinterpret_cast<uint8_t**>(
            pool + 0x10 + static_cast<size_t>(block_index) * 8);
        const size_t limit =
            block_index == current_block ? current_cursor : 0x20000;
        if (!readable(block, limit)) {
            return false;
        }
        size_t offset = 0;
        while (offset + 2 <= limit) {
            const uint16_t header =
                *reinterpret_cast<const uint16_t*>(block + offset);
            if (header == 0) {
                break;
            }
            const size_t length = header >> 6;
            const bool wide = (header & 1u) != 0;
            if (length == 0) {
                return false;
            }
            const size_t payload = length * (wide ? 2 : 1);
            const size_t entry_size = (2 + payload + 1) & ~size_t{1};
            if (offset + entry_size > limit) {
                break;
            }
            if (length == wanted_length) {
                const uint32_t id =
                    (block_index << 16) | static_cast<uint32_t>(offset >> 1);
                if (name_equals(pool, id, wanted)) {
                    result = id;
                    return true;
                }
            }
            offset += entry_size;
        }
    }
    return false;
}

const IMAGE_NT_HEADERS64* image_headers(uint8_t* base) {
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    return reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
}

std::vector<int> parse_pattern(const char* text) {
    const auto hex = [](char value) {
        return value <= '9' ? value - '0' : value - 'A' + 10;
    };
    std::vector<int> pattern;
    while (*text != '\0') {
        while (*text == ' ') {
            ++text;
        }
        if (*text == '\0') {
            break;
        }
        if (text[0] == '?' && text[1] == '?') {
            pattern.push_back(-1);
            text += 2;
            continue;
        }
        const int high = hex(text[0]);
        const int low = hex(text[1]);
        pattern.push_back((high << 4) | low);
        text += 2;
    }
    return pattern;
}

std::vector<uint8_t*> scan_executable(uint8_t* base,
                                      const char* signature) {
    std::vector<uint8_t*> matches;
    const auto* nt = image_headers(base);
    const std::vector<int> pattern = parse_pattern(signature);
    const IMAGE_SECTION_HEADER* section = IMAGE_FIRST_SECTION(nt);
    for (uint16_t index = 0; index < nt->FileHeader.NumberOfSections;
         ++index, ++section) {
        if ((section->Characteristics & IMAGE_SCN_MEM_EXECUTE) == 0) {
            continue;
        }
        const size_t virtual_size = section->Misc.VirtualSize;
        const size_t rva = section->VirtualAddress;
        if (virtual_size < pattern.size()) {
            continue;
        }
        const uint8_t* bytes = base + rva;
        for (size_t offset = 0; offset <= virtual_size - pattern.size();
             ++offset) {
            bool equal = true;
            for (size_t byte = 0; byte < pattern.size(); ++byte) {
                if (pattern[byte] >= 0 &&
                    bytes[offset + byte] != pattern[byte]) {
                    equal = false;
                    break;
                }
            }
            if (equal) {
                matches.push_back(base + rva + offset);
            }
        }
    }
    return matches;
}

uint8_t* unique_signature(uint8_t* base, const char* signature,
                          std::ptrdiff_t result_offset) {
    const std::vector<uint8_t*> matches = scan_executable(base, signature);
    if (matches.size() != 1) {
        return nullptr;
    }
    return matches[0] + result_offset;
}

uint8_t* resolve_rip(uint8_t* instruction, std::ptrdiff_t adjustment) {
    const int32_t displacement =
        *reinterpret_cast<const int32_t*>(instruction + 3);
    return instruction + 7 + displacement + adjustment;
}

bool resolve_addresses(uint8_t* base) {
    g_addresses.processor_exit = unique_signature(
        base, PROCESSOR_EXIT_SIGNATURE, PROCESSOR_EXIT_OFFSET);
    g_addresses.outer_exit = unique_signature(
        base, OUTER_EXIT_SIGNATURE, OUTER_EXIT_OFFSET);
    g_addresses.set_rotation = unique_signature(
        base, SET_ROTATION_SIGNATURE, 0);
    g_addresses.movement_rotation_push = unique_signature(
        base, MOVEMENT_ROTATION_PUSH_SIGNATURE,
        MOVEMENT_ROTATION_PUSH_OFFSET);
    auto* primary = unique_signature(
        base, PRIMARY_SET_SIGNATURE, PRIMARY_SET_RETURN_OFFSET);
    auto* limited = unique_signature(
        base, LIMITED_SET_SIGNATURE, LIMITED_SET_RETURN_OFFSET);
    if (g_addresses.processor_exit == nullptr ||
        g_addresses.outer_exit == nullptr ||
        g_addresses.set_rotation == nullptr ||
        g_addresses.movement_rotation_push == nullptr || primary == nullptr ||
        limited == nullptr) {
        return false;
    }
    g_addresses.primary_set_return = reinterpret_cast<uintptr_t>(primary);
    g_addresses.limited_set_return = reinterpret_cast<uintptr_t>(limited);

    uint8_t* pool_reference = unique_signature(
        base, NAME_POOL_SIGNATURE, 0);
    if (pool_reference == nullptr) {
        return false;
    }
    g_addresses.name_pool = resolve_rip(pool_reference, -0x10);
    log("roadie_camera_uncap: resolved all addresses from unique signatures");
    return true;
}

bool relative_jump(uint8_t* source, uint8_t* destination, int32_t& output) {
    const intptr_t displacement = reinterpret_cast<intptr_t>(destination) -
                                  reinterpret_cast<intptr_t>(source + 5);
    if (displacement < std::numeric_limits<int32_t>::min() ||
        displacement > std::numeric_limits<int32_t>::max()) {
        return false;
    }
    output = static_cast<int32_t>(displacement);
    return true;
}

uint8_t* allocate_relay_page(uint8_t* anchor) {
    SYSTEM_INFO system_info{};
    GetSystemInfo(&system_info);
    const uintptr_t granularity = system_info.dwAllocationGranularity;
    const uintptr_t anchor_value = reinterpret_cast<uintptr_t>(anchor);
    const uintptr_t lower = anchor_value > 0x70000000
                                ? anchor_value - 0x70000000
                                : granularity;
    const uintptr_t upper = std::min(
        anchor_value + 0x70000000,
        reinterpret_cast<uintptr_t>(system_info.lpMaximumApplicationAddress));

    uintptr_t cursor = lower;
    while (cursor < upper) {
        MEMORY_BASIC_INFORMATION info{};
        if (VirtualQuery(reinterpret_cast<void*>(cursor), &info,
                         sizeof(info)) != sizeof(info)) {
            break;
        }
        const uintptr_t region_begin =
            reinterpret_cast<uintptr_t>(info.BaseAddress);
        const uintptr_t region_end = region_begin + info.RegionSize;
        if (info.State == MEM_FREE) {
            const uintptr_t candidate =
                (region_begin + granularity - 1) & ~(granularity - 1);
            if (candidate + 0x1000 <= region_end && candidate < upper) {
                void* allocation = VirtualAlloc(
                    reinterpret_cast<void*>(candidate), 0x1000,
                    MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE);
                if (allocation != nullptr) {
                    return static_cast<uint8_t*>(allocation);
                }
            }
        }
        if (region_end <= cursor) {
            break;
        }
        cursor = region_end;
    }
    return nullptr;
}

void write_absolute_relay(uint8_t* relay, void* destination) {
    relay[0] = 0xFF;
    relay[1] = 0x25;
    std::memset(relay + 2, 0, 4);
    const uint64_t address = reinterpret_cast<uint64_t>(destination);
    std::memcpy(relay + 6, &address, sizeof(address));
}

bool write_hook(const HookSite& hook) {
    std::array<uint8_t, 16> patch{};
    std::fill(patch.begin(), patch.end(), 0x90);
    patch[0] = 0xE9;
    std::memcpy(patch.data() + 1, &hook.displacement, sizeof(hook.displacement));

    DWORD old_protection{};
    if (!VirtualProtect(hook.address, hook.length, PAGE_EXECUTE_READWRITE,
                        &old_protection)) {
        return false;
    }
    std::memcpy(hook.address, patch.data(), hook.length);
    FlushInstructionCache(GetCurrentProcess(), hook.address, hook.length);
    DWORD ignored{};
    VirtualProtect(hook.address, hook.length, old_protection, &ignored);
    return true;
}

void restore_hook(const HookSite& hook) {
    DWORD old_protection{};
    if (!VirtualProtect(hook.address, hook.length, PAGE_EXECUTE_READWRITE,
                        &old_protection)) {
        return;
    }
    std::memcpy(hook.address, hook.expected, hook.length);
    FlushInstructionCache(GetCurrentProcess(), hook.address, hook.length);
    DWORD ignored{};
    VirtualProtect(hook.address, hook.length, old_protection, &ignored);
}

class SuspendedThreads {
public:
    SuspendedThreads() = default;
    SuspendedThreads(const SuspendedThreads&) = delete;
    SuspendedThreads& operator=(const SuspendedThreads&) = delete;

    bool suspend() {
        threads_.reserve(256);
        const DWORD process_id = GetCurrentProcessId();
        const DWORD thread_id = GetCurrentThreadId();
        const HANDLE snapshot =
            CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
        if (snapshot == INVALID_HANDLE_VALUE) {
            return false;
        }
        THREADENTRY32 entry{};
        entry.dwSize = sizeof(entry);
        if (Thread32First(snapshot, &entry)) {
            do {
                if (entry.th32OwnerProcessID != process_id ||
                    entry.th32ThreadID == thread_id) {
                    continue;
                }
                HANDLE thread = OpenThread(THREAD_SUSPEND_RESUME, FALSE,
                                           entry.th32ThreadID);
                if (thread != nullptr &&
                    SuspendThread(thread) != static_cast<DWORD>(-1)) {
                    threads_.push_back(thread);
                } else if (thread != nullptr) {
                    CloseHandle(thread);
                }
            } while (Thread32Next(snapshot, &entry));
        }
        CloseHandle(snapshot);
        return true;
    }

    ~SuspendedThreads() {
        for (HANDLE thread : threads_) {
            ResumeThread(thread);
            CloseHandle(thread);
        }
    }

private:
    std::vector<HANDLE> threads_{};
};

enum class InstallResult {
    installed,
    retry,
    fatal,
};

InstallResult install_hooks() {
    HookSite hooks[] = {
        {g_addresses.processor_exit, PROCESSOR_BYTES.size(),
         PROCESSOR_BYTES.data(), reinterpret_cast<void*>(&RoadieProcessorDetour),
         nullptr},
        {g_addresses.outer_exit, OUTER_BYTES.size(), OUTER_BYTES.data(),
         reinterpret_cast<void*>(&RoadieOuterExitDetour), nullptr},
        {g_addresses.set_rotation, SET_ROTATION_BYTES.size(),
         SET_ROTATION_BYTES.data(),
         reinterpret_cast<void*>(&RoadieSetRotationDetour), nullptr},
        {g_addresses.movement_rotation_push,
         MOVEMENT_ROTATION_PUSH_BYTES.size(),
         MOVEMENT_ROTATION_PUSH_BYTES.data(),
         reinterpret_cast<void*>(&RoadieMovementTypeDetour), nullptr},
    };

    auto* pool = g_addresses.name_pool;
    if (!name_equals(pool, 0, "None") ||
        !find_name_id(pool, TARGET_CLASS, g_target_class_id) ||
        !find_name_id(pool, ROADIE_TUNING_CLASS,
                      g_roadie_tuning_class_id)) {
        return InstallResult::retry;
    }

    uint8_t* relay_page = allocate_relay_page(hooks[0].address);
    if (relay_page == nullptr) {
        log("roadie_camera_uncap: failed to allocate near relay memory");
        return InstallResult::fatal;
    }
    for (size_t index = 0; index < std::size(hooks); ++index) {
        hooks[index].relay = relay_page + index * 0x20;
        write_absolute_relay(hooks[index].relay, hooks[index].detour);
        if (!relative_jump(hooks[index].address, hooks[index].relay,
                           hooks[index].displacement)) {
            log("roadie_camera_uncap: relay is outside rel32 range");
            return InstallResult::fatal;
        }
    }
    DWORD relay_old{};
    VirtualProtect(relay_page, 0x1000, PAGE_EXECUTE_READ, &relay_old);
    FlushInstructionCache(GetCurrentProcess(), relay_page, 0x1000);

    g_processor_return = hooks[0].address + hooks[0].length;
    g_outer_return = hooks[1].address + hooks[1].length;
    g_set_rotation_return = hooks[2].address + hooks[2].length;
    g_movement_rotation_return = hooks[3].address + hooks[3].length;

    SuspendedThreads suspended;
    if (!suspended.suspend()) {
        log("roadie_camera_uncap: failed to enumerate process threads");
        return InstallResult::fatal;
    }
    size_t installed = 0;
    for (; installed < std::size(hooks); ++installed) {
        if (!write_hook(hooks[installed])) {
            break;
        }
    }
    if (installed != std::size(hooks)) {
        while (installed > 0) {
            restore_hook(hooks[--installed]);
        }
        log("roadie_camera_uncap: hook transaction failed and was rolled back");
        return InstallResult::fatal;
    }

    logf("roadie_camera_uncap: installed (camera FName 0x%08X, Roadie tuning "
         "FName 0x%08X)",
         static_cast<unsigned int>(g_target_class_id),
         static_cast<unsigned int>(g_roadie_tuning_class_id));
    return InstallResult::installed;
}

DWORD WINAPI worker(void*) {
    auto* game = reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    Sleep(5000);
    unsigned int scan_count = 0;
    while (!resolve_addresses(game)) {
        if (++scan_count >= 30) {
            log("roadie_camera_uncap: signature resolution failed after 30 "
                "attempts; no hooks installed");
            return 0;
        }
        Sleep(1000);
    }
    log("roadie_camera_uncap: waiting for the Roadie camera class");
    for (;;) {
        const InstallResult result = install_hooks();
        if (result != InstallResult::retry) {
            return 0;
        }
        Sleep(1000);
    }
}

} // namespace

extern "C" void __cdecl RoadieOnProcessorExit(void* processor,
                                                void* hook_stack) noexcept {
    if (processor == nullptr) {
        return;
    }
    auto* processor_bytes = static_cast<uint8_t*>(processor);
    auto* processor_class =
        *reinterpret_cast<uint8_t**>(processor_bytes + 0x10);
    if (processor_class == nullptr ||
        *reinterpret_cast<uint32_t*>(processor_class + 0x18) !=
            g_target_class_id) {
        return;
    }

    auto* stack = static_cast<uint8_t*>(hook_stack);
    auto* input_delta =
        *reinterpret_cast<Rotator**>(stack + 0x178);
    auto* output_delta =
        *reinterpret_cast<Rotator**>(stack + 0x188);
    if (input_delta == nullptr || output_delta == nullptr ||
        !std::isfinite(input_delta->yaw) ||
        !std::isfinite(output_delta->yaw)) {
        return;
    }

    g_processor_state.raw_delta_yaw = input_delta->yaw;
    g_processor_state.limited_delta_yaw = output_delta->yaw;
    g_processor_state.processor_pending = true;
}

extern "C" void __cdecl RoadieOnOuterExit(Rotator* output_view) noexcept {
    if (!g_processor_state.processor_pending) {
        return;
    }
    g_processor_state.processor_pending = false;
    if (output_view == nullptr || !std::isfinite(output_view->yaw)) {
        return;
    }
    const double correction =
        g_processor_state.raw_delta_yaw -
        g_processor_state.limited_delta_yaw;
    output_view->yaw += correction;
}

extern "C" void __cdecl RoadieOnSetControlRotation(
    void* controller, Rotator* requested, uintptr_t caller) noexcept {
    if (controller == nullptr || requested == nullptr ||
        !std::isfinite(requested->yaw)) {
        return;
    }
    const uintptr_t primary = g_addresses.primary_set_return;
    const uintptr_t limited = g_addresses.limited_set_return;
    if (caller == primary) {
        AcquireSRWLockExclusive(&g_control_rotation_lock);
        auto& state = g_control_rotation_states[controller];
        state.primary_yaw = requested->yaw;
        state.primary_valid = true;
        ReleaseSRWLockExclusive(&g_control_rotation_lock);
        return;
    }
    if (caller != limited) {
        return;
    }

    double primary_yaw{};
    bool apply = false;
    AcquireSRWLockExclusive(&g_control_rotation_lock);
    const auto entry = g_control_rotation_states.find(controller);
    if (entry != g_control_rotation_states.end() &&
        entry->second.primary_valid) {
        primary_yaw = entry->second.primary_yaw;
        entry->second.primary_valid = false;
        apply = true;
    }
    ReleaseSRWLockExclusive(&g_control_rotation_lock);

    if (apply) {
        requested->yaw = primary_yaw;
    }
}

extern "C" __declspec(dllexport) void MOD_LOADER_CALL
on_mod_load(mod_log_fn logger) {
    g_log = logger;
    const HANDLE thread = CreateThread(nullptr, 0, worker, nullptr, 0, nullptr);
    if (thread != nullptr) {
        CloseHandle(thread);
    } else {
        log("roadie_camera_uncap: failed to create initialization thread");
    }
}

extern "C" BOOL WINAPI DllMain(HMODULE module, DWORD reason, void*) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(module);
    }
    return TRUE;
}
