#ifndef C_GAME_TOOLKIT_WEB_H
#define C_GAME_TOOLKIT_WEB_H

#ifdef __EMSCRIPTEN__

// Has the browser download `length` bytes as a file named `name`, of the
// media type `type`.
void game_toolkit_web_download(const char *name, const unsigned char *bytes, int length, const char *type);

#endif

#endif
