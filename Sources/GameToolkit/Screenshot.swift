import Dawn
import SDL3
import StbImageWrite

#if os(Emscripten)
    import CGameToolkitWeb
#endif

public enum ScreenshotError: Error {
    case notCopyable
    case unsupportedFormat(TextureFormat)
    case notMapped
}

/// A texture's pixels, which a command encoder copies into a buffer, for
/// `readPixels` once its commands have run.
public struct TextureCopy {
    let buffer: Buffer
    public let width: UInt32
    public let height: UInt32
    let bytesPerRow: UInt32
    let format: TextureFormat
}

/// Has `encoder` copy `texture`, which must allow copies from it, as
/// `configureSurface` makes a surface's where it can. It must be in an 8-bit
/// RGBA or BGRA format, as surfaces are.
public func copyTexture(_ texture: Texture, device: Device, encoder: CommandEncoder) throws -> TextureCopy {
    guard texture.getUsage().contains(.copySrc) else {
        throw ScreenshotError.notCopyable
    }
    let format = texture.getFormat()
    guard [.rgba8Unorm, .rgba8UnormSrgb, .bgra8Unorm, .bgra8UnormSrgb].contains(format) else {
        throw ScreenshotError.unsupportedFormat(format)
    }
    let width = texture.getWidth()
    let height = texture.getHeight()
    // WebGPU copies rows 256 bytes apart.
    let bytesPerRow = (width * 4 + 255) / 256 * 256
    let buffer = try device.createBuffer(
        descriptor: BufferDescriptor(
            label: "texture copy", usage: [.mapRead, .copyDst], size: UInt64(bytesPerRow) * UInt64(height)))
    encoder.copyTextureToBuffer(
        source: TexelCopyTextureInfo(texture: texture),
        destination: TexelCopyBufferInfo(
            layout: TexelCopyBufferLayout(bytesPerRow: bytesPerRow, rowsPerImage: height), buffer: buffer),
        copySize: Extent3D(width: width, height: height, depthOrArrayLayers: 1))
    return TextureCopy(buffer: buffer, width: width, height: height, bytesPerRow: bytesPerRow, format: format)
}

/// The copied pixels, RGBA rows from the top, opaque. It maps them on the
/// caller's executor, the one that drives Dawn, and arranges them off it.
/// Dawn finishes mapping in `Instance.processEvents`, so a loop that calls it
/// should not wait for this in the meantime.
nonisolated(nonsending) public func readPixels(_ copy: TextureCopy) async throws -> [UInt8] {
    let size = Int(copy.bytesPerRow) * Int(copy.height)
    try await copy.buffer.mapAsync(mode: .read, offset: 0, size: size)
    let rows: [UInt8]
    do {
        defer { copy.buffer.unmap() }
        guard let bytes = copy.buffer.getConstMappedRange(size: size) else {
            throw ScreenshotError.notMapped
        }
        rows = Array(bytes)
    }
    return await rgbaPixels(
        rows, width: Int(copy.width), height: Int(copy.height), bytesPerRow: Int(copy.bytesPerRow),
        isBGRA: copy.format == .bgra8Unorm || copy.format == .bgra8UnormSrgb)
}

// Packs rows `bytesPerRow` apart into RGBA, opaque.
@concurrent
private func rgbaPixels(_ rows: [UInt8], width: Int, height: Int, bytesPerRow: Int, isBGRA: Bool) async -> [UInt8] {
    [UInt8](unsafeUninitializedCapacity: width * height * 4) { pixels, count in
        for y in 0..<height {
            for x in 0..<width {
                let source = y * bytesPerRow + x * 4
                let destination = (y * width + x) * 4
                pixels[destination] = rows[source + (isBGRA ? 2 : 0)]
                pixels[destination + 1] = rows[source + 1]
                pixels[destination + 2] = rows[source + (isBGRA ? 0 : 2)]
                pixels[destination + 3] = 255
            }
        }
        count = pixels.count
    }
}

/// Reads `copy` and saves it with `saveScreenshot(pixels:width:height:)`,
/// returning its name. As with `readPixels`, a loop that calls
/// `Instance.processEvents` should not wait for this.
@discardableResult
nonisolated(nonsending) public func saveScreenshot(_ copy: TextureCopy) async throws -> String {
    try await saveScreenshot(pixels: readPixels(copy), width: copy.width, height: copy.height)
}

/// Saves RGBA pixels, rows from the top, as a PNG named after the local
/// time: into the working directory, or as a download in a browser. Returns
/// its name. It encodes and writes off the caller's executor, so that a game
/// does not stall on it.
@concurrent
@discardableResult
public func saveScreenshot(pixels: [UInt8], width: UInt32, height: UInt32) async throws -> String {
    let time = try timeToDateTime(ticks: getCurrentTime(), localTime: true)
    func twoDigits(_ value: Int32) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
    let name = "screenshot-\(time.year)\(twoDigits(time.month))\(twoDigits(time.day))-"
        + "\(twoDigits(time.hour))\(twoDigits(time.minute))\(twoDigits(time.second)).png"
    try pixels.withUnsafeBytes { data in
        #if os(Emscripten)
            // The browser has the one thread, which this runs on as well.
            var png: [UInt8] = []
            try writePngToFunc(
                func: { png += $0 }, w: Int32(width), h: Int32(height), comp: 4, data: data, strideInBytes: 0)
            game_toolkit_web_download(name, png, Int32(png.count), "image/png")
        #else
            try writePng(filename: name, w: Int32(width), h: Int32(height), comp: 4, data: data, strideInBytes: 0)
        #endif
    }
    return name
}
