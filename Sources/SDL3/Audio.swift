import CSDL3
import Dispatch
import Foundation

private let audioCleanupQueue = DispatchQueue(
    label: "SDL3.Audio.cleanup"
)

func waitForAudioCleanup() {
    audioCleanupQueue.sync {}
}

// SDL_AUDIO_MASK_BITSIZE
public let audioMaskBitsize: UInt32 = 0xFF

// SDL_AUDIO_MASK_FLOAT
public let audioMaskFloat: UInt32 = 1 << 8

// SDL_AUDIO_MASK_BIG_ENDIAN
public let audioMaskBigEndian: UInt32 = 1 << 12

// SDL_AUDIO_MASK_SIGNED
public let audioMaskSigned: UInt32 = 1 << 15

// SDL_DEFINE_AUDIO_FORMAT
public func defineAudioFormat(
    signed: Bool,
    bigEndian: Bool,
    float: Bool,
    size: UInt32
) -> UInt32 {
    (signed ? 1 << 15 : 0)
        | (bigEndian ? 1 << 12 : 0)
        | (float ? 1 << 8 : 0)
        | (size & audioMaskBitsize)
}

// SDL_AudioFormat
public struct AudioFormat: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let unknown = Self(rawValue: 0x0000)
    public static let u8 = Self(rawValue: 0x0008)
    public static let s8 = Self(rawValue: 0x8008)
    public static let s16LE = Self(rawValue: 0x8010)
    public static let s16BE = Self(rawValue: 0x9010)
    public static let s32LE = Self(rawValue: 0x8020)
    public static let s32BE = Self(rawValue: 0x9020)
    public static let f32LE = Self(rawValue: 0x8120)
    public static let f32BE = Self(rawValue: 0x9120)

    #if _endian(big)
        public static let s16 = s16BE
        public static let s32 = s32BE
        public static let f32 = f32BE
    #else
        public static let s16 = s16LE
        public static let s32 = s32LE
        public static let f32 = f32LE
    #endif
}

// SDL_AUDIO_BITSIZE
public func audioBitsize(_ format: AudioFormat) -> UInt32 {
    format.rawValue & audioMaskBitsize
}

// SDL_AUDIO_BYTESIZE
public func audioBytesize(_ format: AudioFormat) -> UInt32 {
    audioBitsize(format) / 8
}

// SDL_AUDIO_ISFLOAT
public func audioIsFloat(_ format: AudioFormat) -> Bool {
    format.rawValue & audioMaskFloat != 0
}

// SDL_AUDIO_ISBIGENDIAN
public func audioIsBigEndian(_ format: AudioFormat) -> Bool {
    format.rawValue & audioMaskBigEndian != 0
}

// SDL_AUDIO_ISLITTLEENDIAN
public func audioIsLittleEndian(_ format: AudioFormat) -> Bool {
    !audioIsBigEndian(format)
}

// SDL_AUDIO_ISSIGNED
public func audioIsSigned(_ format: AudioFormat) -> Bool {
    format.rawValue & audioMaskSigned != 0
}

// SDL_AUDIO_ISINT
public func audioIsInt(_ format: AudioFormat) -> Bool {
    !audioIsFloat(format)
}

// SDL_AUDIO_ISUNSIGNED
public func audioIsUnsigned(_ format: AudioFormat) -> Bool {
    !audioIsSigned(format)
}

// SDL_AudioDeviceID
public final class AudioDeviceID: Hashable, @unchecked Sendable {
    public let rawValue: UInt32
    fileprivate let callbackLock = NSLock()
    fileprivate var postmixCallbackBox: AudioPostmixCallbackBox?
    fileprivate var openedSystem: System?

    fileprivate init(rawValue: UInt32, openedSystem: System?) {
        self.rawValue = rawValue
        self.openedSystem = openedSystem
    }

    public static func == (lhs: AudioDeviceID, rhs: AudioDeviceID) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }

    deinit {
        audioDeviceIDRegistry.remove(self)
        guard let openedSystem else { return }

        let cleanup = AudioDeviceCallbackCleanup(
            rawValue: rawValue,
            system: openedSystem,
            callbackBox: postmixCallbackBox
        )
        audioCleanupQueue.async {
            cleanup.run()
        }
    }
}

private final class WeakAudioDeviceID {
    weak var value: AudioDeviceID?

    init(_ value: AudioDeviceID) {
        self.value = value
    }
}

private final class AudioDeviceIDRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UInt32: WeakAudioDeviceID] = [:]

    func get(rawValue: UInt32, openedSystem: System? = nil) -> AudioDeviceID {
        lock.lock()
        defer { lock.unlock() }

        if let value = values[rawValue]?.value {
            if let openedSystem {
                value.openedSystem = openedSystem
            }
            return value
        }

        let value = AudioDeviceID(rawValue: rawValue, openedSystem: openedSystem)
        values[rawValue] = WeakAudioDeviceID(value)
        return value
    }

    func remove(_ value: AudioDeviceID) {
        lock.lock()
        if values[value.rawValue]?.value == nil
            || values[value.rawValue]?.value === value
        {
            values[value.rawValue] = nil
        }
        lock.unlock()
    }
}

