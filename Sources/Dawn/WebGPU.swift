import CDawn

public enum WebGPUError: Error, Equatable {
    case createInstanceFailed
    case requestAdapterFailed(status: UInt32, message: String)
}

public final class Instance {
    let handle: WGPUInstance

    init(handle: WGPUInstance) {
        self.handle = handle
    }

    deinit {
        // wgpuInstanceRelease
        wgpuInstanceRelease(handle)
    }

    // wgpuInstanceProcessEvents
    public func processEvents() {
        wgpuInstanceProcessEvents(handle)
    }

    // wgpuInstanceRequestAdapter
    public func requestAdapter(
        options: WGPURequestAdapterOptions = WGPURequestAdapterOptions()
    ) async throws -> Adapter {
        var options = options
        let result: AdapterRequestResult = await withCheckedContinuation { continuation in
            let context = AdapterRequestContext(continuation)
            let retainedContext = Unmanaged.passRetained(context).toOpaque()
            var callbackInfo = WGPURequestAdapterCallbackInfo()
            callbackInfo.mode = WGPUCallbackMode_AllowSpontaneous
            callbackInfo.userdata1 = retainedContext
            callbackInfo.callback = { status, adapter, message, userdata1, _ in
                guard let userdata1 else { return }
                let context = Unmanaged<AdapterRequestContext>
                    .fromOpaque(userdata1)
                    .takeRetainedValue()
                let text = message.data.map {
                    let bytes = UnsafeRawPointer($0).assumingMemoryBound(to: UInt8.self)
                    return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(message.length)), as: UTF8.self)
                } ?? ""
                context.continuation.resume(
                    returning: AdapterRequestResult(status: status, adapter: adapter, message: text)
                )
            }
            _ = wgpuInstanceRequestAdapter(handle, &options, callbackInfo)
        }

        guard result.status == WGPURequestAdapterStatus_Success, let handle = result.adapter else {
            throw WebGPUError.requestAdapterFailed(
                status: result.status.rawValue,
                message: result.message
            )
        }
        return Adapter(handle: handle, instance: self)
    }
}

public final class Adapter {
    let handle: WGPUAdapter
    private let instance: Instance

    init(handle: WGPUAdapter, instance: Instance) {
        self.handle = handle
        self.instance = instance
    }

    deinit {
        // wgpuAdapterRelease
        wgpuAdapterRelease(handle)
    }
}

// wgpuCreateInstance
public func createInstance(
    descriptor: WGPUInstanceDescriptor = WGPUInstanceDescriptor()
) throws -> Instance {
    var descriptor = descriptor
    guard let handle = wgpuCreateInstance(&descriptor) else {
        throw WebGPUError.createInstanceFailed
    }
    return Instance(handle: handle)
}

private struct AdapterRequestResult: @unchecked Sendable {
    let status: WGPURequestAdapterStatus
    let adapter: WGPUAdapter?
    let message: String
}

private final class AdapterRequestContext: @unchecked Sendable {
    let continuation: CheckedContinuation<AdapterRequestResult, Never>

    init(_ continuation: CheckedContinuation<AdapterRequestResult, Never>) {
        self.continuation = continuation
    }
}
