import CSDL3
import Foundation

// SDL_IOStatus
public enum IOStatus: UInt32, Sendable {
    case ready, error, eof, notReady, readOnly, writeOnly
}

// SDL_IOWhence
public enum IOWhence: UInt32, Sendable {
    case set, current, end
}

// SDL_IOStreamInterface
public struct IOStreamInterface: Sendable {
    public var size: (@Sendable () -> Int64)?
    public var seek: (@Sendable (_ offset: Int64, _ whence: IOWhence) -> Int64)?
    public var read: (@Sendable (_ ptr: UnsafeMutableRawBufferPointer, _ status: inout IOStatus) -> Int)?
    public var write: (@Sendable (_ ptr: UnsafeRawBufferPointer, _ status: inout IOStatus) -> Int)?
    public var flush: (@Sendable (_ status: inout IOStatus) -> Bool)?
    public var close: (@Sendable () -> Bool)?

    public init(
        size: (@Sendable () -> Int64)? = nil,
        seek: (@Sendable (_ offset: Int64, _ whence: IOWhence) -> Int64)? = nil,
        read: (@Sendable (_ ptr: UnsafeMutableRawBufferPointer, _ status: inout IOStatus) -> Int)? = nil,
        write: (@Sendable (_ ptr: UnsafeRawBufferPointer, _ status: inout IOStatus) -> Int)? = nil,
        flush: (@Sendable (_ status: inout IOStatus) -> Bool)? = nil,
        close: (@Sendable () -> Bool)? = nil
    ) {
        self.size = size
        self.seek = seek
        self.read = read
        self.write = write
        self.flush = flush
        self.close = close
    }
}

private final class IOStreamInterfaceBox: @unchecked Sendable {
    let interface: IOStreamInterface

    init(interface: IOStreamInterface) {
        self.interface = interface
    }
}

// SDL_IOStream
public final class IOStream: @unchecked Sendable {
    private let lock = NSLock()
    private var pointer: OpaquePointer?

    fileprivate init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    func withPointer<Result>(
        _ body: (OpaquePointer) throws -> Result
    ) throws -> Result {
        lock.lock()
        defer { lock.unlock() }
        guard let pointer else {
            throw SDLError(operation: "SDL_IOStream", message: "IO stream is closed")
        }
        return try body(pointer)
    }

    func takePointer() throws -> OpaquePointer {
        lock.lock()
        defer { lock.unlock() }
        guard let pointer else {
            throw SDLError(operation: "SDL_IOStream", message: "IO stream is closed")
        }
        self.pointer = nil
        return pointer
    }

    deinit {
        if let pointer {
            // SDL_CloseIO
            _ = SDL_CloseIO(pointer)
        }
    }
}

// SDL_IOFromFile
public func ioFromFile(file: String, mode: String) throws -> IOStream {
    guard let pointer = SDL_IOFromFile(file, mode) else {
        throw SDLError(operation: "SDL_IOFromFile")
    }
    return IOStream(pointer: pointer)
}

// SDL_PROP_IOSTREAM_WINDOWS_HANDLE_POINTER
public let propIOStreamWindowsHandlePointer = "SDL.iostream.windows.handle"
// SDL_PROP_IOSTREAM_STDIO_FILE_POINTER
public let propIOStreamStdioFilePointer = "SDL.iostream.stdio.file"
// SDL_PROP_IOSTREAM_FILE_DESCRIPTOR_NUMBER
public let propIOStreamFileDescriptorNumber = "SDL.iostream.file_descriptor"
// SDL_PROP_IOSTREAM_ANDROID_AASSET_POINTER
public let propIOStreamAndroidAAssetPointer = "SDL.iostream.android.aasset"

// SDL_IOFromMem
public func ioFromMem(mem: UnsafeMutableRawBufferPointer) throws -> IOStream {
    guard let pointer = SDL_IOFromMem(mem.baseAddress, mem.count) else { throw SDLError(operation: "SDL_IOFromMem") }
    return IOStream(pointer: pointer)
}