private let audioDeviceIDRegistry = AudioDeviceIDRegistry()

// SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK
public let audioDeviceDefaultPlayback = audioDeviceIDRegistry.get(rawValue: UInt32.max)

// SDL_AUDIO_DEVICE_DEFAULT_RECORDING
public let audioDeviceDefaultRecording = audioDeviceIDRegistry.get(rawValue: UInt32.max - 1)

// SDL_AudioSpec
public struct AudioSpec: Equatable, Hashable, Sendable {
    public var format: AudioFormat
    public var channels: Int32
    public var freq: Int32

    public init(format: AudioFormat, channels: Int32, freq: Int32) {
        self.format = format
        self.channels = channels
        self.freq = freq
    }
}

// SDL_AUDIO_FRAMESIZE
public func audioFramesize(_ spec: AudioSpec) -> UInt32 {
    audioBytesize(spec.format) * UInt32(spec.channels)
}

// SDL_AudioStream
public final class AudioStream: @unchecked Sendable {
    fileprivate let storage: AudioStreamStorage
    fileprivate let callbackLock = NSLock()
    fileprivate var getCallbackBox: AudioStreamCallbackBox?
    fileprivate var putCallbackBox: AudioStreamCallbackBox?

    fileprivate var pointer: OpaquePointer {
        storage.pointer
    }

    fileprivate init(storage: AudioStreamStorage) {
        self.storage = storage
    }

    fileprivate convenience init(pointer: OpaquePointer, system: System) {
        self.init(storage: AudioStreamStorage(pointer: pointer, system: system))
    }

    deinit {
        if getCallbackBox != nil || putCallbackBox != nil {
            let cleanup = AudioStreamCallbackCleanup(
                storage: storage,
                getCallbackBox: getCallbackBox,
                putCallbackBox: putCallbackBox
            )
            audioCleanupQueue.async {
                cleanup.run()
            }
        }
    }
}

fileprivate final class AudioStreamStorage: @unchecked Sendable {
    let pointer: OpaquePointer
    private let system: System

    init(pointer: OpaquePointer, system: System) {
        self.pointer = pointer
        self.system = system
    }

    deinit {
        let destruction = AudioStreamDestruction(pointer: pointer, system: system)
        audioCleanupQueue.async {
            destruction.run()
        }
    }
}

private final class AudioStreamDestruction: @unchecked Sendable {
    private let pointer: OpaquePointer
    private let system: System

    init(pointer: OpaquePointer, system: System) {
        self.pointer = pointer
        self.system = system
    }

    func run() {
        // SDL_DestroyAudioStream
        SDL_DestroyAudioStream(pointer)
        withExtendedLifetime(system) {}
    }
}

private final class AudioStreamCallbackCleanup: @unchecked Sendable {
    private let storage: AudioStreamStorage
    private let getCallbackBox: AudioStreamCallbackBox?
    private let putCallbackBox: AudioStreamCallbackBox?

    init(
        storage: AudioStreamStorage,
        getCallbackBox: AudioStreamCallbackBox?,
        putCallbackBox: AudioStreamCallbackBox?
    ) {
        self.storage = storage
        self.getCallbackBox = getCallbackBox
        self.putCallbackBox = putCallbackBox
    }

    func run() {
        if getCallbackBox != nil {
            _ = SDL_SetAudioStreamGetCallback(storage.pointer, nil, nil)
        }
        if putCallbackBox != nil {
            _ = SDL_SetAudioStreamPutCallback(storage.pointer, nil, nil)
        }
        withExtendedLifetime((getCallbackBox, putCallbackBox, storage)) {}
    }
}

private final class AudioDeviceCallbackCleanup: @unchecked Sendable {
    private let rawValue: UInt32
    private let system: System
    private let callbackBox: AudioPostmixCallbackBox?

    init(
        rawValue: UInt32,
        system: System,
        callbackBox: AudioPostmixCallbackBox?
    ) {
        self.rawValue = rawValue
        self.system = system
        self.callbackBox = callbackBox
    }

    func run() {
        if callbackBox != nil {
            _ = SDL_SetAudioPostmixCallback(rawValue, nil, nil)
        }
        // SDL_CloseAudioDevice
        SDL_CloseAudioDevice(rawValue)
        withExtendedLifetime((callbackBox, system)) {}
    }
}

// SDL_AudioStreamCallback
public typealias AudioStreamCallback = @Sendable (
    _ stream: AudioStream,
    _ additionalAmount: Int32,
    _ totalAmount: Int32
) -> Void

