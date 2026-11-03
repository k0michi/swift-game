cmake_minimum_required(VERSION 3.24)

project(SwiftGameNotoSansJP LANGUAGES NONE)

# Noto Sans JP's regular weight, under the SIL Open Font License, for
# CNotoSansJP to #embed.
set(NOTO_SANS_JP_DIRECTORY "${CMAKE_BINARY_DIR}/font")
file(DOWNLOAD
    https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/SubsetOTF/JP/NotoSansJP-Regular.otf
    "${NOTO_SANS_JP_DIRECTORY}/NotoSansJP-Regular.otf"
    EXPECTED_HASH SHA256=dff723ba59d57d136764a04b9b2d03205544f7cd785a711442d6d2d085ac5073
    SHOW_PROGRESS
)

if(DEFINED NOTO_SANS_JP_METADATA_DIRECTORY)
    file(MAKE_DIRECTORY "${NOTO_SANS_JP_METADATA_DIRECTORY}")
    file(GENERATE
        OUTPUT "${NOTO_SANS_JP_METADATA_DIRECTORY}/compiler-flags.txt"
        CONTENT "--embed-dir=${NOTO_SANS_JP_DIRECTORY}\n"
    )
endif()
