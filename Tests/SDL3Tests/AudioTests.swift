import Foundation
import Testing

@testable import SDL3

private final class AudioCallbackProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func record() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private final class AudioStreamOwner: @unchecked Sendable {
    private let lock = NSLock()
    private var stream: AudioStream?

    func store(_ stream: AudioStream) {
        lock.lock()
        self.stream = stream
        lock.unlock()
    }

    func resume() throws {
        lock.lock()
        defer { lock.unlock() }
        try resumeAudioStreamDevice(stream: stream!)
    }

    func release() {
        lock.lock()
        stream = nil
        lock.unlock()
    }
}

private final class AudioDeviceOwner: @unchecked Sendable {
    private let lock = NSLock()
    private var device: AudioDeviceID?

    func store(_ device: AudioDeviceID) {
        lock.lock()
        self.device = device
        lock.unlock()
    }

    func release() {
        lock.lock()
        device = nil
        lock.unlock()
    }
}

@MainActor
extension SDL3Tests {
    @Test
    func audioFormatPropertiesMatchSDL() {
        #expect(audioBitsize(.f32) == 32)
        #expect(audioBytesize(.f32) == 4)
        #expect(audioIsFloat(.f32))
        #expect(audioIsSigned(.f32))
        #expect(audioIsInt(.s16))
        #expect(audioIsUnsigned(.u8))
        #expect(
            defineAudioFormat(signed: true, bigEndian: false, float: true, size: 32)
                == AudioFormat.f32LE.rawValue
        )
        #expect(audioFramesize(AudioSpec(format: .f32, channels: 2, freq: 48_000)) == 8)
    }

    @Test
    func convertsQueuedAudioThroughStream() throws {
        let system = try `init`(flags: [.audio])
        let spec = AudioSpec(format: .f32, channels: 2, freq: 48_000)
        let stream = try createAudioStream(srcSpec: spec, dstSpec: spec)
        let samples: [Float] = [0, 0, 0.5, -0.5]

        try samples.withUnsafeBytes {
            try putAudioStreamData(stream: stream, buf: $0)
        }
        #expect(
            try getAudioStreamQueued(stream: stream) == samples.count * MemoryLayout<Float>.size)

        var output = [Float](repeating: 0, count: samples.count)
        let readCount = try output.withUnsafeMutableBytes {
            try getAudioStreamData(stream: stream, buf: $0)
        }
        #expect(readCount == samples.count * MemoryLayout<Float>.size)
        #expect(output == samples)

        withExtendedLifetime((system, stream)) {}
    }

    @Test
    func opensDummyPlaybackStream() throws {
        let system = try `init`(flags: [.audio])
        let stream = try openAudioDeviceStream(
            devid: audioDeviceDefaultPlayback,
            spec: AudioSpec(format: .f32, channels: 2, freq: 48_000)
        )

        #expect(audioStreamDevicePaused(stream: stream))
        try resumeAudioStreamDevice(stream: stream)
        #expect(!audioStreamDevicePaused(stream: stream))

        withExtendedLifetime((system, stream)) {}
    }

    @Test
    func audioStreamKeepsSystemAlive() throws {
        weak var weakSystem: System?
        var stream: AudioStream?

        do {
            let system = try `init`(flags: [.audio])
            weakSystem = system
            stream = try createAudioStream(
                srcSpec: AudioSpec(format: .f32, channels: 2, freq: 48_000),
                dstSpec: AudioSpec(format: .f32, channels: 2, freq: 48_000)
            )
        }

        #expect(weakSystem != nil)
        #expect(stream != nil)
        stream = nil
        #expect(weakSystem == nil)
    }

    @Test
    func streamCallbackAcceptsAndReleasesLambda() throws {
        let system = try `init`(flags: [.audio])
        let spec = AudioSpec(format: .f32, channels: 2, freq: 48_000)
        let stream = try createAudioStream(srcSpec: spec, dstSpec: spec)
        var probe: AudioCallbackProbe? = AudioCallbackProbe()
        weak let weakProbe = probe

        try setAudioStreamPutCallback(stream: stream) { [probe] _, _, _ in
            probe?.record()
        }
        probe = nil
        let samples: [Float] = [0, 0]
        try samples.withUnsafeBytes {
            try putAudioStreamData(stream: stream, buf: $0)
        }

        #expect(weakProbe?.callCount == 1)
        try setAudioStreamPutCallback(stream: stream, callback: nil)
        #expect(weakProbe == nil)
        withExtendedLifetime((system, stream)) {}
    }

    @Test
    func noCopyCallbackReturnsUserManagedPointerWhenCleared() throws {
        let system = try `init`(flags: [.audio])
        let spec = AudioSpec(format: .f32, channels: 2, freq: 48_000)
        let stream = try createAudioStream(srcSpec: spec, dstSpec: spec)
        let samples: [Float] = [0, 0]
        let byteCount = samples.count * MemoryLayout<Float>.stride
        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<Float>.alignment
        )
        samples.withUnsafeBytes {
            pointer.copyMemory(from: $0.baseAddress!, byteCount: byteCount)
        }
        let probe = AudioCallbackProbe()

        try putAudioStreamDataNoCopy(
            stream: stream,
            buf: UnsafeRawBufferPointer(start: pointer, count: byteCount)
        ) { buf in
            UnsafeMutableRawPointer(mutating: buf.baseAddress!).deallocate()
            probe.record()
        }

        try clearAudioStream(stream: stream)
        #expect(probe.callCount == 1)
        withExtendedLifetime((system, stream)) {}
    }

    @Test
    func postmixCallbackReleasesLambdaWhenUnset() throws {
        let system = try `init`(flags: [.audio])
        let device = try openAudioDevice(
            devid: audioDeviceDefaultPlayback,
            spec: AudioSpec(format: .f32, channels: 2, freq: 48_000)
        )
        var probe: AudioCallbackProbe? = AudioCallbackProbe()
        weak let weakProbe = probe

        try setAudioPostmixCallback(devid: device) { [probe] _, _ in
            probe?.record()
        }
        probe = nil
        #expect(weakProbe != nil)

        try setAudioPostmixCallback(devid: device, callback: nil)
        #expect(weakProbe == nil)
        withExtendedLifetime((system, device)) {}
    }

    @Test
    func audioDeviceIDIsCanonicalAndOwnsOpenedDevice() throws {
        weak var weakSystem: System?
        var device: AudioDeviceID?
        var stream: AudioStream?

        do {
            let system = try `init`(flags: [.audio])
            weakSystem = system
            device = try openAudioDevice(
                devid: audioDeviceDefaultPlayback,
                spec: AudioSpec(format: .f32, channels: 2, freq: 48_000)
            )
            stream = try createAudioStream(
                srcSpec: AudioSpec(format: .f32, channels: 2, freq: 48_000),
                dstSpec: AudioSpec(format: .f32, channels: 2, freq: 48_000)
            )
            try bindAudioStream(devid: device!, stream: stream!)

            #expect(getAudioStreamDevice(stream: stream!) === device)
        }

        #expect(weakSystem != nil)
        stream = nil
        device = nil
        #expect(weakSystem == nil)
    }

    @Test
    func streamDestructionReleasesCallbackLambda() throws {
        let system = try `init`(flags: [.audio])
        let spec = AudioSpec(format: .f32, channels: 2, freq: 48_000)
        var stream: AudioStream? = try createAudioStream(srcSpec: spec, dstSpec: spec)
        var probe: AudioCallbackProbe? = AudioCallbackProbe()
        weak let weakProbe = probe

        try setAudioStreamGetCallback(stream: stream!) { [probe] _, _, _ in
            probe?.record()
        }
        probe = nil
        #expect(weakProbe != nil)

        stream = nil
        #expect(weakProbe == nil)
        withExtendedLifetime(system) {}
    }

    @Test
    func openDeviceStreamIsNotDestroyedOnAudioCallbackThread() throws {
        let system = try `init`(flags: [.audio])
        let owner = AudioStreamOwner()
        let callbackFinished = DispatchSemaphore(value: 0)
        var stream: AudioStream? = try openAudioDeviceStream(
            devid: audioDeviceDefaultPlayback,
            spec: AudioSpec(format: .f32, channels: 2, freq: 48_000)
        ) { [weak owner] _, _, _ in
            owner?.release()
            callbackFinished.signal()
        }
        owner.store(stream!)
        stream = nil

        try owner.resume()
        #expect(callbackFinished.wait(timeout: .now() + 2) == .success)
        waitForAudioCallbackCleanup()
        withExtendedLifetime((system, owner)) {}
    }

    @Test
    func streamCallbackCanReplaceItself() throws {
        let system = try `init`(flags: [.audio])
        let spec = AudioSpec(format: .f32, channels: 2, freq: 48_000)
        let stream = try createAudioStream(srcSpec: spec, dstSpec: spec)
        let callbackFinished = DispatchSemaphore(value: 0)

        try setAudioStreamPutCallback(stream: stream) { stream, _, _ in
            try! setAudioStreamPutCallback(stream: stream, callback: nil)
            callbackFinished.signal()
        }

        let samples: [Float] = [0, 0]
        try samples.withUnsafeBytes {
            try putAudioStreamData(stream: stream, buf: $0)
        }

        callbackFinished.wait()
        withExtendedLifetime((system, stream)) {}
    }

    @Test
    func putsPlanarAudioIntoStream() throws {
        let system = try `init`(flags: [.audio])
        let spec = AudioSpec(format: .f32, channels: 2, freq: 48_000)
        let stream = try createAudioStream(srcSpec: spec, dstSpec: spec)
        let left: [Float] = [0.25, 0.5]
        let right: [Float] = [-0.25, -0.5]

        try left.withUnsafeBytes { left in
            try right.withUnsafeBytes { right in
                try putAudioStreamPlanarData(
                    stream: stream,
                    channelBuffers: [left, right],
                    numSamples: 2
                )
            }
        }
        var output = [Float](repeating: 0, count: 4)
        _ = try output.withUnsafeMutableBytes {
            try getAudioStreamData(stream: stream, buf: $0)
        }

        #expect(output == [0.25, -0.25, 0.5, -0.5])
        withExtendedLifetime((system, stream)) {}
    }

    @Test
    func rejectsPlanarAudioBufferShorterThanRequestedSampleCount() throws {
        let system = try `init`(flags: [.audio])
        let spec = AudioSpec(format: .f32, channels: 2, freq: 48_000)
        let stream = try createAudioStream(srcSpec: spec, dstSpec: spec)
        let left: [Float] = [0.25]
        let right: [Float] = [-0.25]

        #expect(throws: SDLError.self) {
            try left.withUnsafeBytes { left in
                try right.withUnsafeBytes { right in
                    try putAudioStreamPlanarData(
                        stream: stream,
                        channelBuffers: [left, right],
                        numSamples: 2
                    )
                }
            }
        }
        withExtendedLifetime((system, stream)) {}
    }

    @Test
    func rejectsAudioBufferLengthsExceedingInt32() throws {
        let system = try `init`(flags: [.audio])
        let spec = AudioSpec(format: .u8, channels: 1, freq: 8_000)
        let stream = try createAudioStream(srcSpec: spec, dstSpec: spec)
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        defer { pointer.deallocate() }
        let oversizedCount = Int(Int32.max) + 1
        let source = UnsafeRawBufferPointer(start: pointer, count: oversizedCount)
        let destination = UnsafeMutableRawBufferPointer(
            start: pointer,
            count: oversizedCount
        )

        #expect(throws: SDLError.self) {
            try putAudioStreamData(stream: stream, buf: source)
        }
        #expect(throws: SDLError.self) {
            try putAudioStreamDataNoCopy(stream: stream, buf: source)
        }
        #expect(throws: SDLError.self) {
            try getAudioStreamData(stream: stream, buf: destination)
        }
        withExtendedLifetime((system, stream)) {}
    }

    @Test
    func mixesAndConvertsAudioSamples() throws {
        var destination: [Float] = [0, 0]
        let source: [Float] = [0.25, -0.5]
        try destination.withUnsafeMutableBytes { destination in
            try source.withUnsafeBytes { source in
                try mixAudio(
                    dst: destination,
                    src: source,
                    format: .f32,
                    volume: 1
                )
            }
        }
        #expect(destination == source)

        let converted = try source.withUnsafeBytes {
            try convertAudioSamples(
                srcSpec: AudioSpec(format: .f32, channels: 1, freq: 8_000),
                srcData: $0,
                dstSpec: AudioSpec(format: .s16, channels: 1, freq: 8_000)
            )
        }
        #expect(converted.count == 2 * MemoryLayout<Int16>.stride)
    }

    @Test
    func loadsWAVFromPathAndIOStream() throws {
        let wav: [UInt8] = [
            0x52, 0x49, 0x46, 0x46, 0x26, 0x00, 0x00, 0x00,
            0x57, 0x41, 0x56, 0x45, 0x66, 0x6D, 0x74, 0x20,
            0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
            0x40, 0x1F, 0x00, 0x00, 0x40, 0x1F, 0x00, 0x00,
            0x01, 0x00, 0x08, 0x00, 0x64, 0x61, 0x74, 0x61,
            0x02, 0x00, 0x00, 0x00, 0x80, 0xFF,
        ]
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-game-audio-\(UUID().uuidString).wav")
        try Data(wav).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }

        let fromPath = try loadWAV(path: path.path)
        #expect(fromPath.spec == AudioSpec(format: .u8, channels: 1, freq: 8_000))
        #expect(fromPath.audio == [0x80, 0xFF])

        let io = try ioFromFile(file: path.path, mode: "rb")
        let fromIO = try loadWAVIO(src: io, closeIO: true)
        #expect(fromIO.spec == fromPath.spec)
        #expect(fromIO.audio == fromPath.audio)
    }
}
