#if os(Emscripten)
// Plays through the browser's AudioContext. The browser keeps it suspended
// until the page gets a user gesture, and resume() succeeds only during one.
@MainActor
public final class AudioContext: BaseAudioContext {
    public var onerror: (() -> Void)?

    public init(options: AudioContextOptions = AudioContextOptions()) throws {
        var fields: [(String, JSONValue)] = []
        switch options.latencyHint {
        case let .category(category): fields.append(("latencyHint", .string(category.rawValue)))
        case let .seconds(seconds): fields.append(("latencyHint", .number(seconds)))
        }
        if let sampleRate = options.sampleRate {
            fields.append(("sampleRate", .number(Double(sampleRate))))
        }
        switch options.sinkId {
        case nil: break
        case let .id(id): fields.append(("sinkId", .string(id)))
        case let .options(sink): fields.append(("sinkId", .object([("type", .string(sink.type.rawValue))])))
        }
        if let renderSizeHint = options.renderSizeHint.jsonValue {
            fields.append(("renderSizeHint", renderSizeHint))
        }
        super.init(object: try JSObjectReference.new("AudioContext", options: fields))
        object.setListener("error", { context in
            MainActor.assumeIsolated {
                Unmanaged<AudioContext>.fromOpaque(context!).takeUnretainedValue().onerror?()
            }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    isolated deinit {
        object.setListener("error", nil, nil)
    }

    public func resume() async throws {
        try await object.callAsync("resume")
    }

    public func suspend() async throws {
        try await object.callAsync("suspend")
    }

    public func close() async throws {
        try await object.callAsync("close")
    }
}
#endif
