#include "CGameToolkitWeb.h"

#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>
#include <stdlib.h>

EM_JS_DEPS(game_toolkit_web, "$UTF8ToString,$getWasmTableEntry,$stringToNewUTF8");

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
// An invisible input element, which the browser's input methods compose
// into. Keys pressed while they compose stay away from SDL, which would take
// them for its own; SDL, which listens on the window, gets the rest. Each
// entry is sent, and the element emptied, so that it holds only what is being
// composed.
EM_JS(void, game_toolkit_web_start_text_input, (void *context, game_toolkit_web_text_input_changed changed), {
    let input = Module.gameToolkitTextInput;
    if (!input) {
        input = document.createElement('input');
        input.type = 'text';
        input.autocomplete = 'off';
        input.spellcheck = false;
        input.setAttribute('autocapitalize', 'off');
        input.style.cssText = 'position: fixed; left: 0; top: 0; width: 1px; height: 1px; margin: 0; padding: 0; '
            + 'border: 0; outline: none; opacity: 0; background: transparent; color: transparent; '
            + 'caret-color: transparent; font-size: 16px; pointer-events: none;';
        document.body.appendChild(input);
        Module.gameToolkitTextInput = input;

        const send = (kind, text) => Module.gameToolkitTextInputChanged?.(kind, text);
        let composing = false;
        const keepFromSDL = (event) => {
            if (composing || event.isComposing || event.keyCode === 229) {
                event.stopPropagation();
            }
        };
        input.addEventListener('keydown', keepFromSDL);
        input.addEventListener('keyup', keepFromSDL);
        input.addEventListener('compositionstart', () => { composing = true; });
        input.addEventListener('compositionupdate', (event) => send(0, event.data));
        input.addEventListener('compositionend', (event) => {
            composing = false;
            send(0, '');
            if (event.data) {
                send(1, event.data);
            }
            input.value = '';
        });
        input.addEventListener('input', (event) => {
            if (!composing && !event.isComposing && input.value) {
                send(1, input.value);
                input.value = '';
            }
        });
        // A click on the canvas takes the focus, which goes back while text
        // is being entered.
        input.addEventListener('blur', () => {
            if (Module.gameToolkitTextInputChanged) {
                setTimeout(() => input.focus({ preventScroll: true }), 0);
            }
        });
    }
    Module.gameToolkitTextInputChanged = (kind, text) => getWasmTableEntry(changed)(context, kind, stringToNewUTF8(text));
    input.focus({ preventScroll: true });
});

EM_JS(void, game_toolkit_web_stop_text_input, (void), {
    Module.gameToolkitTextInputChanged = null;
    Module.gameToolkitTextInput?.blur();
});

EM_JS(void, game_toolkit_web_set_text_input_area, (double x, double y, double width, double height), {
    const input = Module.gameToolkitTextInput;
    const canvas = Module.canvas ?? document.querySelector('canvas');
    if (!input || !canvas) {
        return;
    }
    const bounds = canvas.getBoundingClientRect();
    input.style.left = `${bounds.left + x}px`;
    input.style.top = `${bounds.top + y}px`;
    input.style.width = `${Math.max(width, 1)}px`;
    input.style.height = `${Math.max(height, 1)}px`;
});

void game_toolkit_web_free(void *pointer) {
    free(pointer);
}
#endif
