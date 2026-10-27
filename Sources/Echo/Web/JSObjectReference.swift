#if os(Emscripten)
import CEchoWeb

// A browser object that an Echo object forwards to. The handle is released
// with the reference. The browser has one thread, so the main actor owns
// every reference.
@MainActor
final class JSObjectReference {
    let handle: Int32

    init(handle: Int32) {
        precondition(handle != 0)
        self.handle = handle
    }

    deinit {
        echo_web_release(handle)
    }

    // new <constructor>(context, options), or new <constructor>(options)
    // without a context.
    static func new(
        _ constructor: String,
        context: JSObjectReference? = nil,
        options: [(String, JSONValue)] = []
    ) throws -> JSObjectReference {
        var error: Int32 = 0
        let handle = echo_web_new(constructor, context?.handle ?? 0, JSONValue.object(options).text, &error)
        try check(error)
        return JSObjectReference(handle: handle)
    }

    func number(_ property: String) -> Double {
        echo_web_get_number(handle, property)
    }

    func set(_ property: String, _ value: Double) throws {
        try check(echo_web_set_number(handle, property, value))
    }

    func string(_ property: String) -> String {
        let length = Int(echo_web_get_string(handle, property, nil, 0))
        return String(unsafeUninitializedCapacity: length + 1) { buffer in
            buffer.withMemoryRebound(to: CChar.self) {
                _ = echo_web_get_string(handle, property, $0.baseAddress, Int32($0.count))
            }
            return length
        }
    }

    func set(_ property: String, _ value: String) throws {
        try check(echo_web_set_string(handle, property, value))
    }

    func object(_ property: String) -> JSObjectReference? {
        let handle = echo_web_get_object(handle, property)
        return handle == 0 ? nil : JSObjectReference(handle: handle)
    }

    func call(_ method: String, _ target: JSObjectReference? = nil, _ arguments: [Double] = []) throws {
        try check(echo_web_call(handle, method, target?.handle ?? 0, arguments, Int32(arguments.count)))
    }

    func call(_ method: String, floats: [Float], _ arguments: [Double]) throws {
        try check(echo_web_call_with_floats(
            handle, method, floats, Int32(floats.count), arguments, Int32(arguments.count)
        ))
    }

    // Calls a method that returns a promise and waits for it to settle.
    @discardableResult
    func callAsync(_ method: String, _ arguments: [Double] = []) async throws -> JSObjectReference? {
        let (error, value): (Int32, Int32) = await withUnsafeContinuation { continuation in
            let settlement = Unmanaged.passRetained(Settlement(continuation)).toOpaque()
            echo_web_call_async(handle, method, arguments, Int32(arguments.count), { settlement, error, value in
                Unmanaged<Settlement>.fromOpaque(settlement!).takeRetainedValue()
                    .continuation.resume(returning: (error, value))
            }, settlement)
        }
        let result = value == 0 ? nil : JSObjectReference(handle: value)
        try check(error)
        return result
    }

    // Calls `listener` on each event of `type`, until it is set again. The
    // pointer is passed back to it unretained, so the owner clears the
    // listener before it goes away.
    func setListener(
        _ type: String,
        _ listener: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?,
        _ userData: UnsafeMutableRawPointer?
    ) {
        echo_web_set_listener(handle, type, listener, userData)
    }
}

private final class Settlement {
    let continuation: UnsafeContinuation<(Int32, Int32), Never>

    init(_ continuation: UnsafeContinuation<(Int32, Int32), Never>) {
        self.continuation = continuation
    }
}

private func check(_ error: Int32) throws {
    switch Int(error) {
    case ECHO_WEB_ERROR_NONE: return
    case ECHO_WEB_ERROR_INVALID_ACCESS: throw WebAudioError.invalidAccess
    case ECHO_WEB_ERROR_INVALID_STATE: throw WebAudioError.invalidState
    case ECHO_WEB_ERROR_INDEX_SIZE: throw WebAudioError.indexSize
    case ECHO_WEB_ERROR_NOT_SUPPORTED: throw WebAudioError.notSupported
    default: throw WebAudioError.rangeError
    }
}

// Options passed to constructors.
enum JSONValue {
    case number(Double)
    case string(String)
    case object([(String, JSONValue)])

    var text: String {
        switch self {
        case let .number(number):
            number.isFinite ? "\(number)" : "null"
        case let .string(string):
            "\"" + string.unicodeScalars.map { scalar in
                switch scalar {
                case "\"": "\\\""
                case "\\": "\\\\"
                case _ where scalar.value < 0x20: "\\u" + String(repeating: "0", count: 4 - String(scalar.value, radix: 16).count) + String(scalar.value, radix: 16)
                default: String(scalar)
                }
            }.joined() + "\""
        case let .object(fields):
            "{" + fields.map { JSONValue.string($0.0).text + ":" + $0.1.text }.joined(separator: ",") + "}"
        }
    }
}

extension AudioContextRenderSizeHint {
    // The renderSizeHint option, or nil for the default.
    var jsonValue: JSONValue? {
        switch self {
        case .category(.default): nil
        case let .category(category): .string(category.rawValue)
        case let .frameCount(count): .number(Double(count))
        }
    }
}
#endif
