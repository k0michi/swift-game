cmake_minimum_required(VERSION 3.24)

project(SwiftGameNotoSansJP LANGUAGES NONE)

# Noto Sans JP's regular weight, under the SIL Open Font License, beside the
# games, for the text sample to read, with its license.
file(DOWNLOAD
    https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/SubsetOTF/JP/NotoSansJP-Regular.otf
    "${CMAKE_BINARY_DIR}/NotoSansJP-Regular.otf"
    EXPECTED_HASH SHA256=dff723ba59d57d136764a04b9b2d03205544f7cd785a711442d6d2d085ac5073
    SHOW_PROGRESS
)

# The license, which goes wherever the font does, under the copyright notice
# that the font's own name table holds, which the license leaves out.
file(DOWNLOAD
    https://github.com/notofonts/noto-cjk/raw/Sans2.004/LICENSE
    "${CMAKE_BINARY_DIR}/LICENSE"
    EXPECTED_HASH SHA256=6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2
)
file(READ "${CMAKE_BINARY_DIR}/LICENSE" NOTO_SANS_JP_LICENSE)
file(WRITE "${CMAKE_BINARY_DIR}/NotoSansJP-LICENSE.txt"
    "Noto Sans JP\n© 2014-2021 Adobe (http://www.adobe.com/).\n\n${NOTO_SANS_JP_LICENSE}")

if(DEFINED NOTO_SANS_JP_DESTINATION)
    file(COPY "${CMAKE_BINARY_DIR}/NotoSansJP-Regular.otf" "${CMAKE_BINARY_DIR}/NotoSansJP-LICENSE.txt"
        DESTINATION "${NOTO_SANS_JP_DESTINATION}")
endif()
