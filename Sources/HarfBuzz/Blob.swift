import CHarfBuzz

// hb_blob_t
public final class Blob {
    let pointer: OpaquePointer

    fileprivate init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        hb_blob_destroy(pointer)
    }
}

// hb_blob_create with HB_MEMORY_MODE_DUPLICATE, so that the blob has its own
// copy of the data.
public func blobCreate(data: [UInt8]) -> Blob {
    let pointer = data.withUnsafeBytes {
        hb_blob_create(
            $0.baseAddress?.assumingMemoryBound(to: CChar.self), UInt32($0.count), HB_MEMORY_MODE_DUPLICATE, nil, nil)
    }
    return Blob(pointer: pointer!)
}

// hb_blob_get_length
public func blobGetLength(blob: Blob) -> UInt32 {
    hb_blob_get_length(blob.pointer)
}
