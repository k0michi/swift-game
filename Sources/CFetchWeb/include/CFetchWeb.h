#ifndef C_FETCH_WEB_H
#define C_FETCH_WEB_H

#ifdef __EMSCRIPTEN__

// Responses, errors and bodies are named by handles into a table; each is
// released with fetch_web_release.

void fetch_web_release(int object);

// fetch(url, {method, headers, body}). headers are "name: value\r\n" lines,
// and body is sent when has_body is not 0. settle gets a handle to the
// response, or to the error the promise was rejected with.
typedef void (*fetch_web_settle)(void *user_data, int response, int error);
void fetch_web_fetch(
    const char *url, const char *method, const char *headers,
    const unsigned char *body, int body_length, int has_body,
    fetch_web_settle settle, void *user_data);

// response.status, or response.redirected as 0 or 1.
int fetch_web_get_number(int object, const char *property);
// Writes a property, such as a response's statusText or url or an error's
// message, null-terminated, into `buffer` if `size` is enough and returns
// its length in UTF-8 bytes without the terminator. A response's "headers"
// are "name: value\r\n" lines.
int fetch_web_get_string(int object, const char *property, char *buffer, int size);

// response.arrayBuffer(). settle gets a handle to the bytes and their
// length, or 0 and a handle to the error.
typedef void (*fetch_web_settle_bytes)(void *user_data, int bytes, int length, int error);
void fetch_web_response_bytes(int response, fetch_web_settle_bytes settle, void *user_data);
// Copies the bytes into `destination`, which has room for all of them.
void fetch_web_copy_bytes(int bytes, unsigned char *destination);

#endif

#endif
