import Foundation
import Testing
@testable import SDL3

private final class CustomIOState: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: [UInt8]
    private var position = 0
    private(set) var isClosed = false

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    func size() -> Int64 {
        lock.withLock { Int64(bytes.count) }
    }

    func seek(offset: Int64, whence: IOWhence) -> Int64 {
        lock.withLock {
            let base = switch whence {
            case .set: 0
            case .current: position
            case .end: bytes.count
            }
            position = min(max(base + Int(offset), 0), bytes.count)
            return Int64(position)
        }
    }

    func read(into destination: UnsafeMutableRawBufferPointer, status: inout IOStatus) -> Int {
        lock.withLock {
            let count = min(destination.count, bytes.count - position)
            if count > 0 {
                bytes.withUnsafeBytes { source in
                    destination.copyMemory(from: UnsafeRawBufferPointer(rebasing: source[position..<(position + count)]))
                }
                position += count
            }
            status = position == bytes.count ? .eof : .ready
            return count
        }
    }

    func close() -> Bool {
        lock.withLock { isClosed = true }
        return true
    }
}

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

    @Test
    func customIOStreamInvokesSwiftInterfaceAndCloses() throws {
        let expected = Array("custom stream".utf8)
        let state = CustomIOState(bytes: expected)
        var interface = IOStreamInterface()
        interface.size = { state.size() }
        interface.seek = { state.seek(offset: $0, whence: $1) }
        interface.read = { state.read(into: $0, status: &$1) }
        interface.close = { state.close() }
        let stream = try openIO(iface: interface)

        #expect(try getIOSize(context: stream) == Int64(expected.count))
        var actual = [UInt8](repeating: 0, count: expected.count)
        #expect(try actual.withUnsafeMutableBytes { try readIO(context: stream, ptr: $0) } == expected.count)
        #expect(actual == expected)
        #expect(try getIOStatus(context: stream) == .eof)

        try closeIO(context: stream)
        #expect(state.isClosed)
    }

    @Test
    func printsFormattedTextToIOStream() throws {
        let stream = try ioFromDynamicMem()

        let count = try "value".withCString {
            try ioPrintf(context: stream, format: "%s=%d", $0, 42)
        }
        #expect(count == 8)
        try seekIO(context: stream, offset: 0, whence: .set)
        var bytes = [UInt8](repeating: 0, count: 8)
        #expect(try bytes.withUnsafeMutableBytes { try readIO(context: stream, ptr: $0) } == 8)
        #expect(String(decoding: bytes, as: UTF8.self) == "value=42")
    }
}
