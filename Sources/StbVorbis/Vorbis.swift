import CStbVorbis

// stb_vorbis_info
public struct Info: Equatable, Sendable {
    public var sampleRate: UInt32
    public var channels: Int32
    public var setupMemoryRequired: UInt32
    public var setupTempMemoryRequired: UInt32
    public var tempMemoryRequired: UInt32
    public var maxFrameSize: Int32
}

// stb_vorbis, which stb_vorbis_close closes when it goes away.
public final class Vorbis {
    let pointer: OpaquePointer
    // stb_vorbis_open_memory reads from the memory it is given, so a copy
    // lives as long as the decoder.
    private let memory: UnsafeMutableBufferPointer<UInt8>?

    fileprivate init(pointer: OpaquePointer, memory: UnsafeMutableBufferPointer<UInt8>?) {
        self.pointer = pointer
        self.memory = memory
    }

    deinit {
        stb_vorbis_close(pointer)
        memory?.deallocate()
    }
}

// Copies the interleaved samples stb_vorbis returns and frees them.
private func takeDecoded(
    _ operation: String,
    _ decode: (_ channels: inout Int32, _ sampleRate: inout Int32, _ output: inout UnsafeMutablePointer<Int16>?) -> Int32
) throws -> (output: [Int16], channels: Int32, sampleRate: Int32) {
    var channels: Int32 = 0
    var sampleRate: Int32 = 0
    var output: UnsafeMutablePointer<Int16>?
    let samples = decode(&channels, &sampleRate, &output)
    guard samples >= 0, let output else {
        // The decoders say only that they failed.
        throw StbVorbisError(operation: operation, code: Int32(truncatingIfNeeded: VORBIS_invalid_stream.rawValue))
    }
    defer { free(output) }
    return (Array(UnsafeBufferPointer(start: output, count: Int(samples) * Int(channels))), channels, sampleRate)
}

// stb_vorbis_decode_memory
public func decodeMemory(mem: [UInt8]) throws -> (output: [Int16], channels: Int32, sampleRate: Int32) {
    try takeDecoded("stb_vorbis_decode_memory") { channels, sampleRate, output in
        stb_vorbis_decode_memory(mem, Int32(mem.count), &channels, &sampleRate, &output)
    }
}

// stb_vorbis_decode_filename
public func decodeFilename(filename: String) throws -> (output: [Int16], channels: Int32, sampleRate: Int32) {
    try takeDecoded("stb_vorbis_decode_filename") { channels, sampleRate, output in
        stb_vorbis_decode_filename(filename, &channels, &sampleRate, &output)
    }
}

// stb_vorbis_open_memory
public func openMemory(data: [UInt8]) throws -> Vorbis {
    let memory = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: max(data.count, 1))
    _ = memory.initialize(from: data)
    var error: Int32 = 0
    guard let pointer = stb_vorbis_open_memory(memory.baseAddress, Int32(data.count), &error, nil) else {
        memory.deallocate()
        throw StbVorbisError(operation: "stb_vorbis_open_memory", code: error)
    }
    return Vorbis(pointer: pointer, memory: memory)
}

// stb_vorbis_open_filename
public func openFilename(filename: String) throws -> Vorbis {
    var error: Int32 = 0
    guard let pointer = stb_vorbis_open_filename(filename, &error, nil) else {
        throw StbVorbisError(operation: "stb_vorbis_open_filename", code: error)
    }
    return Vorbis(pointer: pointer, memory: nil)
}

// stb_vorbis_get_info
public func getInfo(f: Vorbis) -> Info {
    let info = stb_vorbis_get_info(f.pointer)
    return Info(
        sampleRate: info.sample_rate,
        channels: info.channels,
        setupMemoryRequired: info.setup_memory_required,
        setupTempMemoryRequired: info.setup_temp_memory_required,
        tempMemoryRequired: info.temp_memory_required,
        maxFrameSize: info.max_frame_size
    )
}

// stb_vorbis_get_sample_offset
public func getSampleOffset(f: Vorbis) -> Int32 {
    stb_vorbis_get_sample_offset(f.pointer)
}

// stb_vorbis_stream_length_in_samples
public func streamLengthInSamples(f: Vorbis) -> UInt32 {
    stb_vorbis_stream_length_in_samples(f.pointer)
}

// stb_vorbis_stream_length_in_seconds
public func streamLengthInSeconds(f: Vorbis) -> Float {
    stb_vorbis_stream_length_in_seconds(f.pointer)
}

private func check(_ operation: String, _ f: Vorbis, _ succeeded: Bool) throws {
    guard succeeded else {
        throw StbVorbisError(operation: operation, code: stb_vorbis_get_error(f.pointer))
    }
}

// stb_vorbis_seek
public func seek(f: Vorbis, sampleNumber: UInt32) throws {
    try check("stb_vorbis_seek", f, stb_vorbis_seek(f.pointer, sampleNumber) != 0)
}

// stb_vorbis_seek_frame
public func seekFrame(f: Vorbis, sampleNumber: UInt32) throws {
    try check("stb_vorbis_seek_frame", f, stb_vorbis_seek_frame(f.pointer, sampleNumber) != 0)
}

// stb_vorbis_seek_start
public func seekStart(f: Vorbis) throws {
    try check("stb_vorbis_seek_start", f, stb_vorbis_seek_start(f.pointer) != 0)
}

// stb_vorbis_get_samples_float: up to `numSamples` samples of each of
// `channels` channels, fewer at the end of the stream.
public func getSamplesFloat(f: Vorbis, channels: Int32, numSamples: Int32) -> [[Float]] {
    let count = Int(numSamples)
    let storage = UnsafeMutablePointer<Float>.allocate(capacity: max(Int(channels) * count, 1))
    defer { storage.deallocate() }
    var buffers = (0..<Int(channels)).map { Optional(storage + $0 * count) }
    let read = stb_vorbis_get_samples_float(f.pointer, channels, &buffers, numSamples)
    return buffers.map { Array(UnsafeBufferPointer(start: $0, count: Int(read))) }
}

// stb_vorbis_get_samples_float_interleaved: up to `numFloats` samples of
// `channels` channels interleaved.
public func getSamplesFloatInterleaved(f: Vorbis, channels: Int32, numFloats: Int32) -> [Float] {
    var buffer = [Float](repeating: 0, count: Int(numFloats))
    let read = stb_vorbis_get_samples_float_interleaved(f.pointer, channels, &buffer, numFloats)
    return Array(buffer.prefix(Int(read) * Int(channels)))
}

// stb_vorbis_get_samples_short_interleaved
public func getSamplesShortInterleaved(f: Vorbis, channels: Int32, numShorts: Int32) -> [Int16] {
    var buffer = [Int16](repeating: 0, count: Int(numShorts))
    let read = stb_vorbis_get_samples_short_interleaved(f.pointer, channels, &buffer, numShorts)
    return Array(buffer.prefix(Int(read) * Int(channels)))
}
