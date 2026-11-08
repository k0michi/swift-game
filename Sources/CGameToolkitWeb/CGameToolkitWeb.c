#include "CGameToolkitWeb.h"

#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>

EM_JS_DEPS(game_toolkit_web, "$UTF8ToString,$getWasmTableEntry");

EM_JS(int, game_toolkit_web_pointer_is_locked, (void), {
    return document.pointerLockElement !== null ? 1 : 0;
});

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

EM_JS(void, game_toolkit_web_fetch, (const char *url, void *context, game_toolkit_web_fetched fetched), {
    const done = (id, length, status) => getWasmTableEntry(fetched)(context, id, length, status);
    fetch(UTF8ToString(url)).then(async (response) => {
        if (!response.ok) {
            done(0, 0, response.status);
            return;
        }
        const bytes = new Uint8Array(await response.arrayBuffer());
        Module.gameToolkitFetched ??= new Map();
        Module.gameToolkitFetchedID = (Module.gameToolkitFetchedID ?? 0) + 1;
        const id = Module.gameToolkitFetchedID;
        Module.gameToolkitFetched.set(id, bytes);
        done(id, bytes.length, response.status);
    }, () => done(0, 0, 0));
});

EM_JS(void, game_toolkit_web_take, (int id, unsigned char *bytes), {
    HEAPU8.set(Module.gameToolkitFetched.get(id), bytes);
    Module.gameToolkitFetched.delete(id);
});
#endif
