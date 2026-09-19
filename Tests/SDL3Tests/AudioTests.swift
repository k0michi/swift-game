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
        #expect(try getAudioStreamQueued(stream: stream) == samples.count * MemoryLayout<Float>.size)

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
    func noCopyCallbackReleasesLambdaAndDataWhenCleared() throws {
        let system = try `init`(flags: [.audio])
        let spec = AudioSpec(format: .f32, channels: 2, freq: 48_000)
        let stream = try createAudioStream(srcSpec: spec, dstSpec: spec)
        let samples: [Float] = [0, 0]
        var data: AudioStreamData? = samples.withUnsafeBytes {
            AudioStreamData(copying: $0)
        }
        weak let weakData = data
        let probe = AudioCallbackProbe()

        try putAudioStreamDataNoCopy(stream: stream, data: data!) { _ in
            probe.record()
        }
        data = nil
        #expect(weakData != nil)

        try clearAudioStream(stream: stream)
        #expect(probe.callCount == 1)
        #expect(weakData == nil)
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
}
