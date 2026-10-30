import Foundation
import Testing

@testable import StbImage
@testable import StbImageWrite

// 3x2 RGBA pixels, each channel different.
private let pixels: [UInt8] = (0..<24).map { UInt8($0 * 10) }

private func encode(_ body: (WriteFunc) throws -> Void) rethrows -> [UInt8] {
    var bytes: [UInt8] = []
    try body { bytes += $0 }
    return bytes
}

@Suite("stb_image and stb_image_write")
struct StbTests {
    @Test
    func pngRoundTrips() throws {
        let png = try pixels.withUnsafeBytes { data in
            try encode { try writePngToFunc(func: $0, w: 3, h: 2, comp: 4, data: data, strideInBytes: 0) }
        }
        #expect(try infoFromMemory(buffer: png) == (3, 2, 4))
        #expect(!is16BitFromMemory(buffer: png))
        #expect(!isHdrFromMemory(buffer: png))
        let image = try loadFromMemory(buffer: png)
        #expect(image.x == 3 && image.y == 2 && image.channelsInFile == 4)
        #expect(image.data == pixels)
    }

    @Test
    func loadingConvertsToTheDesiredChannels() throws {
        let png = try pixels.withUnsafeBytes { data in
            try encode { try writePngToFunc(func: $0, w: 3, h: 2, comp: 4, data: data, strideInBytes: 0) }
        }
        let image = try loadFromMemory(buffer: png, desiredChannels: 3)
        #expect(image.channelsInFile == 4)
        #expect(image.data.count == 3 * 2 * 3)
        #expect(Array(image.data.prefix(6)) == [0, 10, 20, 40, 50, 60])
    }

    @Test
    func pngReadsRowsAStrideApart() throws {
        // Two rows of 3 RGB pixels, each padded to 12 bytes.
        let padded: [UInt8] = (0..<9).map { UInt8($0) } + [99, 99, 99] + (9..<18).map { UInt8($0) }
        let png = try padded.withUnsafeBytes { data in
            try encode { try writePngToFunc(func: $0, w: 3, h: 2, comp: 3, data: data, strideInBytes: 12) }
        }
        #expect(try loadFromMemory(buffer: png).data == (0..<18).map { UInt8($0) })
    }

    @Test
    func bmpAndTgaRoundTrip() throws {
        let rgb = (0..<18).map { UInt8($0 * 12) }
        let bmp = try rgb.withUnsafeBytes { data in
            try encode { try writeBmpToFunc(func: $0, w: 3, h: 2, comp: 3, data: data) }
        }
        let tga = try rgb.withUnsafeBytes { data in
            try encode { try writeTgaToFunc(func: $0, w: 3, h: 2, comp: 3, data: data) }
        }
        #expect(try loadFromMemory(buffer: bmp).data == rgb)
        #expect(try loadFromMemory(buffer: tga).data == rgb)
    }

    @Test
    func jpgDecodesToTheSameSize() throws {
        let gray = [UInt8](repeating: 128, count: 16 * 16)
        let jpg = try gray.withUnsafeBytes { data in
            try encode { try writeJpgToFunc(func: $0, x: 16, y: 16, comp: 1, data: data, quality: 90) }
        }
        // stb_image_write writes color JPEGs, even of gray pixels.
        let image = try loadFromMemory(buffer: jpg, desiredChannels: 1)
        #expect(image.x == 16 && image.y == 16 && image.data.count == 16 * 16)
        #expect(image.data.allSatisfy { abs(Int($0) - 128) <= 2 })
    }

    @Test
    func hdrRoundTrips() throws {
        let values: [Float] = [0.5, 1, 2, 4, 8, 16]
        let hdr = try values.withUnsafeBufferPointer { data in
            try encode { try writeHdrToFunc(func: $0, w: 2, h: 1, comp: 3, data: data) }
        }
        #expect(isHdrFromMemory(buffer: hdr))
        let image = try loadfFromMemory(buffer: hdr)
        #expect(zip(image.data, values).allSatisfy { abs($0 - $1) <= $1 / 64 })
    }

    @Test
    func loadingCanFlipVertically() throws {
        let png = try pixels.withUnsafeBytes { data in
            try encode { try writePngToFunc(func: $0, w: 3, h: 2, comp: 4, data: data, strideInBytes: 0) }
        }
        setFlipVerticallyOnLoadThread(true)
        defer { setFlipVerticallyOnLoadThread(false) }
        #expect(try loadFromMemory(buffer: png).data == Array(pixels[12...] + pixels[..<12]))
    }

    @Test
    func filesRoundTrip() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("stb-\(UUID().uuidString).png").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        try pixels.withUnsafeBytes { try writePng(filename: path, w: 3, h: 2, comp: 4, data: $0, strideInBytes: 0) }
        #expect(try info(filename: path) == (3, 2, 4))
        #expect(try load(filename: path).data == pixels)
    }

    @Test
    func failuresSayWhy() {
        #expect(throws: StbImageError(operation: "stbi_load_from_memory", message: "unknown image type")) {
            try loadFromMemory(buffer: [1, 2, 3, 4])
        }
        #expect(throws: StbImageError(operation: "stbi_load", message: "can't fopen")) {
            try load(filename: "/nonexistent/image.png")
        }
    }

    @Test
    func writingChecksThatTheDataHoldsThePixels() {
        #expect(throws: StbImageWriteError.self) {
            try pixels.withUnsafeBytes { data in
                _ = try encode { try writePngToFunc(func: $0, w: 4, h: 2, comp: 4, data: data, strideInBytes: 0) }
            }
        }
        #expect(throws: StbImageWriteError.self) {
            try pixels.withUnsafeBytes { data in
                _ = try encode { try writePngToFunc(func: $0, w: 3, h: 2, comp: 4, data: data, strideInBytes: 8) }
            }
        }
    }
}