fileprivate final class AudioStreamCallbackBox: @unchecked Sendable {
    weak var stream: AudioStream?
    let callback: AudioStreamCallback

    init(stream: AudioStream, callback: @escaping AudioStreamCallback) {
        self.stream = stream
        self.callback = callback
    }

    func invoke(additionalAmount: Int32, totalAmount: Int32) {
        guard let stream else { return }
        callback(stream, additionalAmount, totalAmount)
    }
}

// SDL_AudioPostmixCallback
public typealias AudioPostmixCallback = @Sendable (
    _ spec: AudioSpec,
    _ buffer: UnsafeMutableBufferPointer<Float>
) -> Void

fileprivate final class AudioPostmixCallbackBox: @unchecked Sendable {
    let callback: AudioPostmixCallback

    init(callback: @escaping AudioPostmixCallback) {
        self.callback = callback
    }
}

// SDL_AudioStreamDataCompleteCallback
public typealias AudioStreamDataCompleteCallback = @Sendable (
    _ buf: UnsafeRawBufferPointer
) -> Void

private final class AudioStreamDataCompleteCallbackBox: @unchecked Sendable {
    let callback: AudioStreamDataCompleteCallback

    init(callback: @escaping AudioStreamDataCompleteCallback) {
        self.callback = callback
    }
}

// SDL_GetNumAudioDrivers
public func getNumAudioDrivers() -> Int32 {
    SDL_GetNumAudioDrivers()
}

// SDL_GetAudioDriver
public func getAudioDriver(index: Int32) -> String? {
    SDL_GetAudioDriver(index).map(String.init(cString:))
}

// SDL_GetCurrentAudioDriver
public func getCurrentAudioDriver() -> String? {
    SDL_GetCurrentAudioDriver().map(String.init(cString:))
}

// SDL_GetAudioPlaybackDevices
public func getAudioPlaybackDevices() throws -> [AudioDeviceID] {
    try getAudioDevices(operation: "SDL_GetAudioPlaybackDevices", SDL_GetAudioPlaybackDevices)
}

// SDL_GetAudioRecordingDevices
public func getAudioRecordingDevices() throws -> [AudioDeviceID] {
    try getAudioDevices(operation: "SDL_GetAudioRecordingDevices", SDL_GetAudioRecordingDevices)
}

// SDL_GetAudioDeviceName
public func getAudioDeviceName(devid: AudioDeviceID) throws -> String {
    guard let name = SDL_GetAudioDeviceName(devid.rawValue) else {
        throw SDLError(operation: "SDL_GetAudioDeviceName")
    }
    return String(cString: name)
}

// SDL_GetAudioDeviceFormat
public func getAudioDeviceFormat(
    devid: AudioDeviceID
) throws -> (spec: AudioSpec, sampleFrames: Int32) {
    var spec = SDL_AudioSpec()
    var sampleFrames: Int32 = 0
    guard SDL_GetAudioDeviceFormat(devid.rawValue, &spec, &sampleFrames) else {
        throw SDLError(operation: "SDL_GetAudioDeviceFormat")
    }
    return (AudioSpec(spec), sampleFrames)
}

// SDL_GetAudioDeviceChannelMap
public func getAudioDeviceChannelMap(devid: AudioDeviceID) throws -> [Int32] {
    var count: Int32 = 0
    guard let pointer = SDL_GetAudioDeviceChannelMap(devid.rawValue, &count) else {
        throw SDLError(operation: "SDL_GetAudioDeviceChannelMap")
    }
    defer { SDL_free(pointer) }
    return Array(UnsafeBufferPointer(start: pointer, count: Int(count)))
}

// SDL_OpenAudioDevice
@MainActor
public func openAudioDevice(
    devid: AudioDeviceID,
    spec: AudioSpec? = nil
) throws -> AudioDeviceID {
    let system = try activeSystem(operation: "SDL_OpenAudioDevice")
    let rawValue = withCAudioSpec(spec) {
        SDL_OpenAudioDevice(devid.rawValue, $0)
    }
    guard rawValue != 0 else {
        throw SDLError(operation: "SDL_OpenAudioDevice")
    }
    return audioDeviceIDRegistry.get(rawValue: rawValue, openedSystem: system)
}

// SDL_IsAudioDevicePhysical
public func isAudioDevicePhysical(devid: AudioDeviceID) -> Bool {
    SDL_IsAudioDevicePhysical(devid.rawValue)
}

// SDL_IsAudioDevicePlayback
public func isAudioDevicePlayback(devid: AudioDeviceID) -> Bool {
    SDL_IsAudioDevicePlayback(devid.rawValue)
}

// SDL_PauseAudioDevice
public func pauseAudioDevice(devid: AudioDeviceID) throws {
    guard SDL_PauseAudioDevice(devid.rawValue) else {
        throw SDLError(operation: "SDL_PauseAudioDevice")
    }
}

// SDL_ResumeAudioDevice
public func resumeAudioDevice(devid: AudioDeviceID) throws {
    guard SDL_ResumeAudioDevice(devid.rawValue) else {
        throw SDLError(operation: "SDL_ResumeAudioDevice")
    }
}

