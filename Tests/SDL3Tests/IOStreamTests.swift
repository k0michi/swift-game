import Foundation
import Testing
@testable import SDL3

@MainActor
extension SDL3Tests {
    @Test
    func readsWritesAndSeeksMemoryIO() throws {
        var bytes = [UInt8](repeating: 0, count: 8)

        try bytes.withUnsafeMutableBytes { memory in
            let stream = try ioFromMem(mem: memory)
            let input: [UInt8] = [1, 2, 3, 4]
            let written = try input.withUnsafeBytes { try writeIO(context: stream, ptr: $0) }

            #expect(written == input.count)
            #expect(try tellIO(context: stream) == 4)
            #expect(try getIOSize(context: stream) == 8)
            #expect(try seekIO(context: stream, offset: 0, whence: .set) == 0)

            var output = [UInt8](repeating: 0, count: input.count)
            let read = try output.withUnsafeMutableBytes { try readIO(context: stream, ptr: $0) }
            #expect(read == input.count)
            #expect(output == input)
            #expect(try getIOStatus(context: stream) == .ready)

            try closeIO(context: stream)
            #expect(throws: SDLError.self) { try getIOSize(context: stream) }
        }
    }

    @Test
    func readsAndWritesEndianValues() throws {
        let stream = try ioFromDynamicMem()

        try writeU16LE(dst: stream, value: 0x1234)
        try writeU32BE(dst: stream, value: 0x89ABCDEF)
        try writeS64LE(dst: stream, value: -123_456_789)
        try seekIO(context: stream, offset: 0, whence: .set)

        #expect(try readU16LE(src: stream) == 0x1234)
        #expect(try readU32BE(src: stream) == 0x89ABCDEF)
        #expect(try readS64LE(src: stream) == -123_456_789)
    }

    @Test
    func savesAndLoadsFiles() throws {
        try withTemporaryFile { url in
            let expected = Array("SDL IOStream".utf8)

            try expected.withUnsafeBytes { try saveFile(file: url.path, data: $0) }
            #expect(try loadFile(file: url.path) == expected)

            let stream = try ioFromFile(file: url.path, mode: "rb")
            #expect(try loadFileIO(src: stream, closeIO: true) == expected)
            #expect(throws: SDLError.self) { try tellIO(context: stream) }
        }
    }
}
