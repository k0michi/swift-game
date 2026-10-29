#ifndef C_ECHO_WEB_H
#define C_ECHO_WEB_H

#ifdef __EMSCRIPTEN__

// JavaScript objects are named by handles into a table; 0 names none. Each
// handle a function returns is released with echo_web_release.
//
// Functions that can fail return an error: 0 for none, or the DOMException or
// RangeError the browser threw, as ECHO_WEB_ERROR_*.
enum {
    ECHO_WEB_ERROR_NONE = 0,
    ECHO_WEB_ERROR_INVALID_ACCESS = 1,
    ECHO_WEB_ERROR_INVALID_STATE = 2,
    ECHO_WEB_ERROR_INDEX_SIZE = 3,
    ECHO_WEB_ERROR_NOT_SUPPORTED = 4,
    ECHO_WEB_ERROR_RANGE = 5,
};

void echo_web_release(int object);

// new <constructor>(options) when context is 0, and
// new <constructor>(context, options) otherwise. options is JSON.
int echo_web_new(const char *constructor, int context, const char *options, int *error);

double echo_web_get_number(int object, const char *property);
int echo_web_set_number(int object, const char *property, double value);
// Writes the string, null-terminated, into `buffer` if `size` is enough and
// returns its length in UTF-8 bytes without the terminator.
int echo_web_get_string(int object, const char *property, char *buffer, int size);
int echo_web_set_string(int object, const char *property, const char *value);
int echo_web_get_object(int object, const char *property);

// object[method](target, ...arguments), leaving target out when it is 0.
int echo_web_call(int object, const char *method, int target, const double *arguments, int count);
// object[method](new Float32Array(values), ...arguments)
int echo_web_call_with_floats(
    int object, const char *method, const float *values, int value_count,
    const double *arguments, int count);

// object[property] = new Float32Array(values), or null when values is NULL.
int echo_web_set_floats(int object, const char *property, const float *values, int value_count);

// Calls a method that returns a promise. When it settles, settle gets the
// error, or a handle to the value if it is an object.
typedef void (*echo_web_settle)(void *user_data, int error, int value);
void echo_web_call_async(
    int object, const char *method, const double *arguments, int count,
    echo_web_settle settle, void *user_data);

// Calls `listener` on each event until it is set again; NULL removes it.
typedef void (*echo_web_listener)(void *user_data);
void echo_web_set_listener(int object, const char *type, echo_web_listener listener, void *user_data);

// Copies channel `channel` of an AudioBuffer into `destination`.
void echo_web_copy_from_channel(int buffer, int channel, float *destination, int length);

#endif

#endif
