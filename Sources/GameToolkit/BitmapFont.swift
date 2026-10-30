import VectorMath

/// A 5×7 dot font for printable ASCII, drawn as rectangles with no texture.
///
/// Each glyph's shape is a string of seven rows of five characters, separated
/// by spaces: `#` for a lit dot and `.` for an unlit one.
public enum BitmapFont {
    public static let glyphWidth = 5
    public static let glyphHeight = 7
    /// Horizontal distance between glyphs, in dots, including one dot of spacing.
    public static let advance = 6

    private static let shapes: [(Character, String)] = [
        (" ", "..... ..... ..... ..... ..... ..... ....."),
        ("!", "..#.. ..#.. ..#.. ..#.. ..#.. ..... ..#.."),
        ("\"", ".#.#. .#.#. ..... ..... ..... ..... ....."),
        ("#", ".#.#. .#.#. ##### .#.#. ##### .#.#. .#.#."),
        ("$", "..#.. .#### #.#.. .###. ..#.# ####. ..#.."),
        ("%", "##... ##..# ...#. ..#.. .#... #..## ...##"),
        ("&", ".##.. #..#. #.#.. .#... #.#.# #..#. .##.#"),
        ("'", "..#.. ..#.. ..... ..... ..... ..... ....."),
        ("(", "...#. ..#.. .#... .#... .#... ..#.. ...#."),
        (")", ".#... ..#.. ...#. ...#. ...#. ..#.. .#..."),
        ("*", "..... ..#.. #.#.# .###. #.#.# ..#.. ....."),
        ("+", "..... ..#.. ..#.. ##### ..#.. ..#.. ....."),
        (",", "..... ..... ..... ..... .##.. ..#.. .#..."),
        ("-", "..... ..... ..... ##### ..... ..... ....."),
        (".", "..... ..... ..... ..... ..... .##.. .##.."),
        ("/", "..... ....# ...#. ..#.. .#... #.... ....."),
        ("0", ".###. #...# #..## #.#.# ##..# #...# .###."),
        ("1", "..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###."),
        ("2", ".###. #...# ....# ...#. ..#.. .#... #####"),
        ("3", "##### ...#. ..#.. ...#. ....# #...# .###."),
        ("4", "...#. ..##. .#.#. #..#. ##### ...#. ...#."),
        ("5", "##### #.... ####. ....# ....# #...# .###."),
        ("6", "..##. .#... #.... ####. #...# #...# .###."),
        ("7", "##### ....# ...#. ..#.. .#... .#... .#..."),
        ("8", ".###. #...# #...# .###. #...# #...# .###."),
        ("9", ".###. #...# #...# .#### ....# ...#. .##.."),
        (":", "..... .##.. .##.. ..... .##.. .##.. ....."),
        (";", "..... .##.. .##.. ..... .##.. ..#.. .#..."),
        ("<", "...#. ..#.. .#... #.... .#... ..#.. ...#."),
        ("=", "..... ..... ##### ..... ##### ..... ....."),
        (">", ".#... ..#.. ...#. ....# ...#. ..#.. .#..."),
        ("?", ".###. #...# ....# ...#. ..#.. ..... ..#.."),
        ("@", ".###. #...# ....# .##.# #.#.# #.#.# .###."),
        ("A", ".###. #...# #...# ##### #...# #...# #...#"),
        ("B", "####. #...# #...# ####. #...# #...# ####."),
        ("C", ".###. #...# #.... #.... #.... #...# .###."),
        ("D", "###.. #..#. #...# #...# #...# #..#. ###.."),
        ("E", "##### #.... #.... ####. #.... #.... #####"),
        ("F", "##### #.... #.... ####. #.... #.... #...."),
        ("G", ".###. #...# #.... #.### #...# #...# .####"),
        ("H", "#...# #...# #...# ##### #...# #...# #...#"),
        ("I", ".###. ..#.. ..#.. ..#.. ..#.. ..#.. .###."),
        ("J", "..### ...#. ...#. ...#. ...#. #..#. .##.."),
        ("K", "#...# #..#. #.#.. ##... #.#.. #..#. #...#"),
        ("L", "#.... #.... #.... #.... #.... #.... #####"),
        ("M", "#...# ##.## #.#.# #.#.# #...# #...# #...#"),
        ("N", "#...# #...# ##..# #.#.# #..## #...# #...#"),
        ("O", ".###. #...# #...# #...# #...# #...# .###."),
        ("P", "####. #...# #...# ####. #.... #.... #...."),
        ("Q", ".###. #...# #...# #...# #.#.# #..#. .##.#"),
        ("R", "####. #...# #...# ####. #.#.. #..#. #...#"),
        ("S", ".#### #.... #.... .###. ....# ....# ####."),
        ("T", "##### ..#.. ..#.. ..#.. ..#.. ..#.. ..#.."),
        ("U", "#...# #...# #...# #...# #...# #...# .###."),
        ("V", "#...# #...# #...# #...# #...# .#.#. ..#.."),
        ("W", "#...# #...# #...# #.#.# #.#.# #.#.# .#.#."),
        ("X", "#...# #...# .#.#. ..#.. .#.#. #...# #...#"),
        ("Y", "#...# #...# .#.#. ..#.. ..#.. ..#.. ..#.."),
        ("Z", "##### ....# ...#. ..#.. .#... #.... #####"),
        ("[", ".###. .#... .#... .#... .#... .#... .###."),
        ("\\", "..... #.... .#... ..#.. ...#. ....# ....."),
        ("]", ".###. ...#. ...#. ...#. ...#. ...#. .###."),
        ("^", "..#.. .#.#. #...# ..... ..... ..... ....."),
        ("_", "..... ..... ..... ..... ..... ..... #####"),
        ("`", ".#... ..#.. ..... ..... ..... ..... ....."),
        ("a", "..... ..... .###. ....# .#### #...# .####"),
        ("b", "#.... #.... #.##. ##..# #...# #...# ####."),
        ("c", "..... ..... .###. #.... #.... #...# .###."),
        ("d", "....# ....# .##.# #..## #...# #...# .####"),
        ("e", "..... ..... .###. #...# ##### #.... .###."),
        ("f", "..##. .#..# .#... ###.. .#... .#... .#..."),
        ("g", "..... .#### #...# #...# .#### ....# .###."),
        ("h", "#.... #.... #.##. ##..# #...# #...# #...#"),
        ("i", "..#.. ..... .##.. ..#.. ..#.. ..#.. .###."),
        ("j", "...#. ..... ..##. ...#. ...#. #..#. .##.."),
        ("k", "#.... #.... #..#. #.#.. ##... #.#.. #..#."),
        ("l", ".##.. ..#.. ..#.. ..#.. ..#.. ..#.. .###."),
        ("m", "..... ..... ##.#. #.#.# #.#.# #...# #...#"),
        ("n", "..... ..... #.##. ##..# #...# #...# #...#"),
        ("o", "..... ..... .###. #...# #...# #...# .###."),
        ("p", "..... ..... ####. #...# ####. #.... #...."),
        ("q", "..... ..... .##.# #..## .#### ....# ....#"),
        ("r", "..... ..... #.##. ##..# #.... #.... #...."),
        ("s", "..... ..... .###. #.... .###. ....# ####."),
        ("t", ".#... .#... ###.. .#... .#... .#..# ..##."),
        ("u", "..... ..... #...# #...# #...# #..## .##.#"),
        ("v", "..... ..... #...# #...# #...# .#.#. ..#.."),
        ("w", "..... ..... #...# #...# #.#.# #.#.# .#.#."),
        ("x", "..... ..... #...# .#.#. ..#.. .#.#. #...#"),
        ("y", "..... ..... #...# #...# .#### ....# .###."),
        ("z", "..... ..... ##### ...#. ..#.. .#... #####"),
        ("{", "...#. ..#.. ..#.. .#... ..#.. ..#.. ...#."),
        ("|", "..#.. ..#.. ..#.. ..#.. ..#.. ..#.. ..#.."),
        ("}", ".#... ..#.. ..#.. ...#. ..#.. ..#.. .#..."),
        ("~", "..... ..... .#... #.#.# ...#. ..... ....."),
    ]

