cmake_minimum_required(VERSION 3.20)

project(fh2_impulse_triggers LANGUAGES CXX)

if(NOT WIN32 OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "fh2_impulse_triggers targets Windows x64")
endif()

add_library(fh2_impulse_triggers MODULE
    src/main.cpp
)

target_compile_features(fh2_impulse_triggers PRIVATE cxx_std_17)
target_include_directories(fh2_impulse_triggers PRIVATE include)
target_compile_definitions(fh2_impulse_triggers PRIVATE
    NOMINMAX
    WIN32_LEAN_AND_MEAN
    UNICODE
    _UNICODE
)
target_link_libraries(fh2_impulse_triggers PRIVATE kernel32 windowsapp)

if(MSVC)
    target_compile_options(fh2_impulse_triggers PRIVATE /W4 /permissive- /EHsc)
endif()

set_target_properties(fh2_impulse_triggers PROPERTIES PREFIX "")
