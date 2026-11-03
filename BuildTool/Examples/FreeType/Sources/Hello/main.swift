import CFreeType
import Foundation

// Reads the font that BuildTool put beside the executable.
let directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let font = try Data(contentsOf: directory.appendingPathComponent("NotoSansJP-Regular.otf"))

var library: FT_Library?
precondition(FT_Init_FreeType(&library) == 0)
var (major, minor, patch): (FT_Int, FT_Int, FT_Int) = (0, 0, 0)
FT_Library_Version(library, &major, &minor, &patch)
print("FreeType \(major).\(minor).\(patch)")

let bytes = [UInt8](font)
var face: FT_Face?
precondition(FT_New_Memory_Face(library, bytes, FT_Long(bytes.count), 0, &face) == 0)
print("\(String(cString: face!.pointee.family_name)): \(face!.pointee.num_glyphs) glyphs")
FT_Done_Face(face)
FT_Done_FreeType(library)