// SDL_AudioDevicePaused
public func audioDevicePaused(devid: AudioDeviceID) -> Bool {
    SDL_AudioDevicePaused(devid.rawValue)
}

// SDL_GetAudioDeviceGain
public func getAudioDeviceGain(devid: AudioDeviceID) throws -> Float {
    let gain = SDL_GetAudioDeviceGain(devid.rawValue)
    guard gain >= 0 else {
        throw SDLError(operation: "SDL_GetAudioDeviceGain")
    }
    return gain
}

// SDL_SetAudioDeviceGain
public func setAudioDeviceGain(devid: AudioDeviceID, gain: Float) throws {
    guard SDL_SetAudioDeviceGain(devid.rawValue, gain) else {
        throw SDLError(operation: "SDL_SetAudioDeviceGain")
    }
}

// SDL_BindAudioStreams
public func bindAudioStreams(devid: AudioDeviceID, streams: [AudioStream]) throws {
    let pointers: [OpaquePointer?] = streams.map(\.pointer)
    guard pointers.withUnsafeBufferPointer({
        SDL_BindAudioStreams(devid.rawValue, $0.baseAddress, Int32($0.count))
    }) else {
        throw SDLError(operation: "SDL_BindAudioStreams")
    }
}

// SDL_BindAudioStream
public func bindAudioStream(devid: AudioDeviceID, stream: AudioStream) throws {
    guard SDL_BindAudioStream(devid.rawValue, stream.pointer) else {
        throw SDLError(operation: "SDL_BindAudioStream")
    }
}

// SDL_UnbindAudioStreams
public func unbindAudioStreams(streams: [AudioStream]) {
    let pointers: [OpaquePointer?] = streams.map(\.pointer)
    pointers.withUnsafeBufferPointer {
        SDL_UnbindAudioStreams($0.baseAddress, Int32($0.count))
    }
}

// SDL_UnbindAudioStream
public func unbindAudioStream(stream: AudioStream) {
    SDL_UnbindAudioStream(stream.pointer)
}

// SDL_GetAudioStreamDevice
public func getAudioStreamDevice(stream: AudioStream) -> AudioDeviceID? {
    let rawValue = SDL_GetAudioStreamDevice(stream.pointer)
    return rawValue == 0 ? nil : audioDeviceIDRegistry.get(rawValue: rawValue)
}

// SDL_CreateAudioStream
@MainActor
public func createAudioStream(
    srcSpec: AudioSpec?,
    dstSpec: AudioSpec?
) throws -> AudioStream {
    let system = try activeSystem(operation: "SDL_CreateAudioStream")
    let pointer = withCAudioSpec(srcSpec) { srcSpec in
        withCAudioSpec(dstSpec) { dstSpec in
            SDL_CreateAudioStream(srcSpec, dstSpec)
        }
    }
    guard let pointer else {
        throw SDLError(operation: "SDL_CreateAudioStream")
    }
    return AudioStream(pointer: pointer, system: system)
}

// SDL_GetAudioStreamProperties
public func getAudioStreamProperties(stream: AudioStream) throws -> PropertiesID {
    let rawValue = SDL_GetAudioStreamProperties(stream.pointer)
    guard rawValue != 0 else {
        throw SDLError(operation: "SDL_GetAudioStreamProperties")
    }
    return PropertiesID(rawValue: rawValue)
}

// SDL_GetAudioStreamFormat
public func getAudioStreamFormat(
    stream: AudioStream
) throws -> (srcSpec: AudioSpec, dstSpec: AudioSpec) {
    var srcSpec = SDL_AudioSpec()
    var dstSpec = SDL_AudioSpec()
    guard SDL_GetAudioStreamFormat(stream.pointer, &srcSpec, &dstSpec) else {
        throw SDLError(operation: "SDL_GetAudioStreamFormat")
    }
    return (AudioSpec(srcSpec), AudioSpec(dstSpec))
}

// SDL_SetAudioStreamFormat
public func setAudioStreamFormat(
    stream: AudioStream,
    srcSpec: AudioSpec?,
    dstSpec: AudioSpec?
) throws {
    let succeeded = withCAudioSpec(srcSpec) { srcSpec in
        withCAudioSpec(dstSpec) { dstSpec in
            SDL_SetAudioStreamFormat(stream.pointer, srcSpec, dstSpec)
        }
    }
    guard succeeded else {
        throw SDLError(operation: "SDL_SetAudioStreamFormat")
    }
}

// SDL_GetAudioStreamFrequencyRatio
public func getAudioStreamFrequencyRatio(stream: AudioStream) throws -> Float {
    let ratio = SDL_GetAudioStreamFrequencyRatio(stream.pointer)
    guard ratio != 0 else {
        throw SDLError(operation: "SDL_GetAudioStreamFrequencyRatio")
    }
    return ratio
}

