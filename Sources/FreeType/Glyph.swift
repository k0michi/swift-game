import CFreeType

// FT_LOAD_*
public struct LoadFlags: OptionSet, Sendable {
    public let rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    public static let `default` = Self(rawValue: CFreeType_LOAD_DEFAULT)
    public static let noScale = Self(rawValue: CFreeType_LOAD_NO_SCALE)
    public static let noHinting = Self(rawValue: CFreeType_LOAD_NO_HINTING)
    public static let render = Self(rawValue: CFreeType_LOAD_RENDER)
    public static let noBitmap = Self(rawValue: CFreeType_LOAD_NO_BITMAP)
    public static let verticalLayout = Self(rawValue: CFreeType_LOAD_VERTICAL_LAYOUT)
    public static let forceAutohint = Self(rawValue: CFreeType_LOAD_FORCE_AUTOHINT)
    public static let cropBitmap = Self(rawValue: CFreeType_LOAD_CROP_BITMAP)
    public static let pedantic = Self(rawValue: CFreeType_LOAD_PEDANTIC)
    public static let ignoreGlobalAdvanceWidth = Self(rawValue: CFreeType_LOAD_IGNORE_GLOBAL_ADVANCE_WIDTH)
    public static let noRecurse = Self(rawValue: CFreeType_LOAD_NO_RECURSE)
    public static let ignoreTransform = Self(rawValue: CFreeType_LOAD_IGNORE_TRANSFORM)
    public static let monochrome = Self(rawValue: CFreeType_LOAD_MONOCHROME)
    public static let linearDesign = Self(rawValue: CFreeType_LOAD_LINEAR_DESIGN)
    public static let sbitsOnly = Self(rawValue: CFreeType_LOAD_SBITS_ONLY)
    public static let noAutohint = Self(rawValue: CFreeType_LOAD_NO_AUTOHINT)
    public static let color = Self(rawValue: CFreeType_LOAD_COLOR)
    public static let computeMetrics = Self(rawValue: CFreeType_LOAD_COMPUTE_METRICS)
    public static let bitmapMetricsOnly = Self(rawValue: CFreeType_LOAD_BITMAP_METRICS_ONLY)
    public static let noSVG = Self(rawValue: CFreeType_LOAD_NO_SVG)
    public static let targetNormal = Self(rawValue: CFreeType_LOAD_TARGET_NORMAL)
    public static let targetLight = Self(rawValue: CFreeType_LOAD_TARGET_LIGHT)
    public static let targetMono = Self(rawValue: CFreeType_LOAD_TARGET_MONO)
    public static let targetLCD = Self(rawValue: CFreeType_LOAD_TARGET_LCD)
    public static let targetLCDV = Self(rawValue: CFreeType_LOAD_TARGET_LCD_V)
}

// FT_Render_Mode
public enum RenderMode: UInt32, Sendable {
    case normal = 0
    case light = 1
    case mono = 2
    case lcd = 3
    case lcdV = 4
    case sdf = 5
}

// FT_Pixel_Mode
public enum PixelMode: UInt8, Sendable {
    case none = 0
    case mono = 1
    case gray = 2
    case gray2 = 3
    case gray4 = 4
    case lcd = 5
    case lcdV = 6
    case bgra = 7
}

// FT_Vector, in 26.6 fixed point where it is a position or a distance.
public struct Vector: Equatable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    init(_ vector: FT_Vector) {
        self.init(x: Int(vector.x), y: Int(vector.y))
    }
}

// FT_Glyph_Metrics, in 26.6 fixed point unless loaded with noScale.
public struct GlyphMetrics: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var horiBearingX: Int
    public var horiBearingY: Int
    public var horiAdvance: Int
    public var vertBearingX: Int
    public var vertBearingY: Int
    public var vertAdvance: Int

    init(_ metrics: FT_Glyph_Metrics) {
        width = Int(metrics.width)
        height = Int(metrics.height)
        horiBearingX = Int(metrics.horiBearingX)
        horiBearingY = Int(metrics.horiBearingY)
        horiAdvance = Int(metrics.horiAdvance)
        vertBearingX = Int(metrics.vertBearingX)
        vertBearingY = Int(metrics.vertBearingY)
        vertAdvance = Int(metrics.vertAdvance)
    }
}

// FT_Bitmap with a copy of its buffer: rows of pitch bytes, top to bottom
// when pitch is positive.
public struct Bitmap: Equatable, Sendable {
    public var rows: UInt32
    public var width: UInt32
    public var pitch: Int32
    public var buffer: [UInt8]
    public var numGrays: UInt16
    public var pixelMode: PixelMode?

    init(_ bitmap: FT_Bitmap) {
        rows = bitmap.rows
        width = bitmap.width
        pitch = bitmap.pitch
        let count = Int(bitmap.rows) * Int(bitmap.pitch.magnitude)
        buffer = bitmap.buffer.map { Array(UnsafeBufferPointer(start: $0, count: count)) } ?? []
        numGrays = bitmap.num_grays
        pixelMode = PixelMode(rawValue: bitmap.pixel_mode)
    }
}

// FT_GlyphSlot: the face's one, which each load replaces.
public struct GlyphSlot {
    let face: Face

    var pointer: FT_GlyphSlot { face.pointer.pointee.glyph }

    // FT_GlyphSlotRec.glyph_index
    public var glyphIndex: UInt32 { pointer.pointee.glyph_index }
    // FT_GlyphSlotRec.metrics
    public var metrics: GlyphMetrics { GlyphMetrics(pointer.pointee.metrics) }
    // FT_GlyphSlotRec.advance
    public var advance: Vector { Vector(pointer.pointee.advance) }
    // FT_GlyphSlotRec.bitmap
    public var bitmap: Bitmap { Bitmap(pointer.pointee.bitmap) }
    // FT_GlyphSlotRec.bitmap_left
    public var bitmapLeft: Int32 { pointer.pointee.bitmap_left }
    // FT_GlyphSlotRec.bitmap_top
    public var bitmapTop: Int32 { pointer.pointee.bitmap_top }
}

// FT_Load_Glyph
public func loadGlyph(face: Face, glyphIndex: UInt32, loadFlags: LoadFlags) throws {
    try check("FT_Load_Glyph", FT_Load_Glyph(face.pointer, glyphIndex, loadFlags.rawValue))
}

// FT_Load_Char
public func loadChar(face: Face, charCode: UInt32, loadFlags: LoadFlags) throws {
    try check("FT_Load_Char", FT_Load_Char(face.pointer, FT_ULong(charCode), loadFlags.rawValue))
}

// FT_Render_Glyph
public func renderGlyph(slot: GlyphSlot, renderMode: RenderMode) throws {
    // C enums are Int32 on Windows and UInt32 elsewhere.
    let mode = FT_Render_Mode(FT_Render_Mode.RawValue(truncatingIfNeeded: renderMode.rawValue))
    try check("FT_Render_Glyph", FT_Render_Glyph(slot.pointer, mode))
}
