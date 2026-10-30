import CStbImageWrite

// stbi_write_func: called with the bytes written so far, which last only
// during the call.
public typealias WriteFunc = (_ data: UnsafeRawBufferPointer) -> Void

// stb_image_write reads y rows of x pixels of `comp` channels each, the rows
// `strideInBytes` apart, or packed when it is 0, which `count` elements of
// `data` must hold.
private func checkSize(_ operation: String, _ count: Int, x: Int32, y: Int32, comp: Int32, strideInBytes: Int32 = 0) throws {
    let row = Int(x) * Int(comp)
    let stride = strideInBytes == 0 ? row : Int(strideInBytes)
    guard x > 0, y > 0, (1...4).contains(comp), stride >= row, count >= (Int(y) - 1) * stride + row else {
        throw StbImageWriteError(operation: operation, message: "data does not hold \(x)x\(y) pixels of \(comp) channels")
    }
}

private func write(_ operation: String, _ body: () -> Int32) throws {
    guard body() != 0 else {
        throw StbImageWriteError(operation: operation, message: "could not write the image")
    }
}

private func write(
    _ operation: String,
    _ function: WriteFunc,
    _ body: (_ function: @escaping @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32) -> Void,
             _ context: UnsafeMutableRawPointer) -> Int32
) throws {
    try withoutActuallyEscaping(function) { function in
        var function = function
        try withUnsafeMutablePointer(to: &function) { context in
            try write(operation) {
                body({ context, data, size in
                    context!.assumingMemoryBound(to: WriteFunc.self).pointee(
                        UnsafeRawBufferPointer(start: data, count: Int(size)))
                }, context)
            }
        }
    }
}

// stbi_write_png
public func writePng(
    filename: String, w: Int32, h: Int32, comp: Int32, data: UnsafeRawBufferPointer, strideInBytes: Int32
) throws {
    try checkSize("stbi_write_png", data.count, x: w, y: h, comp: comp, strideInBytes: strideInBytes)
    try write("stbi_write_png") { stbi_write_png(filename, w, h, comp, data.baseAddress, strideInBytes) }
}

// stbi_write_bmp
public func writeBmp(filename: String, w: Int32, h: Int32, comp: Int32, data: UnsafeRawBufferPointer) throws {
    try checkSize("stbi_write_bmp", data.count, x: w, y: h, comp: comp)
    try write("stbi_write_bmp") { stbi_write_bmp(filename, w, h, comp, data.baseAddress) }
}

// stbi_write_tga
public func writeTga(filename: String, w: Int32, h: Int32, comp: Int32, data: UnsafeRawBufferPointer) throws {
    try checkSize("stbi_write_tga", data.count, x: w, y: h, comp: comp)
    try write("stbi_write_tga") { stbi_write_tga(filename, w, h, comp, data.baseAddress) }
}

// stbi_write_hdr
public func writeHdr(filename: String, w: Int32, h: Int32, comp: Int32, data: UnsafeBufferPointer<Float>) throws {
    try checkSize("stbi_write_hdr", data.count, x: w, y: h, comp: comp)
    try write("stbi_write_hdr") { stbi_write_hdr(filename, w, h, comp, data.baseAddress) }
}

// stbi_write_jpg
public func writeJpg(
    filename: String, x: Int32, y: Int32, comp: Int32, data: UnsafeRawBufferPointer, quality: Int32
) throws {
    try checkSize("stbi_write_jpg", data.count, x: x, y: y, comp: comp)
    try write("stbi_write_jpg") { stbi_write_jpg(filename, x, y, comp, data.baseAddress, quality) }
}

// stbi_write_png_to_func
public func writePngToFunc(
    func function: WriteFunc, w: Int32, h: Int32, comp: Int32, data: UnsafeRawBufferPointer, strideInBytes: Int32
) throws {
    try checkSize("stbi_write_png_to_func", data.count, x: w, y: h, comp: comp, strideInBytes: strideInBytes)
    try write("stbi_write_png_to_func", function) { function, context in
        stbi_write_png_to_func(function, context, w, h, comp, data.baseAddress, strideInBytes)
    }
}

// stbi_write_bmp_to_func
public func writeBmpToFunc(func function: WriteFunc, w: Int32, h: Int32, comp: Int32, data: UnsafeRawBufferPointer) throws {
    try checkSize("stbi_write_bmp_to_func", data.count, x: w, y: h, comp: comp)
    try write("stbi_write_bmp_to_func", function) { function, context in
        stbi_write_bmp_to_func(function, context, w, h, comp, data.baseAddress)
    }
}

// stbi_write_tga_to_func
public func writeTgaToFunc(func function: WriteFunc, w: Int32, h: Int32, comp: Int32, data: UnsafeRawBufferPointer) throws {
    try checkSize("stbi_write_tga_to_func", data.count, x: w, y: h, comp: comp)
    try write("stbi_write_tga_to_func", function) { function, context in
        stbi_write_tga_to_func(function, context, w, h, comp, data.baseAddress)
    }
}

// stbi_write_hdr_to_func
public func writeHdrToFunc(func function: WriteFunc, w: Int32, h: Int32, comp: Int32, data: UnsafeBufferPointer<Float>) throws {
    try checkSize("stbi_write_hdr_to_func", data.count, x: w, y: h, comp: comp)
    try write("stbi_write_hdr_to_func", function) { function, context in
        stbi_write_hdr_to_func(function, context, w, h, comp, data.baseAddress)
    }
}

// stbi_write_jpg_to_func
public func writeJpgToFunc(
    func function: WriteFunc, x: Int32, y: Int32, comp: Int32, data: UnsafeRawBufferPointer, quality: Int32
) throws {
    try checkSize("stbi_write_jpg_to_func", data.count, x: x, y: y, comp: comp)
    try write("stbi_write_jpg_to_func", function) { function, context in
        stbi_write_jpg_to_func(function, context, x, y, comp, data.baseAddress, quality)
    }
}

// stbi_flip_vertically_on_write
public func flipVerticallyOnWrite(_ flagBoolean: Bool) {
    stbi_flip_vertically_on_write(flagBoolean ? 1 : 0)
}
