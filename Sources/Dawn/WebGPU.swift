import CDawn

public enum WebGPUError: Error, Equatable {
    case createInstanceFailed
    case requestAdapterFailed(status: UInt32, message: String)
}

// WGPUBackendType
public enum BackendType: UInt32, Sendable {
    case undefined = 0x0000_0000
    case null = 0x0000_0001
    case webGPU = 0x0000_0002
    case d3D11 = 0x0000_0003
    case d3D12 = 0x0000_0004
    case metal = 0x0000_0005
    case vulkan = 0x0000_0006
    case openGL = 0x0000_0007
    case openGLES = 0x0000_0008
}

// WGPURequestAdapterOptions
public struct RequestAdapterOptions: Sendable {
    public var backendType: BackendType

    public init(backendType: BackendType = .undefined) {
        self.backendType = backendType
    }
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
        options: RequestAdapterOptions = RequestAdapterOptions()
    ) async throws -> Adapter {
        var cOptions = CDawn.WGPURequestAdapterOptions()
        cOptions.backendType = options.backendType.cValue
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
            _ = wgpuInstanceRequestAdapter(handle, &cOptions, callbackInfo)
        }

        guard result.status == WGPURequestAdapterStatus_Success, let handle = result.adapter else {
            throw WebGPUError.requestAdapterFailed(
                status: UInt32(truncatingIfNeeded: result.status.rawValue),
                message: result.message
            )
        }
        return Adapter(handle: handle, instance: self)
    }
}

private extension BackendType {
    var cValue: WGPUBackendType {
        switch self {
        case .undefined: WGPUBackendType_Undefined
        case .null: WGPUBackendType_Null
        case .webGPU: WGPUBackendType_WebGPU
        case .d3D11: WGPUBackendType_D3D11
        case .d3D12: WGPUBackendType_D3D12
        case .metal: WGPUBackendType_Metal
        case .vulkan: WGPUBackendType_Vulkan
        case .openGL: WGPUBackendType_OpenGL
        case .openGLES: WGPUBackendType_OpenGLES
        }
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
