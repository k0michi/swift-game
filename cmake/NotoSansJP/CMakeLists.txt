cmake_minimum_required(VERSION 3.24)

project(SwiftGameNotoSansJP LANGUAGES NONE)

# Noto Sans JP's regular weight, under the SIL Open Font License, beside the
# games, for the text sample to read.
file(DOWNLOAD
    https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/SubsetOTF/JP/NotoSansJP-Regular.otf
    "${CMAKE_BINARY_DIR}/NotoSansJP-Regular.otf"
    EXPECTED_HASH SHA256=dff723ba59d57d136764a04b9b2d03205544f7cd785a711442d6d2d085ac5073
    SHOW_PROGRESS
)

if(DEFINED NOTO_SANS_JP_DESTINATION)
    file(COPY "${CMAKE_BINARY_DIR}/NotoSansJP-Regular.otf" DESTINATION "${NOTO_SANS_JP_DESTINATION}")
endif()
