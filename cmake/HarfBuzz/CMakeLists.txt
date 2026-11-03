cmake_minimum_required(VERSION 3.24)

project(SwiftGameHarfBuzz LANGUAGES CXX)

include(FetchContent)

# Only checked out: HarfBuzz is built here from harfbuzz.cc, the whole library
# in one file, with none of the libraries it can use, such as FreeType, ICU or
# the platforms' own shapers.
FetchContent_Declare(
    harfbuzz
    GIT_REPOSITORY https://github.com/harfbuzz/harfbuzz.git
    GIT_TAG 35f656a1a2bab548ea7f54a6dd3fba2b09680d14 # 15.0.0
    GIT_SHALLOW FALSE
    GIT_PROGRESS TRUE
    SOURCE_SUBDIR not-a-directory
)

FetchContent_MakeAvailable(harfbuzz)

add_library(harfbuzz STATIC "${harfbuzz_SOURCE_DIR}/src/harfbuzz.cc")
target_include_directories(harfbuzz PUBLIC "${harfbuzz_SOURCE_DIR}/src")
# Without C++'s exceptions and run-time types, it needs no C++ library.
if(NOT MSVC)
    target_compile_options(harfbuzz PRIVATE -fno-exceptions -fno-rtti -fno-threadsafe-statics)
endif()

if(DEFINED HARFBUZZ_METADATA_DIRECTORY)
    file(MAKE_DIRECTORY "${HARFBUZZ_METADATA_DIRECTORY}")
    file(GENERATE
        OUTPUT "${HARFBUZZ_METADATA_DIRECTORY}/compiler-flags.txt"
        CONTENT "-I${harfbuzz_SOURCE_DIR}/src\n"
    )
    file(GENERATE
        OUTPUT "${HARFBUZZ_METADATA_DIRECTORY}/linker-flags.txt"
        CONTENT "$<TARGET_FILE:harfbuzz>\n"
    )
endif()