// SDL_SetAudioStreamFrequencyRatio
public func setAudioStreamFrequencyRatio(stream: AudioStream, ratio: Float) throws {
    guard SDL_SetAudioStreamFrequencyRatio(stream.pointer, ratio) else {
        throw SDLError(operation: "SDL_SetAudioStreamFrequencyRatio")
    }
}

// SDL_GetAudioStreamGain
public func getAudioStreamGain(stream: AudioStream) throws -> Float {
    let gain = SDL_GetAudioStreamGain(stream.pointer)
    guard gain >= 0 else {
        throw SDLError(operation: "SDL_GetAudioStreamGain")
    }
    return gain
}

// SDL_SetAudioStreamGain
public func setAudioStreamGain(stream: AudioStream, gain: Float) throws {
    guard SDL_SetAudioStreamGain(stream.pointer, gain) else {
        throw SDLError(operation: "SDL_SetAudioStreamGain")
    }
}

// SDL_GetAudioStreamInputChannelMap
public func getAudioStreamInputChannelMap(stream: AudioStream) throws -> [Int32] {
    try getAudioStreamChannelMap(
        operation: "SDL_GetAudioStreamInputChannelMap",
        stream: stream,
        SDL_GetAudioStreamInputChannelMap
    )
}

// SDL_GetAudioStreamOutputChannelMap
public func getAudioStreamOutputChannelMap(stream: AudioStream) throws -> [Int32] {
    try getAudioStreamChannelMap(
        operation: "SDL_GetAudioStreamOutputChannelMap",
        stream: stream,
        SDL_GetAudioStreamOutputChannelMap
    )
}

// SDL_SetAudioStreamInputChannelMap
public func setAudioStreamInputChannelMap(
    stream: AudioStream,
    chmap: [Int32]
) throws {
    guard chmap.withUnsafeBufferPointer({
        SDL_SetAudioStreamInputChannelMap(stream.pointer, $0.baseAddress, Int32($0.count))
    }) else {
        throw SDLError(operation: "SDL_SetAudioStreamInputChannelMap")
    }
}

// SDL_SetAudioStreamOutputChannelMap
public func setAudioStreamOutputChannelMap(
    stream: AudioStream,
    chmap: [Int32]
) throws {
    guard chmap.withUnsafeBufferPointer({
        SDL_SetAudioStreamOutputChannelMap(stream.pointer, $0.baseAddress, Int32($0.count))
    }) else {
        throw SDLError(operation: "SDL_SetAudioStreamOutputChannelMap")
    }
}

// SDL_PutAudioStreamData
public func putAudioStreamData(
    stream: AudioStream,
    buf: UnsafeRawBufferPointer
) throws {
    let length = try audioBufferLength(buf.count, operation: "SDL_PutAudioStreamData")
    guard SDL_PutAudioStreamData(stream.pointer, buf.baseAddress, length) else {
        throw SDLError(operation: "SDL_PutAudioStreamData")
    }
}

// SDL_PutAudioStreamDataNoCopy
public func putAudioStreamDataNoCopy(
    stream: AudioStream,
    buf: UnsafeRawBufferPointer,
    callback: AudioStreamDataCompleteCallback? = nil
) throws {
    let length = try audioBufferLength(
        buf.count,
        operation: "SDL_PutAudioStreamDataNoCopy"
    )
    guard let callback else {
        guard SDL_PutAudioStreamDataNoCopy(
            stream.pointer,
            buf.baseAddress,
            length,
            nil,
            nil
        ) else {
            throw SDLError(operation: "SDL_PutAudioStreamDataNoCopy")
        }
        return
    }

    let box = AudioStreamDataCompleteCallbackBox(callback: callback)
    let userdata = Unmanaged.passRetained(box).toOpaque()
    let succeeded = SDL_PutAudioStreamDataNoCopy(
        stream.pointer,
        buf.baseAddress,
        length,
        { userdata, buf, buflen in
            guard let userdata, let buf else { return }
            let box = Unmanaged<AudioStreamDataCompleteCallbackBox>
                .fromOpaque(userdata)
                .takeRetainedValue()
            box.callback(UnsafeRawBufferPointer(start: buf, count: Int(buflen)))
        },
        userdata
    )
    guard succeeded else {
        Unmanaged<AudioStreamDataCompleteCallbackBox>.fromOpaque(userdata).release()
        throw SDLError(operation: "SDL_PutAudioStreamDataNoCopy")
    }
}

