cmake_minimum_required(VERSION 3.20)

project(borderlands4_dynamic_fps LANGUAGES CXX)

if(NOT WIN32)
    message(FATAL_ERROR "borderlands4_dynamic_fps only supports Windows")
endif()

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "borderlands4_dynamic_fps must be built for x64")
endif()

add_library(borderlands4_dynamic_fps MODULE
    src/plugin.cpp
    src/rtss.cpp
)

target_compile_features(borderlands4_dynamic_fps PRIVATE cxx_std_17)
target_include_directories(borderlands4_dynamic_fps PRIVATE include)
target_compile_definitions(borderlands4_dynamic_fps PRIVATE
    WIN32_LEAN_AND_MEAN
    UNICODE
    _UNICODE
)

set_target_properties(borderlands4_dynamic_fps PROPERTIES
    PREFIX ""
    OUTPUT_NAME "borderlands4_dynamic_fps"
)

if(MSVC)
    target_compile_options(borderlands4_dynamic_fps PRIVATE /W4 /WX /utf-8)
endif()
