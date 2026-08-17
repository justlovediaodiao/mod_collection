#include <windows.h>

#include <reframework/API.h>

#include <stddef.h>
#include <stdint.h>

namespace rtss {
bool set_fps_limit(uint32_t fps, char* message, size_t message_size);
}

namespace {

constexpr uint32_t MENU_FPS = 60;
constexpr uint32_t GAME_FPS = 120;
constexpr uint32_t CHECK_INTERVAL = 20;

#pragma pack(push, 1)
struct InvokeResult {
    unsigned char value[128]{};
    bool exception_thrown{};
};
#pragma pack(pop)

struct PluginState {
    const REFrameworkPluginFunctions* functions{};
    const REFrameworkSDKData* sdk{};
    REFrameworkMethodHandle is_any_open_menu{};
    REFrameworkMethodHandle is_title_flow{};
    uint32_t frame_count{};
    uint32_t current_fps{UINT32_MAX};
    bool rtss_warning_logged{};
    bool gui_warning_logged{};
};

PluginState g_state;

bool resolve_gui_methods(REFrameworkManagedObjectHandle gui) {
    if (g_state.is_any_open_menu != nullptr && g_state.is_title_flow != nullptr) {
        return true;
    }

    const auto type = g_state.sdk->managed_object->get_type_definition(gui);
    if (type == nullptr) {
        return false;
    }

    g_state.is_any_open_menu =
        g_state.sdk->type_definition->find_method(type, "isAnyOpenMenu");
    g_state.is_title_flow =
        g_state.sdk->type_definition->find_method(type, "isTitleFlow");
    return g_state.is_any_open_menu != nullptr && g_state.is_title_flow != nullptr;
}

bool invoke_boolean(REFrameworkMethodHandle method,
                    REFrameworkManagedObjectHandle object, bool& value) {
    InvokeResult output;
    const auto result = g_state.sdk->method->invoke(
        method, object, nullptr, 0, &output,
        static_cast<unsigned int>(sizeof(output)));

    if (result != REFRAMEWORK_ERROR_NONE || output.exception_thrown) {
        return false;
    }

    value = output.value[0] != 0;
    return true;
}

bool get_menu_state(bool& is_menu) {
    const auto gui =
        g_state.sdk->functions->get_managed_singleton("app.GuiManager");
    bool any_open_menu{};
    bool title_flow{};

    if (gui == nullptr || !resolve_gui_methods(gui) ||
        !invoke_boolean(g_state.is_any_open_menu, gui, any_open_menu) ||
        (!any_open_menu &&
         !invoke_boolean(g_state.is_title_flow, gui, title_flow))) {
        if (!g_state.gui_warning_logged) {
            g_state.functions->log_warn(
                "[PRAGMATA FPS] app.GuiManager or its menu methods are unavailable");
            g_state.gui_warning_logged = true;
        }
        return false;
    }

    g_state.gui_warning_logged = false;
    is_menu = any_open_menu || title_flow;
    return true;
}

void on_begin_rendering() {
    if (++g_state.frame_count < CHECK_INTERVAL) {
        return;
    }
    g_state.frame_count = 0;

    bool is_menu{};
    if (!get_menu_state(is_menu)) {
        return;
    }

    const uint32_t target_fps = is_menu ? MENU_FPS : GAME_FPS;
    if (target_fps == g_state.current_fps) {
        return;
    }

    char message[256]{};
    if (!rtss::set_fps_limit(target_fps, message, sizeof(message))) {
        if (!g_state.rtss_warning_logged) {
            g_state.functions->log_warn("[PRAGMATA FPS] %s", message);
            g_state.rtss_warning_logged = true;
        }
        return;
    }

    g_state.rtss_warning_logged = false;
    g_state.current_fps = target_fps;
    g_state.functions->log_info("[PRAGMATA FPS] %s", message);
}

} // namespace

extern "C" __declspec(dllexport) bool reframework_plugin_initialize(
    const REFrameworkPluginInitializeParam* param) {
    if (param == nullptr || param->functions == nullptr || param->sdk == nullptr ||
        param->sdk->functions == nullptr ||
        param->sdk->managed_object == nullptr ||
        param->sdk->type_definition == nullptr || param->sdk->method == nullptr ||
        param->functions->on_pre_application_entry == nullptr ||
        param->functions->log_warn == nullptr ||
        param->functions->log_info == nullptr) {
        return false;
    }

    g_state.functions = param->functions;
    g_state.sdk = param->sdk;

    if (!g_state.functions->on_pre_application_entry(
            "BeginRendering", on_begin_rendering)) {
        g_state.functions->log_warn(
            "[PRAGMATA FPS] Failed to register the BeginRendering callback");
        return false;
    }

    g_state.functions->log_info(
        "[PRAGMATA FPS] Plugin initialized (menu %u FPS, gameplay %u FPS)",
        MENU_FPS, GAME_FPS);
    return true;
}
