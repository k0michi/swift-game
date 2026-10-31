#include "CGameToolkitWeb.h"

#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>

EM_JS_DEPS(game_toolkit_web, "$UTF8ToString");

EM_JS(void, game_toolkit_web_download, (const char *name, const unsigned char *bytes, int length, const char *type), {
    const blob = new Blob([HEAPU8.slice(bytes, bytes + length)], { type: UTF8ToString(type) });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = UTF8ToString(name);
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 0);
});
#endif