// SDL_PROP_IOSTREAM_MEMORY_POINTER
public let propIOStreamMemoryPointer = "SDL.iostream.memory.base"
// SDL_PROP_IOSTREAM_MEMORY_SIZE_NUMBER
public let propIOStreamMemorySizeNumber = "SDL.iostream.memory.size"
// SDL_PROP_IOSTREAM_MEMORY_FREE_FUNC_POINTER
public let propIOStreamMemoryFreeFunctionPointer = "SDL.iostream.memory.free"

// SDL_IOFromConstMem
public func ioFromConstMem(mem: UnsafeRawBufferPointer) throws -> IOStream {
    guard let pointer = SDL_IOFromConstMem(mem.baseAddress, mem.count) else { throw SDLError(operation: "SDL_IOFromConstMem") }
    return IOStream(pointer: pointer)
}

// SDL_IOFromDynamicMem
public func ioFromDynamicMem() throws -> IOStream {
    guard let pointer = SDL_IOFromDynamicMem() else { throw SDLError(operation: "SDL_IOFromDynamicMem") }
    return IOStream(pointer: pointer)
}

// SDL_PROP_IOSTREAM_DYNAMIC_MEMORY_POINTER
public let propIOStreamDynamicMemoryPointer = "SDL.iostream.dynamic.memory"
// SDL_PROP_IOSTREAM_DYNAMIC_CHUNKSIZE_NUMBER
public let propIOStreamDynamicChunkSizeNumber = "SDL.iostream.dynamic.chunksize"

// SDL_OpenIO
public func openIO(iface: IOStreamInterface) throws -> IOStream {
    let box = IOStreamInterfaceBox(interface: iface)
    let userdata = Unmanaged.passRetained(box).toOpaque()
    var cInterface = SDL_IOStreamInterface()
    cInterface.version = UInt32(MemoryLayout<SDL_IOStreamInterface>.size)
    cInterface.size = iface.size.map { _ in ioStreamSizeCallback }
    cInterface.seek = iface.seek.map { _ in ioStreamSeekCallback }
    cInterface.read = iface.read.map { _ in ioStreamReadCallback }
    cInterface.write = iface.write.map { _ in ioStreamWriteCallback }
    cInterface.flush = iface.flush.map { _ in ioStreamFlushCallback }
    cInterface.close = ioStreamCloseCallback

    guard let pointer = SDL_OpenIO(&cInterface, userdata) else {
        Unmanaged<IOStreamInterfaceBox>.fromOpaque(userdata).release()
        throw SDLError(operation: "SDL_OpenIO")
    }
    return IOStream(pointer: pointer)
}

private let ioStreamSizeCallback: @convention(c) (UnsafeMutableRawPointer?) -> Int64 = { userdata in
    guard let userdata else { return -1 }
    return Unmanaged<IOStreamInterfaceBox>.fromOpaque(userdata)
        .takeUnretainedValue().interface.size?() ?? -1
}

private let ioStreamSeekCallback: @convention(c) (UnsafeMutableRawPointer?, Int64, SDL_IOWhence) -> Int64 = {
    userdata, offset, whence in
    guard
        let userdata,
        let whence = IOWhence(rawValue: UInt32(truncatingIfNeeded: whence.rawValue)),
        let seek = Unmanaged<IOStreamInterfaceBox>.fromOpaque(userdata)
            .takeUnretainedValue().interface.seek
    else { return -1 }
    return seek(offset, whence)
}

private let ioStreamReadCallback: @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int,
    UnsafeMutablePointer<SDL_IOStatus>?
) -> Int = { userdata, ptr, count, status in
    guard
        let userdata,
        let read = Unmanaged<IOStreamInterfaceBox>.fromOpaque(userdata)
            .takeUnretainedValue().interface.read
    else { return 0 }
    var swiftStatus = status.flatMap {
        IOStatus(rawValue: UInt32(truncatingIfNeeded: $0.pointee.rawValue))
    } ?? .ready
    let result = read(UnsafeMutableRawBufferPointer(start: ptr, count: count), &swiftStatus)
    status?.pointee = SDL_IOStatus(.init(truncatingIfNeeded: swiftStatus.rawValue))
    return min(max(result, 0), count)
}

