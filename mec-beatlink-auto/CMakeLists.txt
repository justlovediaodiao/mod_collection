cmake_minimum_required(VERSION 3.24)

project(beatlink_auto LANGUAGES C CXX)

if(NOT WIN32)
    message(FATAL_ERROR "beatlink_auto only supports Windows")
endif()

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "beatlink_auto must be built for x64")
endif()

include(FetchContent)
set(BUILD_SHARED_LIBS OFF)
FetchContent_Declare(minhook
    URL https://github.com/TsudaKageyu/minhook/archive/refs/tags/v1.3.4.zip
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(minhook)

add_library(beatlink_auto MODULE main.cpp)
target_compile_features(beatlink_auto PRIVATE cxx_std_17)
target_include_directories(beatlink_auto PRIVATE include)
target_link_libraries(beatlink_auto PRIVATE minhook kernel32 user32)

set_target_properties(beatlink_auto PROPERTIES
    PREFIX ""
    OUTPUT_NAME "beatlink_auto"
)

if(MSVC)
    target_compile_options(beatlink_auto PRIVATE /W4 /utf-8)
endif()

install(TARGETS beatlink_auto
    RUNTIME DESTINATION mods
    LIBRARY DESTINATION mods
)
install(FILES config.ini DESTINATION mods)
