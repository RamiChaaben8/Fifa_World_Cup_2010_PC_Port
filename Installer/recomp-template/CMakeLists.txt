# worldcup2010 - ReXGlue Recompiled Project
#
# SDK boilerplate lives in generated/rexglue.cmake.

cmake_minimum_required(VERSION 3.25)
project(worldcup2010 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(generated/rexglue.cmake)

# Sources
set(WORLDCUP2010_SOURCES
    src/main.cpp
)

if(WIN32)
    add_executable(worldcup2010 WIN32 ${WORLDCUP2010_SOURCES})
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/worldcup2010.rc")
        enable_language(RC)
        target_sources(worldcup2010 PRIVATE src/worldcup2010.rc)
        if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
            set_source_files_properties(src/worldcup2010.rc PROPERTIES
                COMPILE_OPTIONS "/nologo"
            )
            target_include_directories(worldcup2010 PRIVATE
                "${CMAKE_CURRENT_SOURCE_DIR}/src"
            )
        endif()
    endif()
else()
    add_executable(worldcup2010 ${WORLDCUP2010_SOURCES})
endif()

rexglue_setup_target(worldcup2010 GPU_PLUGINS xenos)
set_target_properties(worldcup2010 PROPERTIES OUTPUT_NAME "FIFA World Cup 2010")
target_include_directories(worldcup2010 PRIVATE src)

# The source SDK keeps ImGui private to rexruntime; its public UI headers
# still require the include directory when compiling the host application.
# Propagate headers only, keeping the ImGui objects in the shared runtime.
if(TARGET imgui::imgui)
    target_include_directories(worldcup2010 PRIVATE
        $<TARGET_PROPERTY:imgui::imgui,INTERFACE_INCLUDE_DIRECTORIES>)
endif()

# Guest SIMD code must be optimized even when using the debug runtime. Keep
# debug symbols and checked runtime libraries while avoiding unoptimized SIMD
# wrappers in the game and its separately compiled DLL.
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(worldcup2010 PRIVATE -O2)
    if(TARGET worldcup2010_recomp)
        target_compile_options(worldcup2010_recomp PRIVATE -O2)
    endif()
endif()

# World Cup 2010 DLL-specific kernel stubs (fifadllzf.xex -> target worldcup2010_fifadllzf).
# Note: native_libc_hooks.cpp is left disabled until World Cup 2010 CRT addresses are verified.
if(TARGET worldcup2010_fifadllzf)
    if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
        target_compile_options(worldcup2010_fifadllzf PRIVATE -O2)
    endif()
    target_sources(worldcup2010_fifadllzf PRIVATE
        src/stubs.cpp
        src/round32_qichain_override.cpp
    )
endif()
