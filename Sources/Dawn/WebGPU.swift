import CDawn
import Interop

public enum WebGPUError: Error, Equatable {
    case createInstanceFailed
    case requestAdapterFailed(status: UInt32, message: String)
    case requestDeviceFailed(status: UInt32, message: String)
    case createSurfaceFailed
    case unsupportedChainedStruct(SType)
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

// WGPUSType
public enum SType: UInt32, Sendable {
    case surfaceSourceMetalLayer = 0x0000_0004
    case surfaceSourceWindowsHWND = 0x0000_0005
    case surfaceSourceXlibWindow = 0x0000_0006
    case surfaceSourceWaylandSurface = 0x0000_0007
}

// WGPUChainedStruct
public struct ChainedStruct {
    public var next: (any ChainedStructNode)?
    public let sType: SType

    public init(next: (any ChainedStructNode)? = nil, sType: SType) {
        self.next = next
        self.sType = sType
    }
}

public protocol ChainedStructNode {
    var chain: ChainedStruct { get set }
}

// WGPUSurfaceDescriptor
public struct SurfaceDescriptor {
    public var nextInChain: (any ChainedStructNode)?
    public var label: String?

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        label: String? = nil
    ) {
        self.nextInChain = nextInChain
        self.label = label
    }
}

// WGPUSurfaceSourceMetalLayer
public struct SurfaceSourceMetalLayer: ChainedStructNode {
    public var chain: ChainedStruct
    public var layer: UnsafeLifetimeBoundRawPointer

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        layer: UnsafeLifetimeBoundRawPointer
    ) {
        self.chain = ChainedStruct(
            next: nextInChain,
            sType: .surfaceSourceMetalLayer
        )
        self.layer = layer
    }
}

// WGPUSurfaceSourceWindowsHWND
public struct SurfaceSourceWindowsHWND: ChainedStructNode {
    public var chain: ChainedStruct
    public var hinstance: UnsafeLifetimeBoundRawPointer
    public var hwnd: UnsafeLifetimeBoundRawPointer

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        hinstance: UnsafeLifetimeBoundRawPointer,
        hwnd: UnsafeLifetimeBoundRawPointer
    ) {
        self.chain = ChainedStruct(
            next: nextInChain,
            sType: .surfaceSourceWindowsHWND
        )
        self.hinstance = hinstance
        self.hwnd = hwnd
    }
}

// WGPUSurfaceSourceWaylandSurface
public struct SurfaceSourceWaylandSurface: ChainedStructNode {
    public var chain: ChainedStruct
    public var display: UnsafeLifetimeBoundRawPointer
    public var surface: UnsafeLifetimeBoundRawPointer

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        display: UnsafeLifetimeBoundRawPointer,
        surface: UnsafeLifetimeBoundRawPointer
    ) {
        self.chain = ChainedStruct(
            next: nextInChain,
            sType: .surfaceSourceWaylandSurface
        )
        self.display = display
        self.surface = surface
    }
}

