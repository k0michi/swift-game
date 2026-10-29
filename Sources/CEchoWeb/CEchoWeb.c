#include "CEchoWeb.h"

#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>

EM_JS_DEPS(echo_web, "$getWasmTableEntry,$lengthBytesUTF8,$stringToUTF8,$UTF8ToString");

// The table and the error codes live on Module, set up on first use.
EM_JS(void, echo_web_setup, (void), {
    if (Module.echoWeb) return;
    const objects = [undefined];
    const free = [];
    Module.echoWeb = {
        objects,
        keep(value) {
            const handle = free.length ? free.pop() : objects.length;
            objects[handle] = value;
            return handle;
        },
        release(handle) {
            if (!handle) return;
            objects[handle] = undefined;
            free.push(handle);
        },
        error(e) {
            switch (e && e.name) {
            case 'InvalidAccessError': return 1;
            case 'InvalidStateError': return 2;
            case 'IndexSizeError': return 3;
            case 'NotSupportedError': return 4;
            case 'RangeError': return 5;
            }
            throw e;
        },
        listeners: new WeakMap(),
    };
});

EM_JS(void, echo_web_release_js, (int object), {
    Module.echoWeb.release(object);
});

void echo_web_release(int object) {
    echo_web_setup();
    echo_web_release_js(object);
}

EM_JS(int, echo_web_new_js, (const char *constructor, int context, const char *options, int *error), {
    const web = Module.echoWeb;
    const Constructor = globalThis[UTF8ToString(constructor)];
    const parsed = JSON.parse(UTF8ToString(options));
    try {
        const object = context ? new Constructor(web.objects[context], parsed) : new Constructor(parsed);
        HEAP32[error >> 2] = 0;
        return web.keep(object);
    } catch (e) {
        HEAP32[error >> 2] = web.error(e);
        return 0;
    }
});

int echo_web_new(const char *constructor, int context, const char *options, int *error) {
    echo_web_setup();
    return echo_web_new_js(constructor, context, options, error);
}

EM_JS(double, echo_web_get_number, (int object, const char *property), {
    return Module.echoWeb.objects[object][UTF8ToString(property)];
});

EM_JS(int, echo_web_set_number, (int object, const char *property, double value), {
    try {
        Module.echoWeb.objects[object][UTF8ToString(property)] = value;
        return 0;
    } catch (e) {
        return Module.echoWeb.error(e);
    }
});

EM_JS(int, echo_web_get_string, (int object, const char *property, char *buffer, int size), {
    const value = String(Module.echoWeb.objects[object][UTF8ToString(property)]);
    if (size > 0) stringToUTF8(value, buffer, size);
    return lengthBytesUTF8(value);
});

EM_JS(int, echo_web_set_string, (int object, const char *property, const char *value), {
    try {
        Module.echoWeb.objects[object][UTF8ToString(property)] = UTF8ToString(value);
        return 0;
    } catch (e) {
        return Module.echoWeb.error(e);
    }
});

EM_JS(int, echo_web_get_object, (int object, const char *property), {
    const value = Module.echoWeb.objects[object][UTF8ToString(property)];
    return value == null ? 0 : Module.echoWeb.keep(value);
});

EM_JS(int, echo_web_set_object, (int object, const char *property, int value), {
    const web = Module.echoWeb;
    try {
        web.objects[object][UTF8ToString(property)] = value ? web.objects[value] : null;
        return 0;
    } catch (e) {
        return web.error(e);
    }
});

EM_JS(int, echo_web_call, (int object, const char *method, int target, const double *arguments, int count), {
    const web = Module.echoWeb;
    const values = Array.from(HEAPF64.subarray(arguments >> 3, (arguments >> 3) + count));
    if (target) values.unshift(web.objects[target]);
    try {
        web.objects[object][UTF8ToString(method)](...values);
        return 0;
    } catch (e) {
        return web.error(e);
    }
});

EM_JS(int, echo_web_call_with_floats, (
    int object, const char *method, const float *values, int value_count,
    const double *arguments, int count), {
    const web = Module.echoWeb;
    const floats = HEAPF32.slice(values >> 2, (values >> 2) + value_count);
    const rest = Array.from(HEAPF64.subarray(arguments >> 3, (arguments >> 3) + count));
    try {
        web.objects[object][UTF8ToString(method)](floats, ...rest);
        return 0;
    } catch (e) {
        return web.error(e);
    }
});

EM_JS(int, echo_web_set_floats, (int object, const char *property, const float *values, int value_count), {
    const floats = values ? HEAPF32.slice(values >> 2, (values >> 2) + value_count) : null;
    try {
        Module.echoWeb.objects[object][UTF8ToString(property)] = floats;
        return 0;
    } catch (e) {
        return Module.echoWeb.error(e);
    }
});

EM_JS(int, echo_web_get_frequency_response, (
    int object, const float *frequencies, float *magnitudes, float *phases, int count), {
    const frequencyHz = HEAPF32.slice(frequencies >> 2, (frequencies >> 2) + count);
    const magResponse = new Float32Array(count);
    const phaseResponse = new Float32Array(count);
    try {
        Module.echoWeb.objects[object].getFrequencyResponse(frequencyHz, magResponse, phaseResponse);
    } catch (e) {
        return Module.echoWeb.error(e);
    }
    HEAPF32.set(magResponse, magnitudes >> 2);
    HEAPF32.set(phaseResponse, phases >> 2);
    return 0;
});

EM_JS(void, echo_web_call_async, (
    int object, const char *method, const double *arguments, int count,
    echo_web_settle settle, void *user_data), {
    const web = Module.echoWeb;
    const values = Array.from(HEAPF64.subarray(arguments >> 3, (arguments >> 3) + count));
    const callback = getWasmTableEntry(settle);
    let promise;
    try {
        promise = Promise.resolve(web.objects[object][UTF8ToString(method)](...values));
    } catch (e) {
        promise = Promise.reject(e);
    }
    promise.then(
        (value) => callback(user_data, 0, typeof value === 'object' && value !== null ? web.keep(value) : 0),
        (e) => callback(user_data, web.error(e), 0));
});

EM_JS(void, echo_web_set_listener, (int object, const char *type, echo_web_listener listener, void *user_data), {
    const web = Module.echoWeb;
    const target = web.objects[object];
    const name = UTF8ToString(type);
    let listeners = web.listeners.get(target);
    if (!listeners) {
        listeners = {};
        web.listeners.set(target, listeners);
    }
    if (listeners[name]) target.removeEventListener(name, listeners[name]);
    delete listeners[name];
    if (!listener) return;
    const callback = getWasmTableEntry(listener);
    listeners[name] = () => callback(user_data);
    target.addEventListener(name, listeners[name]);
});

EM_JS(void, echo_web_copy_from_channel, (int buffer, int channel, float *destination, int length), {
    Module.echoWeb.objects[buffer].copyFromChannel(HEAPF32.subarray(destination >> 2, (destination >> 2) + length), channel);
});
#endif
