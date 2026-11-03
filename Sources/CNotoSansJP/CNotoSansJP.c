#include "CNotoSansJP.h"

#pragma clang diagnostic ignored "-Wc23-extensions"

static const unsigned char regular[] = {
#embed <NotoSansJP-Regular.otf>
};

const unsigned char *const CNotoSansJP_Regular = regular;
const size_t CNotoSansJP_RegularSize = sizeof regular;
