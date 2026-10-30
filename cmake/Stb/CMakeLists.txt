cmake_minimum_required(VERSION 3.24)

project(SwiftGameStb LANGUAGES C)

include(FetchContent)

# stb has no CMake project of its own, so this only checks it out.
FetchContent_Declare(
    stb
    GIT_REPOSITORY https://github.com/nothings/stb.git
    GIT_TAG 003501f6d7a8668ce8b6d875e34dd97ad0d5d5b5
    GIT_SHALLOW FALSE
    GIT_PROGRESS TRUE
)

FetchContent_MakeAvailable(stb)

# A library for each single-file library, with its implementation.
foreach(library IN ITEMS stb_image stb_image_write stb_vorbis)
    add_library(${library} STATIC ${library}.c)
    target_include_directories(${library} PUBLIC "${stb_SOURCE_DIR}")
    if(WIN32)
        target_compile_definitions(${library} PRIVATE _CRT_SECURE_NO_WARNINGS)
    endif()
endforeach()

if(DEFINED STB_METADATA_DIRECTORY)
    file(MAKE_DIRECTORY "${STB_METADATA_DIRECTORY}")
    file(GENERATE
        OUTPUT "${STB_METADATA_DIRECTORY}/compiler-flags.txt"
        CONTENT "-I${stb_SOURCE_DIR}\n"
    )
    foreach(library IN ITEMS stb_image stb_image_write stb_vorbis)
        file(GENERATE
            OUTPUT "${STB_METADATA_DIRECTORY}/${library}-linker-flags.txt"
            CONTENT "$<TARGET_FILE:${library}>\n"
        )
    endforeach()
endif()
