import CHarfBuzz

// hb_font_t, which holds a reference to its face.
public final class Font {
    let pointer: OpaquePointer

    fileprivate init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        hb_font_destroy(pointer)
    }
}

// hb_font_create
public func fontCreate(face: Face) -> Font {
    Font(pointer: hb_font_create(face.pointer))
}

// hb_font_set_scale
public func fontSetScale(font: Font, xScale: Int32, yScale: Int32) {
    hb_font_set_scale(font.pointer, xScale, yScale)
}

// hb_font_get_scale
public func fontGetScale(font: Font) -> (xScale: Int32, yScale: Int32) {
    var xScale: Int32 = 0
    var yScale: Int32 = 0
    hb_font_get_scale(font.pointer, &xScale, &yScale)
    return (xScale, yScale)
}