private let ioStreamWriteCallback: @convention(c) (
    UnsafeMutableRawPointer?, UnsafeRawPointer?, Int,
    UnsafeMutablePointer<SDL_IOStatus>?
) -> Int = { userdata, ptr, count, status in
    guard
        let userdata,
        let write = Unmanaged<IOStreamInterfaceBox>.fromOpaque(userdata)
            .takeUnretainedValue().interface.write
    else { return 0 }
    var swiftStatus = status.flatMap {
        IOStatus(rawValue: UInt32(truncatingIfNeeded: $0.pointee.rawValue))
    } ?? .ready
    let result = write(UnsafeRawBufferPointer(start: ptr, count: count), &swiftStatus)
    status?.pointee = SDL_IOStatus(.init(truncatingIfNeeded: swiftStatus.rawValue))
    return min(max(result, 0), count)
}

private let ioStreamFlushCallback: @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutablePointer<SDL_IOStatus>?
) -> Bool = { userdata, status in
    guard
        let userdata,
        let flush = Unmanaged<IOStreamInterfaceBox>.fromOpaque(userdata)
            .takeUnretainedValue().interface.flush
    else { return true }
    var swiftStatus = status.flatMap {
        IOStatus(rawValue: UInt32(truncatingIfNeeded: $0.pointee.rawValue))
    } ?? .ready
    let result = flush(&swiftStatus)
    status?.pointee = SDL_IOStatus(.init(truncatingIfNeeded: swiftStatus.rawValue))
    return result
}

private let ioStreamCloseCallback: @convention(c) (UnsafeMutableRawPointer?) -> Bool = { userdata in
    guard let userdata else { return true }
    let box = Unmanaged<IOStreamInterfaceBox>.fromOpaque(userdata).takeRetainedValue()
    return box.interface.close?() ?? true
}

// SDL_CloseIO
public func closeIO(context: IOStream) throws {
    guard SDL_CloseIO(try context.takePointer()) else { throw SDLError(operation: "SDL_CloseIO") }
}

// SDL_GetIOProperties
public func getIOProperties(context: IOStream) throws -> PropertiesID {
    let rawValue = try context.withPointer(SDL_GetIOProperties)
    guard rawValue != 0 else { throw SDLError(operation: "SDL_GetIOProperties") }
    return PropertiesID(rawValue: rawValue)
}

// SDL_GetIOStatus
public func getIOStatus(context: IOStream) throws -> IOStatus {
    let value = try context.withPointer(SDL_GetIOStatus)
    guard let status = IOStatus(rawValue: UInt32(truncatingIfNeeded: value.rawValue)) else {
        throw SDLError(operation: "SDL_GetIOStatus", message: "Unknown IO status: \(value.rawValue)")
    }
    return status
}

// SDL_GetIOSize
public func getIOSize(context: IOStream) throws -> Int64 {
    let value = try context.withPointer(SDL_GetIOSize)
    guard value >= 0 else { throw SDLError(operation: "SDL_GetIOSize") }
    return value
}

// SDL_SeekIO
@discardableResult
public func seekIO(context: IOStream, offset: Int64, whence: IOWhence) throws -> Int64 {
    let value = try context.withPointer {
        SDL_SeekIO($0, offset, SDL_IOWhence(.init(truncatingIfNeeded: whence.rawValue)))
    }
    guard value >= 0 else { throw SDLError(operation: "SDL_SeekIO") }
    return value
}

// SDL_TellIO
public func tellIO(context: IOStream) throws -> Int64 {
    let value = try context.withPointer(SDL_TellIO)
    guard value >= 0 else { throw SDLError(operation: "SDL_TellIO") }
    return value
}

// SDL_ReadIO
@discardableResult
public func readIO(context: IOStream, ptr: UnsafeMutableRawBufferPointer) throws -> Int {
    try context.withPointer { SDL_ReadIO($0, ptr.baseAddress, ptr.count) }
}

// SDL_WriteIO
@discardableResult
public func writeIO(context: IOStream, ptr: UnsafeRawBufferPointer) throws -> Int {
    try context.withPointer { SDL_WriteIO($0, ptr.baseAddress, ptr.count) }
}

// SDL_IOprintf
@discardableResult
public func ioPrintf(context: IOStream, format: String, _ arguments: CVarArg...) throws -> Int {
    try ioVPrintf(context: context, format: format, arguments: arguments)
}

