#pragma once

#define MOD_LOADER_CALL __cdecl

extern "C" {
typedef void(MOD_LOADER_CALL* mod_log_fn)(const char* message);
}
