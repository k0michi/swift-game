#include "CFetchWeb.h"

#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>

EM_JS_DEPS(fetch_web, "$getWasmTableEntry,$lengthBytesUTF8,$stringToUTF8,$UTF8ToString");

// The table lives on Module, set up on first use.
EM_JS(void, fetch_web_setup, (void), {
    if (Module.fetchWeb) return;
    const objects = [undefined];
    const free = [];
    Module.fetchWeb = {
        objects,
        keep(value) {
            const handle = free.length ? free.pop() : objects.length;
            objects[handle] = value;
            return handle;
        },
        release(handle) {
            objects[handle] = undefined;
            free.push(handle);
        },
        // Keeps what a promise was rejected with as an object with a message.
        keepError(e) {
            return this.keep(e instanceof Error ? e : { message: String(e) });
        },
    };
});

EM_JS(void, fetch_web_release_js, (int object), {
    Module.fetchWeb.release(object);
});

void fetch_web_release(int object) {
    fetch_web_setup();
    fetch_web_release_js(object);
}

EM_JS(void, fetch_web_fetch_js, (
    const char *url, const char *method, const char *headers,
    const unsigned char *body, int body_length, int has_body,
    fetch_web_settle settle, void *user_data), {
    const web = Module.fetchWeb;
    const callback = getWasmTableEntry(settle);
    const init = {
        method: UTF8ToString(method),
        headers: UTF8ToString(headers).split('\r\n').filter((line) => line).map((line) => {
            const colon = line.indexOf(': ');
            return [line.slice(0, colon), line.slice(colon + 2)];
        }),
    };
    if (has_body) init.body = HEAPU8.slice(body, body + body_length);
    let promise;
    try {
        promise = fetch(UTF8ToString(url), init);
    } catch (e) {
        promise = Promise.reject(e);
    }
    promise.then(
        (response) => callback(user_data, web.keep(response), 0),
        (e) => callback(user_data, 0, web.keepError(e)));
});

void fetch_web_fetch(
    const char *url, const char *method, const char *headers,
    const unsigned char *body, int body_length, int has_body,
    fetch_web_settle settle, void *user_data) {
    fetch_web_setup();
    fetch_web_fetch_js(url, method, headers, body, body_length, has_body, settle, user_data);
}

EM_JS(int, fetch_web_get_number, (int object, const char *property), {
    return Number(Module.fetchWeb.objects[object][UTF8ToString(property)]);
});

EM_JS(int, fetch_web_get_string, (int handle, const char *property, char *buffer, int size), {
    const object = Module.fetchWeb.objects[handle];
    const name = UTF8ToString(property);
    const value = name === 'headers' && object instanceof Response
        ? [...object.headers].map(([key, value]) => key + ': ' + value + '\r\n').join("")
        : String(object[name]);
    if (size > 0) stringToUTF8(value, buffer, size);
    return lengthBytesUTF8(value);
});

EM_JS(void, fetch_web_response_bytes, (int response, fetch_web_settle_bytes settle, void *user_data), {
    const web = Module.fetchWeb;
    const callback = getWasmTableEntry(settle);
    let promise;
    try {
        promise = web.objects[response].arrayBuffer();
    } catch (e) {
        promise = Promise.reject(e);
    }
    promise.then(
        (buffer) => callback(user_data, web.keep(new Uint8Array(buffer)), buffer.byteLength, 0),
        (e) => callback(user_data, 0, 0, web.keepError(e)));
});

EM_JS(void, fetch_web_copy_bytes, (int bytes, unsigned char *destination), {
    HEAPU8.set(Module.fetchWeb.objects[bytes], destination);
});
#endif