// SDL_IOvprintf
@discardableResult
public func ioVPrintf(context: IOStream, format: String, arguments: [CVarArg]) throws -> Int {
    let count = try context.withPointer { pointer in
        withVaList(arguments) { SDL_IOvprintf(pointer, format, $0) }
    }
    guard count > 0 || format.isEmpty else { throw SDLError(operation: "SDL_IOvprintf") }
    return count
}

// SDL_FlushIO
public func flushIO(context: IOStream) throws {
    guard try context.withPointer(SDL_FlushIO) else { throw SDLError(operation: "SDL_FlushIO") }
}

// SDL_LoadFile_IO
public func loadFileIO(src: IOStream, closeIO: Bool) throws -> [UInt8] {
    var count = 0
    let data: UnsafeMutableRawPointer? = if closeIO {
        SDL_LoadFile_IO(try src.takePointer(), &count, true)
    } else {
        try src.withPointer { SDL_LoadFile_IO($0, &count, false) }
    }
    guard let data else { throw SDLError(operation: "SDL_LoadFile_IO") }
    defer { SDL_free(data) }
    return Array(UnsafeRawBufferPointer(start: data, count: count))
}

// SDL_LoadFile
public func loadFile(file: String) throws -> [UInt8] {
    var count = 0
    guard let data = SDL_LoadFile(file, &count) else { throw SDLError(operation: "SDL_LoadFile") }
    defer { SDL_free(data) }
    return Array(UnsafeRawBufferPointer(start: data, count: count))
}

// SDL_SaveFile_IO
public func saveFileIO(src: IOStream, data: UnsafeRawBufferPointer, closeIO: Bool) throws {
    let saved = if closeIO {
        SDL_SaveFile_IO(try src.takePointer(), data.baseAddress, data.count, true)
    } else {
        try src.withPointer { SDL_SaveFile_IO($0, data.baseAddress, data.count, false) }
    }
    guard saved else { throw SDLError(operation: "SDL_SaveFile_IO") }
}

// SDL_SaveFile
public func saveFile(file: String, data: UnsafeRawBufferPointer) throws {
    guard SDL_SaveFile(file, data.baseAddress, data.count) else { throw SDLError(operation: "SDL_SaveFile") }
}

private func readInteger<T>(context: IOStream, operation: String, _ body: (OpaquePointer, UnsafeMutablePointer<T>) -> Bool) throws -> T {
    try context.withPointer { pointer in
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard body(pointer, value) else { throw SDLError(operation: operation) }
        return value.pointee
    }
}

private func writeInteger<T>(context: IOStream, value: T, operation: String, _ body: (OpaquePointer, T) -> Bool) throws {
    guard try context.withPointer({ body($0, value) }) else { throw SDLError(operation: operation) }
}

// SDL_ReadU8
public func readU8(src: IOStream) throws -> UInt8 { try readInteger(context: src, operation: "SDL_ReadU8", SDL_ReadU8) }
// SDL_ReadS8
public func readS8(src: IOStream) throws -> Int8 { try readInteger(context: src, operation: "SDL_ReadS8", SDL_ReadS8) }
// SDL_ReadU16LE
public func readU16LE(src: IOStream) throws -> UInt16 { try readInteger(context: src, operation: "SDL_ReadU16LE", SDL_ReadU16LE) }
// SDL_ReadS16LE
public func readS16LE(src: IOStream) throws -> Int16 { try readInteger(context: src, operation: "SDL_ReadS16LE", SDL_ReadS16LE) }
// SDL_ReadU16BE
public func readU16BE(src: IOStream) throws -> UInt16 { try readInteger(context: src, operation: "SDL_ReadU16BE", SDL_ReadU16BE) }
// SDL_ReadS16BE
public func readS16BE(src: IOStream) throws -> Int16 { try readInteger(context: src, operation: "SDL_ReadS16BE", SDL_ReadS16BE) }
// SDL_ReadU32LE
public func readU32LE(src: IOStream) throws -> UInt32 { try readInteger(context: src, operation: "SDL_ReadU32LE", SDL_ReadU32LE) }
// SDL_ReadS32LE
public func readS32LE(src: IOStream) throws -> Int32 { try readInteger(context: src, operation: "SDL_ReadS32LE", SDL_ReadS32LE) }
// SDL_ReadU32BE
public func readU32BE(src: IOStream) throws -> UInt32 { try readInteger(context: src, operation: "SDL_ReadU32BE", SDL_ReadU32BE) }
// SDL_ReadS32BE
public func readS32BE(src: IOStream) throws -> Int32 { try readInteger(context: src, operation: "SDL_ReadS32BE", SDL_ReadS32BE) }
// SDL_ReadU64LE
public func readU64LE(src: IOStream) throws -> UInt64 { try readInteger(context: src, operation: "SDL_ReadU64LE", SDL_ReadU64LE) }
// SDL_ReadS64LE
public func readS64LE(src: IOStream) throws -> Int64 { try readInteger(context: src, operation: "SDL_ReadS64LE", SDL_ReadS64LE) }
// SDL_ReadU64BE
public func readU64BE(src: IOStream) throws -> UInt64 { try readInteger(context: src, operation: "SDL_ReadU64BE", SDL_ReadU64BE) }
// SDL_ReadS64BE
public func readS64BE(src: IOStream) throws -> Int64 { try readInteger(context: src, operation: "SDL_ReadS64BE", SDL_ReadS64BE) }

