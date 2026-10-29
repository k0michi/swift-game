#ifndef C_BUILD_INFO_H
#define C_BUILD_INFO_H

// What was built, which scripts/generate-build-info.sh writes before each
// build. Only the definition reads it, so that only it is compiled again when
// it changes.

// `git describe --tags --always --dirty`: the last tag, the commits since and
// the commit, or the commit alone with no tag, and whether files changed.
const char *build_info_version(void);

#endif
