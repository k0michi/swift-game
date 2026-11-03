#ifndef CFreeType_h
#define CFreeType_h

#include <ft2build.h>
#include FT_FREETYPE_H

// FT_LOAD_*, as constants: FT_LOAD_TARGET_* are function-like macros, which
// Swift does not import.
extern const FT_Int32 CFreeType_LOAD_DEFAULT;
extern const FT_Int32 CFreeType_LOAD_NO_SCALE;
extern const FT_Int32 CFreeType_LOAD_NO_HINTING;
extern const FT_Int32 CFreeType_LOAD_RENDER;
extern const FT_Int32 CFreeType_LOAD_NO_BITMAP;
extern const FT_Int32 CFreeType_LOAD_VERTICAL_LAYOUT;
extern const FT_Int32 CFreeType_LOAD_FORCE_AUTOHINT;
extern const FT_Int32 CFreeType_LOAD_CROP_BITMAP;
extern const FT_Int32 CFreeType_LOAD_PEDANTIC;
extern const FT_Int32 CFreeType_LOAD_IGNORE_GLOBAL_ADVANCE_WIDTH;
extern const FT_Int32 CFreeType_LOAD_NO_RECURSE;
extern const FT_Int32 CFreeType_LOAD_IGNORE_TRANSFORM;
extern const FT_Int32 CFreeType_LOAD_MONOCHROME;
extern const FT_Int32 CFreeType_LOAD_LINEAR_DESIGN;
extern const FT_Int32 CFreeType_LOAD_SBITS_ONLY;
extern const FT_Int32 CFreeType_LOAD_NO_AUTOHINT;
extern const FT_Int32 CFreeType_LOAD_COLOR;
extern const FT_Int32 CFreeType_LOAD_COMPUTE_METRICS;
extern const FT_Int32 CFreeType_LOAD_BITMAP_METRICS_ONLY;
extern const FT_Int32 CFreeType_LOAD_NO_SVG;
extern const FT_Int32 CFreeType_LOAD_TARGET_NORMAL;
extern const FT_Int32 CFreeType_LOAD_TARGET_LIGHT;
extern const FT_Int32 CFreeType_LOAD_TARGET_MONO;
extern const FT_Int32 CFreeType_LOAD_TARGET_LCD;
extern const FT_Int32 CFreeType_LOAD_TARGET_LCD_V;

// FT_Error_String, which returns NULL unless FreeType is built with
// FT_CONFIG_OPTION_ERROR_STRINGS.
const char *CFreeType_ErrorString(FT_Error error);

#endif