// WGPUSurfaceSourceXlibWindow
public struct SurfaceSourceXlibWindow: ChainedStructNode {
    public var chain: ChainedStruct
    public var display: UnsafeLifetimeBoundRawPointer
    public var window: UInt64

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        display: UnsafeLifetimeBoundRawPointer,
        window: UInt64
    ) {
        self.chain = ChainedStruct(
            next: nextInChain,
            sType: .surfaceSourceXlibWindow
        )
        self.display = display
        self.window = window
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

    // wgpuInstanceCreateSurface
    @MainActor
    public func createSurface(
        descriptor: SurfaceDescriptor = SurfaceDescriptor()
    ) throws -> Surface {
        let handle = try withCChain(descriptor.nextInChain) { nextInChain in
            try withWGPUStringView(descriptor.label) { label in
                var cDescriptor = WGPUSurfaceDescriptor()
                cDescriptor.nextInChain = nextInChain
                cDescriptor.label = label
                guard let handle = wgpuInstanceCreateSurface(self.handle, &cDescriptor) else {
                    throw WebGPUError.createSurfaceFailed
                }
                return handle
            }
        }
        return Surface(handle: handle, instance: self, descriptor: descriptor)
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
                context.continuation.resume(
                    returning: AdapterRequestResult(status: status, adapter: adapter, message: decode(message))
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

    // wgpuAdapterRequestDevice
    public func requestDevice() async throws -> Device {
        let result: DeviceRequestResult = await withCheckedContinuation { continuation in
            let context = DeviceRequestContext(continuation)
            let retainedContext = Unmanaged.passRetained(context).toOpaque()
            var callbackInfo = WGPURequestDeviceCallbackInfo()
            callbackInfo.mode = WGPUCallbackMode_AllowSpontaneous
            callbackInfo.userdata1 = retainedContext
            callbackInfo.callback = { status, device, message, userdata1, _ in
                guard let userdata1 else { return }
                let context = Unmanaged<DeviceRequestContext>
                    .fromOpaque(userdata1)
                    .takeRetainedValue()
                context.continuation.resume(
                    returning: DeviceRequestResult(status: status, device: device, message: decode(message))
                )
            }
            _ = wgpuAdapterRequestDevice(handle, nil, callbackInfo)
        }

        guard result.status == WGPURequestDeviceStatus_Success, let handle = result.device else {
            throw WebGPUError.requestDeviceFailed(
                status: UInt32(truncatingIfNeeded: result.status.rawValue),
                message: result.message
            )
        }
        return Device(handle: handle, adapter: self)
    }
}

public final class Device {
    let handle: WGPUDevice
    private let adapter: Adapter

    init(handle: WGPUDevice, adapter: Adapter) {
        self.handle = handle
        self.adapter = adapter
    }

    deinit {
        // wgpuDeviceRelease
        wgpuDeviceRelease(handle)
    }
}

@MainActor
public final class Surface {
    let handle: WGPUSurface
    private let instance: Instance
    private let descriptor: SurfaceDescriptor

    init(
        handle: WGPUSurface,
        instance: Instance,
        descriptor: SurfaceDescriptor
    ) {
        self.handle = handle
        self.instance = instance
        self.descriptor = descriptor
    }

    isolated deinit {
        // wgpuSurfaceRelease
        wgpuSurfaceRelease(handle)
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

private struct DeviceRequestResult: @unchecked Sendable {
    let status: WGPURequestDeviceStatus
    let device: WGPUDevice?
    let message: String
}

private final class DeviceRequestContext: @unchecked Sendable {
    let continuation: CheckedContinuation<DeviceRequestResult, Never>

    init(_ continuation: CheckedContinuation<DeviceRequestResult, Never>) {
        self.continuation = continuation
    }
}

private func decode(_ view: WGPUStringView) -> String {
    view.data.map {
        let bytes = UnsafeRawPointer($0).assumingMemoryBound(to: UInt8.self)
        return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(view.length)), as: UTF8.self)
    } ?? ""
}

private extension SType {
    var cValue: WGPUSType {
        switch self {
        case .surfaceSourceMetalLayer: WGPUSType_SurfaceSourceMetalLayer
        case .surfaceSourceWindowsHWND: WGPUSType_SurfaceSourceWindowsHWND
        case .surfaceSourceXlibWindow: WGPUSType_SurfaceSourceXlibWindow
        case .surfaceSourceWaylandSurface: WGPUSType_SurfaceSourceWaylandSurface
        }
    }
}

private func withCChain<Result>(
    _ node: (any ChainedStructNode)?,
    body: (UnsafeMutablePointer<WGPUChainedStruct>?) throws -> Result
) throws -> Result {
    guard let node else {
        return try body(nil)
    }

    switch node {
    case let source as SurfaceSourceMetalLayer:
        return try withCChain(source.chain.next) { next in
            try source.layer.withUnsafeMutableRawPointer { layer in
                var cSource = WGPUSurfaceSourceMetalLayer()
                cSource.chain.next = next
                cSource.chain.sType = source.chain.sType.cValue
                cSource.layer = layer
                return try withUnsafeMutablePointer(to: &cSource) { source in
                    try body(
                        UnsafeMutableRawPointer(source)
                            .assumingMemoryBound(to: WGPUChainedStruct.self)
                    )
                }
            }
        }
    case let source as SurfaceSourceWindowsHWND:
        return try withCChain(source.chain.next) { next in
            try source.hinstance.withUnsafeMutableRawPointer { hinstance in
                try source.hwnd.withUnsafeMutableRawPointer { hwnd in
                    var cSource = WGPUSurfaceSourceWindowsHWND()
                    cSource.chain.next = next
                    cSource.chain.sType = source.chain.sType.cValue
                    cSource.hinstance = hinstance
                    cSource.hwnd = hwnd
                    return try withUnsafeMutablePointer(to: &cSource) { source in
                        try body(
                            UnsafeMutableRawPointer(source)
                                .assumingMemoryBound(to: WGPUChainedStruct.self)
                        )
                    }
                }
            }
        }
    case let source as SurfaceSourceWaylandSurface:
        return try withCChain(source.chain.next) { next in
            try source.display.withUnsafeMutableRawPointer { display in
                try source.surface.withUnsafeMutableRawPointer { surface in
                    var cSource = WGPUSurfaceSourceWaylandSurface()
                    cSource.chain.next = next
                    cSource.chain.sType = source.chain.sType.cValue
                    cSource.display = display
                    cSource.surface = surface
                    return try withUnsafeMutablePointer(to: &cSource) { source in
                        try body(
                            UnsafeMutableRawPointer(source)
                                .assumingMemoryBound(to: WGPUChainedStruct.self)
                        )
                    }
                }
            }
        }
    case let source as SurfaceSourceXlibWindow:
        return try withCChain(source.chain.next) { next in
            try source.display.withUnsafeMutableRawPointer { display in
                var cSource = WGPUSurfaceSourceXlibWindow()
                cSource.chain.next = next
                cSource.chain.sType = source.chain.sType.cValue
                cSource.display = display
                cSource.window = source.window
                return try withUnsafeMutablePointer(to: &cSource) { source in
                    try body(
                        UnsafeMutableRawPointer(source)
                            .assumingMemoryBound(to: WGPUChainedStruct.self)
                    )
                }
            }
        }
    default:
        throw WebGPUError.unsupportedChainedStruct(node.chain.sType)
    }
}

private func withWGPUStringView<Result>(
    _ string: String?,
    body: (WGPUStringView) throws -> Result
) rethrows -> Result {
    guard let string else {
        return try body(WGPUStringView())
    }

    return try string.utf8CString.withUnsafeBufferPointer { buffer in
        var view = WGPUStringView()
        view.data = buffer.baseAddress
        view.length = string.utf8.count
        return try body(view)
    }
}