// SDL_PutAudioStreamPlanarData
public func putAudioStreamPlanarData(
    stream: AudioStream,
    channelBuffers: [UnsafeRawBufferPointer?],
    numSamples: Int32
) throws {
    guard SDL_LockAudioStream(stream.pointer) else {
        throw SDLError(operation: "SDL_LockAudioStream")
    }
    defer { _ = SDL_UnlockAudioStream(stream.pointer) }

    let (srcSpec, _) = try getAudioStreamFormat(stream: stream)
    let sampleByteCount = Int(audioBytesize(srcSpec.format))
    let (requiredByteCount, overflow) = Int(numSamples).multipliedReportingOverflow(
        by: sampleByteCount
    )
    guard numSamples >= 0, !overflow else {
        throw SDLError(
            operation: "SDL_PutAudioStreamPlanarData",
            message: "sample count exceeds the supported buffer length"
        )
    }
    guard
        srcSpec.channels >= 0,
        let channelCount = Int32(exactly: channelBuffers.count)
    else {
        throw SDLError(
            operation: "SDL_PutAudioStreamPlanarData",
            message: "channel count exceeds the supported range"
        )
    }
    let providedChannelCount = min(channelBuffers.count, Int(srcSpec.channels))
    guard channelBuffers.prefix(providedChannelCount).allSatisfy({
        $0.map { $0.count >= requiredByteCount } ?? true
    }) else {
        throw SDLError(
            operation: "SDL_PutAudioStreamPlanarData",
            message: "a channel buffer is shorter than the requested sample count"
        )
    }
    let pointers = channelBuffers.map { $0?.baseAddress }
    guard pointers.withUnsafeBufferPointer({
        SDL_PutAudioStreamPlanarData(
            stream.pointer,
            $0.baseAddress,
            channelCount,
            numSamples
        )
    }) else {
        throw SDLError(operation: "SDL_PutAudioStreamPlanarData")
    }
}

// SDL_GetAudioStreamData
@discardableResult
public func getAudioStreamData(
    stream: AudioStream,
    buf: UnsafeMutableRawBufferPointer
) throws -> Int32 {
    let length = try audioBufferLength(buf.count, operation: "SDL_GetAudioStreamData")
    let count = SDL_GetAudioStreamData(stream.pointer, buf.baseAddress, length)
    guard count >= 0 else {
        throw SDLError(operation: "SDL_GetAudioStreamData")
    }
    return count
}

// SDL_GetAudioStreamAvailable
public func getAudioStreamAvailable(stream: AudioStream) throws -> Int32 {
    let count = SDL_GetAudioStreamAvailable(stream.pointer)
    guard count >= 0 else {
        throw SDLError(operation: "SDL_GetAudioStreamAvailable")
    }
    return count
}

// SDL_GetAudioStreamQueued
public func getAudioStreamQueued(stream: AudioStream) throws -> Int32 {
    let count = SDL_GetAudioStreamQueued(stream.pointer)
    guard count >= 0 else {
        throw SDLError(operation: "SDL_GetAudioStreamQueued")
    }
    return count
}

// SDL_FlushAudioStream
public func flushAudioStream(stream: AudioStream) throws {
    guard SDL_FlushAudioStream(stream.pointer) else {
        throw SDLError(operation: "SDL_FlushAudioStream")
    }
}

// SDL_ClearAudioStream
public func clearAudioStream(stream: AudioStream) throws {
    guard SDL_ClearAudioStream(stream.pointer) else {
        throw SDLError(operation: "SDL_ClearAudioStream")
    }
}

// SDL_PauseAudioStreamDevice
public func pauseAudioStreamDevice(stream: AudioStream) throws {
    guard SDL_PauseAudioStreamDevice(stream.pointer) else {
        throw SDLError(operation: "SDL_PauseAudioStreamDevice")
    }
}

// SDL_ResumeAudioStreamDevice
public func resumeAudioStreamDevice(stream: AudioStream) throws {
    guard SDL_ResumeAudioStreamDevice(stream.pointer) else {
        throw SDLError(operation: "SDL_ResumeAudioStreamDevice")
    }
}

// SDL_AudioStreamDevicePaused
public func audioStreamDevicePaused(stream: AudioStream) -> Bool {
    SDL_AudioStreamDevicePaused(stream.pointer)
}

// SDL_LockAudioStream
public func lockAudioStream(stream: AudioStream) throws {
    guard SDL_LockAudioStream(stream.pointer) else {
        throw SDLError(operation: "SDL_LockAudioStream")
    }
}

// SDL_UnlockAudioStream
public func unlockAudioStream(stream: AudioStream) throws {
    guard SDL_UnlockAudioStream(stream.pointer) else {
        throw SDLError(operation: "SDL_UnlockAudioStream")
    }
}

// SDL_SetAudioStreamGetCallback
public func setAudioStreamGetCallback(
    stream: AudioStream,
    callback: AudioStreamCallback?
) throws {
    try setAudioStreamCallback(
        stream: stream,
        callback: callback,
        operation: "SDL_SetAudioStreamGetCallback",
        setter: SDL_SetAudioStreamGetCallback,
        keyPath: \.getCallbackBox
    )
}

// SDL_SetAudioStreamPutCallback
public func setAudioStreamPutCallback(
    stream: AudioStream,
    callback: AudioStreamCallback?
) throws {
    try setAudioStreamCallback(
        stream: stream,
        callback: callback,
        operation: "SDL_SetAudioStreamPutCallback",
        setter: SDL_SetAudioStreamPutCallback,
        keyPath: \.putCallbackBox
    )
}

