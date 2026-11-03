import CFreeType
import CHarfBuzz
import CSDL3

#if !os(Emscripten)
    import Foundation
#endif

let version = SDL_GetVersion()
print("SDL \(version / 1_000_000).\(version / 1000 % 1000).\(version % 1000)")
print("HarfBuzz \(String(cString: hb_version_string()))")

var library: FT_Library?
precondition(FT_Init_FreeType(&library) == 0)
var (major, minor, patch): (FT_Int, FT_Int, FT_Int) = (0, 0, 0)
FT_Library_Version(library, &major, &minor, &patch)
print("FreeType \(major).\(minor).\(patch)")

// Reads the font that BuildTool put beside the executable, which a page has
// no file system to read from.
#if !os(Emscripten)
    let directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    let bytes = [UInt8](try Data(contentsOf: directory.appendingPathComponent("NotoSansJP-Regular.otf")))
    var face: FT_Face?
    precondition(FT_New_Memory_Face(library, bytes, FT_Long(bytes.count), 0, &face) == 0)
    print("\(String(cString: face!.pointee.family_name)): \(face!.pointee.num_glyphs) glyphs")
    FT_Done_Face(face)
#endif
FT_Done_FreeType(library)
