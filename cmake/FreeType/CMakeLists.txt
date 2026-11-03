cmake_minimum_required(VERSION 3.24)

project(SwiftGameFreeType LANGUAGES C)

include(FetchContent)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
# FreeType alone: no compressed fonts, PNG bitmaps, HarfBuzz autohinting or
# Apple's HVF fonts, whose libraries the games would have to link too.
set(FT_DISABLE_ZLIB ON CACHE BOOL "" FORCE)
set(FT_DISABLE_BZIP2 ON CACHE BOOL "" FORCE)
set(FT_DISABLE_PNG ON CACHE BOOL "" FORCE)
set(FT_DISABLE_HARFBUZZ ON CACHE BOOL "" FORCE)
set(FT_DISABLE_BROTLI ON CACHE BOOL "" FORCE)
set(FT_DISABLE_HVF ON CACHE BOOL "" FORCE)

FetchContent_Declare(
    freetype
    GIT_REPOSITORY https://gitlab.freedesktop.org/freetype/freetype.git
    GIT_TAG 631ee12ce7693c9ba9ea33f0235da99218045420 # VER-2-15-0
    GIT_SHALLOW FALSE
    GIT_PROGRESS TRUE
)

FetchContent_MakeAvailable(freetype)

if(DEFINED FREETYPE_METADATA_DIRECTORY)
    file(MAKE_DIRECTORY "${FREETYPE_METADATA_DIRECTORY}")
    file(GENERATE
        OUTPUT "${FREETYPE_METADATA_DIRECTORY}/compiler-flags.txt"
        CONTENT "-I$<JOIN:$<TARGET_PROPERTY:freetype,INTERFACE_INCLUDE_DIRECTORIES>,\n-I>\n"
    )
    file(GENERATE
        OUTPUT "${FREETYPE_METADATA_DIRECTORY}/linker-flags.txt"
        CONTENT "$<TARGET_FILE:freetype>\n"
    )
endif()