// SDL_OpenAudioDeviceStream
@MainActor
public func openAudioDeviceStream(
    devid: AudioDeviceID,
    spec: AudioSpec? = nil,
    callback: AudioStreamCallback? = nil
) throws -> AudioStream {
    let system = try activeSystem(operation: "SDL_OpenAudioDeviceStream")
    let pointer = withCAudioSpec(spec) {
        SDL_OpenAudioDeviceStream(devid.rawValue, $0, nil, nil)
    }
    guard let pointer else {
        throw SDLError(operation: "SDL_OpenAudioDeviceStream")
    }
    let stream = AudioStream(pointer: pointer, system: system)
    if let callback, let device = getAudioStreamDevice(stream: stream) {
        if isAudioDevicePlayback(devid: device) {
            try setAudioStreamGetCallback(stream: stream, callback: callback)
        } else {
            try setAudioStreamPutCallback(stream: stream, callback: callback)
        }
    }
    return stream
}

// SDL_SetAudioPostmixCallback
public func setAudioPostmixCallback(
    devid: AudioDeviceID,
    callback: AudioPostmixCallback?
) throws {
    devid.callbackLock.lock()
    defer { devid.callbackLock.unlock() }

    let box = callback.map(AudioPostmixCallbackBox.init(callback:))
    let userdata = box.map { Unmanaged.passUnretained($0).toOpaque() }
    let succeeded = SDL_SetAudioPostmixCallback(
        devid.rawValue,
        box == nil ? nil : { userdata, spec, buffer, buflen in
            guard
                let userdata,
                let spec,
                let buffer
            else { return }
            let box = Unmanaged<AudioPostmixCallbackBox>
                .fromOpaque(userdata)
                .takeUnretainedValue()
            box.callback(
                AudioSpec(spec.pointee),
                UnsafeMutableBufferPointer(
                    start: buffer,
                    count: Int(buflen) / MemoryLayout<Float>.stride
                )
            )
        },
        userdata
    )
    guard succeeded else {
        throw SDLError(operation: "SDL_SetAudioPostmixCallback")
    }
    devid.postmixCallbackBox = box
}

// SDL_LoadWAV_IO
public func loadWAVIO(
    src: IOStream,
    closeIO: Bool
) throws -> (spec: AudioSpec, audio: [UInt8]) {
    if closeIO {
        let pointer = try src.takePointer()
        return try loadWAV { spec, audioBuffer, audioLength in
            SDL_LoadWAV_IO(pointer, true, spec, audioBuffer, audioLength)
        }
    }
    return try src.withPointer { pointer in
        try loadWAV { spec, audioBuffer, audioLength in
            SDL_LoadWAV_IO(pointer, false, spec, audioBuffer, audioLength)
        }
    }
}

// SDL_LoadWAV
public func loadWAV(path: String) throws -> (spec: AudioSpec, audio: [UInt8]) {
    try loadWAV { spec, audioBuffer, audioLength in
        SDL_LoadWAV(path, spec, audioBuffer, audioLength)
    }
}

// SDL_MixAudio
public func mixAudio(
    dst: UnsafeMutableRawBufferPointer,
    src: UnsafeRawBufferPointer,
    format: AudioFormat,
    volume: Float
) throws {
    guard dst.count == src.count, let length = UInt32(exactly: src.count) else {
        throw SDLError(
            operation: "SDL_MixAudio",
            message: "source and destination buffers must have the same UInt32-sized length"
        )
    }
    guard SDL_MixAudio(
        dst.baseAddress?.assumingMemoryBound(to: UInt8.self),
        src.baseAddress?.assumingMemoryBound(to: UInt8.self),
        SDL_AudioFormat(.init(truncatingIfNeeded: format.rawValue)),
        length,
        volume
    ) else {
        throw SDLError(operation: "SDL_MixAudio")
    }
}

// SDL_ConvertAudioSamples
public func convertAudioSamples(
    srcSpec: AudioSpec,
    srcData: UnsafeRawBufferPointer,
    dstSpec: AudioSpec
) throws -> [UInt8] {
    guard let srcLength = Int32(exactly: srcData.count) else {
        throw SDLError(
            operation: "SDL_ConvertAudioSamples",
            message: "source buffer length exceeds Int32.max"
        )
    }
    var cSrcSpec = srcSpec.cValue
    var cDstSpec = dstSpec.cValue
    var dstData: UnsafeMutablePointer<UInt8>?
    var dstLength: Int32 = 0
    guard SDL_ConvertAudioSamples(
        &cSrcSpec,
        srcData.baseAddress?.assumingMemoryBound(to: UInt8.self),
        srcLength,
        &cDstSpec,
        &dstData,
        &dstLength
    ), let dstData else {
        throw SDLError(operation: "SDL_ConvertAudioSamples")
    }
    defer { SDL_free(dstData) }
    return Array(UnsafeBufferPointer(start: dstData, count: Int(dstLength)))
}

