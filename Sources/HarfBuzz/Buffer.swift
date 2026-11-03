import CHarfBuzz

// hb_buffer_t
public final class Buffer {
    let pointer: OpaquePointer

    fileprivate init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        hb_buffer_destroy(pointer)
    }
}

// hb_glyph_info_t: after shaping, the glyph's index in `codepoint`.
public struct GlyphInfo: Equatable, Sendable {
    public var codepoint: UInt32
    public var cluster: UInt32
}

// hb_glyph_position_t, in the font's scale.
public struct GlyphPosition: Equatable, Sendable {
    public var xAdvance: Int32
    public var yAdvance: Int32
    public var xOffset: Int32
    public var yOffset: Int32
}

// hb_buffer_create
public func bufferCreate() -> Buffer {
    Buffer(pointer: hb_buffer_create())
}

// hb_buffer_reset
public func bufferReset(buffer: Buffer) {
    hb_buffer_reset(buffer.pointer)
}

// hb_buffer_add_utf8, of all of `text`.
public func bufferAddUTF8(buffer: Buffer, text: String, itemOffset: UInt32 = 0, itemLength: Int32 = -1) {
    var text = text
    text.withUTF8 {
        $0.withMemoryRebound(to: CChar.self) {
            hb_buffer_add_utf8(buffer.pointer, $0.baseAddress, Int32($0.count), itemOffset, itemLength)
        }
    }
}

// hb_buffer_guess_segment_properties
public func bufferGuessSegmentProperties(buffer: Buffer) {
    hb_buffer_guess_segment_properties(buffer.pointer)
}

// hb_buffer_set_direction
public func bufferSetDirection(buffer: Buffer, direction: Direction) {
    hb_buffer_set_direction(buffer.pointer, hb_direction_t(rawValue: direction.rawValue))
}

// hb_buffer_get_direction
public func bufferGetDirection(buffer: Buffer) -> Direction {
    Direction(rawValue: hb_buffer_get_direction(buffer.pointer).rawValue) ?? .invalid
}

// hb_buffer_set_script
public func bufferSetScript(buffer: Buffer, script: Script) {
    hb_buffer_set_script(buffer.pointer, hb_script_t(rawValue: script.rawValue))
}

// hb_buffer_get_script
public func bufferGetScript(buffer: Buffer) -> Script {
    Script(rawValue: hb_buffer_get_script(buffer.pointer).rawValue)
}

// hb_buffer_set_language
public func bufferSetLanguage(buffer: Buffer, language: Language) {
    hb_buffer_set_language(buffer.pointer, language.pointer)
}

// hb_buffer_get_language
public func bufferGetLanguage(buffer: Buffer) -> Language {
    Language(pointer: hb_buffer_get_language(buffer.pointer))
}

// hb_buffer_get_length
public func bufferGetLength(buffer: Buffer) -> UInt32 {
    hb_buffer_get_length(buffer.pointer)
}

// hb_buffer_get_glyph_infos
public func bufferGetGlyphInfos(buffer: Buffer) -> [GlyphInfo] {
    var length: UInt32 = 0
    guard let infos = hb_buffer_get_glyph_infos(buffer.pointer, &length) else { return [] }
    return UnsafeBufferPointer(start: infos, count: Int(length)).map {
        GlyphInfo(codepoint: $0.codepoint, cluster: $0.cluster)
    }
}

// hb_buffer_get_glyph_positions
public func bufferGetGlyphPositions(buffer: Buffer) -> [GlyphPosition] {
    var length: UInt32 = 0
    guard let positions = hb_buffer_get_glyph_positions(buffer.pointer, &length) else { return [] }
    return UnsafeBufferPointer(start: positions, count: Int(length)).map {
        GlyphPosition(xAdvance: $0.x_advance, yAdvance: $0.y_advance, xOffset: $0.x_offset, yOffset: $0.y_offset)
    }
}

// hb_shape
public func shape(font: Font, buffer: Buffer, features: [Feature] = []) {
    let features = features.map(\.cFeature)
    hb_shape(font.pointer, buffer.pointer, features, UInt32(features.count))
}
