#include "CBuildInfo.h"

// A build that did not run the script, such as a plain swift build, has
// none.
#if __has_include("BuildInfo.generated.h")
#include "BuildInfo.generated.h"
#else
#define BUILD_INFO_VERSION "unknown"
#endif

const char *build_info_version(void) {
    return BUILD_INFO_VERSION;
}