    /// Each glyph's rows as bit masks, indexed by ASCII code; bit 4 is the
    /// leftmost dot. Built once from `shapes`, which it checks.
    private static let glyphs: [[UInt8]?] = {
        var glyphs = [[UInt8]?](repeating: nil, count: 128)
        for (character, shape) in shapes {
            guard let code = character.asciiValue else {
                fatalError("BitmapFont: \(character) is not ASCII")
            }
            let rows = shape.split(separator: " ")
            precondition(rows.count == glyphHeight, "BitmapFont: \(character) needs \(glyphHeight) rows")
            glyphs[Int(code)] = rows.map { row in
                precondition(row.count == glyphWidth, "BitmapFont: \(character) needs rows of \(glyphWidth) dots")
                return row.reduce(0) { bits, dot in
                    precondition(dot == "#" || dot == ".", "BitmapFont: \(character) uses \(dot)")
                    return bits << 1 | (dot == "#" ? 1 : 0)
                }
            }
        }
        return glyphs
    }()

    /// The width of `text` in pixels, without the spacing after the last glyph.
    public static func width(of text: String, scale: Float) -> Float {
        let count = text.unicodeScalars.count
        return count == 0 ? 0 : Float(count * advance - 1) * scale
    }

    /// Appends rectangles drawing `text` with its top-left corner at `origin`,
    /// each dot `scale` pixels square. Characters outside printable ASCII
    /// draw as `?`.
    public static func appendText(
        _ text: String, at origin: Vector2<Float>, scale: Float, color: Vector4<Float>, to batch: inout ShapeBatch
    ) {
        var glyphOrigin = origin
        for scalar in text.unicodeScalars {
            let code = scalar.isASCII ? Int(scalar.value) : 0
            if let rows = glyphs[code] ?? glyphs[Int(Character("?").asciiValue!)] {
                appendGlyph(rows, at: glyphOrigin, scale: scale, color: color, to: &batch)
            }
            glyphOrigin.x += Float(advance) * scale
        }
    }

    /// One rectangle per run of lit dots in a row.
    private static func appendGlyph(
        _ rows: [UInt8], at origin: Vector2<Float>, scale: Float, color: Vector4<Float>, to batch: inout ShapeBatch
    ) {
        for (rowIndex, bits) in rows.enumerated() {
            let top = origin.y + Float(rowIndex) * scale
            var column = 0
            while column < glyphWidth {
                guard bits & (1 << (glyphWidth - 1 - column)) != 0 else {
                    column += 1
                    continue
                }
                let start = column
                while column < glyphWidth && bits & (1 << (glyphWidth - 1 - column)) != 0 {
                    column += 1
                }
                batch.appendRect(
                    from: Vector2(origin.x + Float(start) * scale, top),
                    to: Vector2(origin.x + Float(column) * scale, top + scale), color: color)
            }
        }
    }
}