// SDL_WriteU8
public func writeU8(dst: IOStream, value: UInt8) throws { try writeInteger(context: dst, value: value, operation: "SDL_WriteU8", SDL_WriteU8) }
// SDL_WriteS8
public func writeS8(dst: IOStream, value: Int8) throws { try writeInteger(context: dst, value: value, operation: "SDL_WriteS8", SDL_WriteS8) }
// SDL_WriteU16LE
public func writeU16LE(dst: IOStream, value: UInt16) throws { try writeInteger(context: dst, value: value, operation: "SDL_WriteU16LE", SDL_WriteU16LE) }
// SDL_WriteS16LE
public func writeS16LE(dst: IOStream, value: Int16) throws { try writeInteger(context: dst, value: value, operation: "SDL_WriteS16LE", SDL_WriteS16LE) }
// SDL_WriteU16BE
public func writeU16BE(dst: IOStream, value: UInt16) throws { try writeInteger(context: dst, value: value, operation: "SDL_WriteU16BE", SDL_WriteU16BE) }
// SDL_WriteS16BE
public func writeS16BE(dst: IOStream, value: Int16) throws { try writeInteger(context: dst, value: value, operation: "SDL_WriteS16BE", SDL_WriteS16BE) }
// SDL_WriteU32LE
public func writeU32LE(dst: IOStream, value: UInt32) throws { try writeInteger(context: dst, value: value, operation: "SDL_WriteU32LE", SDL_WriteU32LE) }
// SDL_WriteS32LE
public func writeS32LE(dst: IOStream, value: Int32) throws { try writeInteger(context: dst, value: value, operation: "SDL_WriteS32LE", SDL_WriteS32LE) }
// SDL_WriteU32BE
public func writeU32BE(dst: IOStream, value: UInt32) throws { try writeInteger(context: dst, value: value, operation: "SDL_WriteU32BE", SDL_WriteU32BE) }
// SDL_WriteS32BE
public func writeS32BE(dst: IOStream, value: Int32) throws { try writeInteger(context: dst, value: value, operation: "SDL_WriteS32BE", SDL_WriteS32BE) }
// SDL_WriteU64LE
public func writeU64LE(dst: IOStream, value: UInt64) throws { try writeInteger(context: dst, value: value, operation: "SDL_WriteU64LE", SDL_WriteU64LE) }
// SDL_WriteS64LE
public func writeS64LE(dst: IOStream, value: Int64) throws { try writeInteger(context: dst, value: value, operation: "SDL_WriteS64LE", SDL_WriteS64LE) }
// SDL_WriteU64BE
public func writeU64BE(dst: IOStream, value: UInt64) throws { try writeInteger(context: dst, value: value, operation: "SDL_WriteU64BE", SDL_WriteU64BE) }
// SDL_WriteS64BE
public func writeS64BE(dst: IOStream, value: Int64) throws { try writeInteger(context: dst, value: value, operation: "SDL_WriteS64BE", SDL_WriteS64BE) }
