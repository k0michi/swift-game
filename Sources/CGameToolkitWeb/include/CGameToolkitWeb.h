#ifndef C_GAME_TOOLKIT_WEB_H
#define C_GAME_TOOLKIT_WEB_H

#ifdef __EMSCRIPTEN__

// Whether the page holds the pointer lock, 1 if so.
int game_toolkit_web_pointer_is_locked(void);

// Has the browser download `length` bytes as a file named `name`, of the
// media type `type`.
void game_toolkit_web_download(const char *name, const unsigned char *bytes, int length, const char *type);

// Called when a fetch has finished: with the response's bytes, which
// game_toolkit_web_take copies, under `id` and of `length`, or with an `id` of
// 0 and the response's HTTP status, 0 if there was none.
typedef void (*game_toolkit_web_fetched)(void *context, int id, int length, int status);

// Has the browser fetch `url`, and calls `fetched` with `context` when it has.
void game_toolkit_web_fetch(const char *url, void *context, game_toolkit_web_fetched fetched);

// Copies the bytes fetched under `id` into `bytes`, and forgets them.
void game_toolkit_web_take(int id, unsigned char *bytes);

#endif

#endif
