#if os(Emscripten)
import CEchoWeb

// Renders with the browser's OfflineAudioContext, which renders a fixed
// length in one go.
public final class OfflineAudioContext: BaseAudioContext {
    public let length: UInt32?
    public var oncomplete: ((OfflineAudioCompletionEvent) -> Void)?

    public init(options: OfflineAudioContextOptions) throws {
        guard let length = options.length else { throw WebAudioError.notSupported }
        var fields: [(String, JSONValue)] = [
            ("numberOfChannels", .number(Double(options.numberOfChannels))),
            ("length", .number(Double(length))),
            ("sampleRate", .number(Double(options.sampleRate))),
        ]
        if let renderSizeHint = options.renderSizeHint.jsonValue {
            fields.append(("renderSizeHint", renderSizeHint))
        }
        self.length = length
        super.init(object: try JSObjectReference.new("OfflineAudioContext", options: fields))
    }

    public convenience init(
        numberOfChannels: UInt32,
        length: UInt32,
        sampleRate: Float
    ) throws {
        try self.init(options: OfflineAudioContextOptions(
            numberOfChannels: numberOfChannels,
            length: length,
            sampleRate: sampleRate
        ))
    }

    // The browser renders the whole length, so `chunkSize` must be nil.
    public func startRendering(chunkSize: UInt32? = nil) async throws -> AudioBuffer {
        guard chunkSize == nil else { throw WebAudioError.notSupported }
        guard let rendered = try await object.callAsync("startRendering") else {
            throw WebAudioError.invalidState
        }
        let buffer = try AudioBuffer(options: AudioBufferOptions(
            numberOfChannels: UInt32(rendered.number("numberOfChannels")),
            length: UInt32(rendered.number("length")),
            sampleRate: Float(rendered.number("sampleRate"))
        ))
        for channel in 0 ..< buffer.numberOfChannels {
            let data = try buffer.getChannelData(channel)
            echo_web_copy_from_channel(rendered.handle, Int32(channel), data.baseAddress, Int32(data.count))
        }
        oncomplete?(OfflineAudioCompletionEvent(renderedBuffer: buffer))
        return buffer
    }

    public func suspend(at suspendTime: Double) async throws {
        try await object.callAsync("suspend", [suspendTime])
    }

    public func resume() async throws {
        try await object.callAsync("resume")
    }
}
#endif
