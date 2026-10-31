#ifndef C_BUILD_INFO_H
#define C_BUILD_INFO_H

// What was built, which scripts/generate-build-info.sh writes before each
// build. Only the definition reads it, so that only it is compiled again when
// it changes.

// `git describe --tags --always --dirty`: the last tag, the commits since and
// the commit, or the commit alone with no tag, and whether files changed.
const char *build_info_version(void);

// The version of the Swift compiler that built it, such as "6.3.1".
const char *build_info_swift_version(void);

// The target triple without an OS version, such as "arm64-apple-macosx".
const char *build_info_triple(void);

#endif
