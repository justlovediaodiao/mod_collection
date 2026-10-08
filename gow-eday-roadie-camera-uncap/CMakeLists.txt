cmake_minimum_required(VERSION 3.20)

project(gow_eday_roadie_camera_uncap LANGUAGES CXX ASM_MASM)

if(NOT WIN32 OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "gow_eday_roadie_camera_uncap targets Windows x64")
endif()

if(NOT MSVC)
    message(FATAL_ERROR "The x64 hook stubs require the MSVC MASM toolchain")
endif()

add_library(roadie_camera_uncap SHARED
    src/mod.cpp
    src/hooks.asm
)

target_compile_features(roadie_camera_uncap PRIVATE cxx_std_17)
target_include_directories(roadie_camera_uncap PRIVATE include)
target_compile_definitions(roadie_camera_uncap PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
    UNICODE
    _UNICODE
)
target_compile_options(roadie_camera_uncap PRIVATE
    /W4
    /permissive-
    /EHsc
)
target_link_libraries(roadie_camera_uncap PRIVATE kernel32)

set_target_properties(roadie_camera_uncap PROPERTIES
    PREFIX ""
    OUTPUT_NAME "roadie_camera_uncap"
)

install(TARGETS roadie_camera_uncap RUNTIME DESTINATION .)
