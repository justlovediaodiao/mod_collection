cmake_minimum_required(VERSION 3.20)

project(pragmata_dynamic_fps VERSION 2.0.0 LANGUAGES CXX)

if(NOT WIN32)
    message(FATAL_ERROR "pragmata-dynamic-fps only supports Windows")
endif()

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "pragmata-dynamic-fps must be built for x64")
endif()

set(REFRAMEWORK_NIGHTLY_SDK_DIR "" CACHE PATH
    "Path to the REFramework Nightly source tree")
find_path(REFRAMEWORK_INCLUDE_DIR
    NAMES reframework/API.h
    HINTS
        "${REFRAMEWORK_NIGHTLY_SDK_DIR}/include"
        "$ENV{REFRAMEWORK_NIGHTLY_SDK_DIR}/include"
    REQUIRED
)

add_library(pragmata_dynamic_fps MODULE
    src/plugin.cpp
    src/rtss.cpp
)
target_compile_features(pragmata_dynamic_fps PRIVATE cxx_std_17)
target_include_directories(pragmata_dynamic_fps PRIVATE "${REFRAMEWORK_INCLUDE_DIR}")
target_compile_definitions(pragmata_dynamic_fps PRIVATE
    WIN32_LEAN_AND_MEAN
    UNICODE
    _UNICODE
)

set_target_properties(pragmata_dynamic_fps PROPERTIES
    PREFIX ""
    OUTPUT_NAME "pragmata_dynamic_fps"
)

if(MSVC)
    target_compile_options(pragmata_dynamic_fps PRIVATE /W4 /WX /utf-8)
endif()

install(TARGETS pragmata_dynamic_fps
    RUNTIME DESTINATION reframework/plugins
    LIBRARY DESTINATION reframework/plugins
)
