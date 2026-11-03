import CHarfBuzz

// hb_face_t, which holds a reference to its blob.
public final class Face {
    let pointer: OpaquePointer

    fileprivate init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        hb_face_destroy(pointer)
    }
}

// hb_face_create
public func faceCreate(blob: Blob, index: UInt32) -> Face {
    Face(pointer: hb_face_create(blob.pointer, index))
}

// hb_face_get_upem
public func faceGetUpem(face: Face) -> UInt32 {
    hb_face_get_upem(face.pointer)
}

// hb_face_get_glyph_count
public func faceGetGlyphCount(face: Face) -> UInt32 {
    hb_face_get_glyph_count(face.pointer)
}
