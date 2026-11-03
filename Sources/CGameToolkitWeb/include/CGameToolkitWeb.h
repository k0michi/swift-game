#ifndef C_GAME_TOOLKIT_WEB_H
#define C_GAME_TOOLKIT_WEB_H

#ifdef __EMSCRIPTEN__

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

// Called with what the text input element brings: with a `kind` of 0, the
// text an input method is composing, empty when it is done, and of 1, text
// entered. `text` is UTF-8, which game_toolkit_web_free frees.
typedef void (*game_toolkit_web_text_input_changed)(void *context, int kind, char *text);

// Focuses an input element of its own, which it makes the first time, for the
// browser and its input methods to enter text into, and calls `changed` with
// `context` with what they enter, until game_toolkit_web_stop_text_input.
void game_toolkit_web_start_text_input(void *context, game_toolkit_web_text_input_changed changed);

void game_toolkit_web_stop_text_input(void);

// Places the input element `x`, `y` CSS pixels from the canvas's top-left
// corner, `width` by `height`, where the input method shows what it composes.
void game_toolkit_web_set_text_input_area(double x, double y, double width, double height);

// Frees what the browser allocated for C.
void game_toolkit_web_free(void *pointer);

#endif

#endif