// SDL_GetAudioFormatName
public func getAudioFormatName(format: AudioFormat) -> String {
    String(
        cString: SDL_GetAudioFormatName(
            SDL_AudioFormat(.init(truncatingIfNeeded: format.rawValue))
        )
    )
}

// SDL_GetSilenceValueForFormat
public func getSilenceValueForFormat(format: AudioFormat) -> Int32 {
    SDL_GetSilenceValueForFormat(
        SDL_AudioFormat(.init(truncatingIfNeeded: format.rawValue))
    )
}

@MainActor
private func activeSystem(operation: String) throws -> System {
    guard let system = System.active(for: .audio) else {
        throw SDLError(operation: operation, message: "SDL is not initialized")
    }
    return system
}

private func getAudioDevices(
    operation: String,
    _ body: (UnsafeMutablePointer<Int32>?) -> UnsafeMutablePointer<UInt32>?
) throws -> [AudioDeviceID] {
    var count: Int32 = 0
    guard let pointer = body(&count) else {
        throw SDLError(operation: operation)
    }
    defer { SDL_free(pointer) }
    return UnsafeBufferPointer(start: pointer, count: Int(count)).map {
        audioDeviceIDRegistry.get(rawValue: $0)
    }
}

private func loadWAV(
    _ body: (
        UnsafeMutablePointer<SDL_AudioSpec>,
        UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
        UnsafeMutablePointer<UInt32>
    ) -> Bool
) throws -> (spec: AudioSpec, audio: [UInt8]) {
    var spec = SDL_AudioSpec()
    var audioBuffer: UnsafeMutablePointer<UInt8>?
    var audioLength: UInt32 = 0
    guard body(&spec, &audioBuffer, &audioLength), let audioBuffer else {
        throw SDLError(operation: "SDL_LoadWAV")
    }
    defer { SDL_free(audioBuffer) }
    return (
        AudioSpec(spec),
        Array(UnsafeBufferPointer(start: audioBuffer, count: Int(audioLength)))
    )
}

private func audioBufferLength(_ count: Int, operation: String) throws -> Int32 {
    guard let length = Int32(exactly: count) else {
        throw SDLError(
            operation: operation,
            message: "buffer length exceeds Int32.max"
        )
    }
    return length
}

private func getAudioStreamChannelMap(
    operation: String,
    stream: AudioStream,
    _ body: (OpaquePointer?, UnsafeMutablePointer<Int32>?) -> UnsafeMutablePointer<Int32>?
) throws -> [Int32] {
    var count: Int32 = 0
    guard let pointer = body(stream.pointer, &count) else {
        throw SDLError(operation: operation)
    }
    defer { SDL_free(pointer) }
    return Array(UnsafeBufferPointer(start: pointer, count: Int(count)))
}

private func setAudioStreamCallback(
    stream: AudioStream,
    callback: AudioStreamCallback?,
    operation: String,
    setter: (
        OpaquePointer?,
        SDL_AudioStreamCallback?,
        UnsafeMutableRawPointer?
    ) -> Bool,
    keyPath: ReferenceWritableKeyPath<AudioStream, AudioStreamCallbackBox?>
) throws {
    stream.callbackLock.lock()
    defer { stream.callbackLock.unlock() }

    let box = callback.map {
        AudioStreamCallbackBox(stream: stream, callback: $0)
    }
    let userdata = box.map { Unmanaged.passUnretained($0).toOpaque() }
    let succeeded = setter(
        stream.pointer,
        box == nil ? nil : { userdata, _, additionalAmount, totalAmount in
            guard let userdata else { return }
            Unmanaged<AudioStreamCallbackBox>
                .fromOpaque(userdata)
                .takeUnretainedValue()
                .invoke(
                    additionalAmount: additionalAmount,
                    totalAmount: totalAmount
                )
        },
        userdata
    )
    guard succeeded else {
        throw SDLError(operation: operation)
    }
    stream[keyPath: keyPath] = box
}

private func withCAudioSpec<Result>(
    _ spec: AudioSpec?,
    body: (UnsafePointer<SDL_AudioSpec>?) -> Result
) -> Result {
    guard let spec else {
        return body(nil)
    }
    var cSpec = spec.cValue
    return withUnsafePointer(to: &cSpec, body)
}

private extension AudioSpec {
    init(_ value: SDL_AudioSpec) {
        self.init(
            format: AudioFormat(
                rawValue: UInt32(truncatingIfNeeded: value.format.rawValue)
            ),
            channels: value.channels,
            freq: value.freq
        )
    }

    var cValue: SDL_AudioSpec {
        SDL_AudioSpec(
            format: SDL_AudioFormat(.init(truncatingIfNeeded: format.rawValue)),
            channels: channels,
            freq: freq
        )
    }
}
