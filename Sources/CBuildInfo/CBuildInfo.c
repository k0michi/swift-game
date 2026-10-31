#include "CBuildInfo.h"

// A build that did not run the script, such as a plain swift build, has
// none.
#if __has_include("BuildInfo.generated.h")
#include "BuildInfo.generated.h"
#endif
#ifndef BUILD_INFO_VERSION
#define BUILD_INFO_VERSION "unknown"
#endif
#ifndef BUILD_INFO_SWIFT_VERSION
#define BUILD_INFO_SWIFT_VERSION "unknown"
#endif
#ifndef BUILD_INFO_TRIPLE
#define BUILD_INFO_TRIPLE "unknown"
#endif

const char *build_info_version(void) {
    return BUILD_INFO_VERSION;
}

const char *build_info_swift_version(void) {
    return BUILD_INFO_SWIFT_VERSION;
}

const char *build_info_triple(void) {
    return BUILD_INFO_TRIPLE;
}
