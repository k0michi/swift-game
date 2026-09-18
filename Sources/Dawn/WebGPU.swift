import CDawn
import Interop

public enum WebGPUError: Error, Equatable {
    case createInstanceFailed
    case requestAdapterFailed(status: UInt32, message: String)
    case requestDeviceFailed(status: UInt32, message: String)
    case createSurfaceFailed
    case unsupportedChainedStruct(SType)
    case getSurfaceCapabilitiesFailed(status: UInt32)
    case unsupportedTextureFormat(TextureFormat)
    case getCurrentTextureFailed(status: UInt32)
    case createTextureViewFailed
    case createBufferFailed
    case createBindGroupFailed
    case createShaderModuleFailed
    case shaderSourceSPIRVTooLarge
    case createPipelineLayoutFailed
    case createRenderPipelineFailed
    case createCommandEncoderFailed
    case createBindGroupLayoutFailed
    case beginRenderPassFailed
    case finishCommandEncoderFailed
    case presentFailed(status: UInt32)
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
// TODO: Migrate the remaining WGPUSType values.
public enum SType: UInt32, Sendable {
    case shaderSourceSPIRV = 0x0000_0001
    case shaderSourceWGSL = 0x0000_0002
    case surfaceSourceMetalLayer = 0x0000_0004
    case surfaceSourceWindowsHWND = 0x0000_0005
    case surfaceSourceXlibWindow = 0x0000_0006
    case surfaceSourceWaylandSurface = 0x0000_0007
    case dawnShaderModuleSPIRVOptionsDescriptor = 0x0005_000B
    case shaderModuleCompilationOptions = 0x0005_0019
    case colorTargetStateExpandResolveTextureDawn = 0x0005_001A
    case dawnShaderSourceSPIRV = 0x0005_0053
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

// WGPUDawnShaderModuleSPIRVOptionsDescriptor
public struct DawnShaderModuleSPIRVOptionsDescriptor: ChainedStructNode {
    public var chain: ChainedStruct
    public var allowNonUniformDerivatives: Bool

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        allowNonUniformDerivatives: Bool = false
    ) {
        self.chain = ChainedStruct(
            next: nextInChain,
            sType: .dawnShaderModuleSPIRVOptionsDescriptor
        )
        self.allowNonUniformDerivatives = allowNonUniformDerivatives
    }
}

// WGPUDawnShaderSourceSPIRV
public struct DawnShaderSourceSPIRV: ChainedStructNode {
    public var chain: ChainedStruct
    public var code: [UInt32]

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        code: [UInt32]
    ) {
        self.chain = ChainedStruct(
            next: nextInChain,
            sType: .dawnShaderSourceSPIRV
        )
        self.code = code
    }
}

// WGPUShaderModuleCompilationOptions
public struct ShaderModuleCompilationOptions: ChainedStructNode {
    public var chain: ChainedStruct
    public var strictMath: Bool

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        strictMath: Bool = false
    ) {
        self.chain = ChainedStruct(
            next: nextInChain,
            sType: .shaderModuleCompilationOptions
        )
        self.strictMath = strictMath
    }
}

// WGPUShaderSourceSPIRV
public struct ShaderSourceSPIRV: ChainedStructNode {
    public var chain: ChainedStruct
    public var code: [UInt32]

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        code: [UInt32]
    ) {
        self.chain = ChainedStruct(
            next: nextInChain,
            sType: .shaderSourceSPIRV
        )
        self.code = code
    }
}

// WGPUShaderSourceWGSL
public struct ShaderSourceWGSL: ChainedStructNode {
    public var chain: ChainedStruct
    public var code: String

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        code: String
    ) {
        self.chain = ChainedStruct(
            next: nextInChain,
            sType: .shaderSourceWGSL
        )
        self.code = code
    }
}

// WGPUShaderModuleDescriptor
public struct ShaderModuleDescriptor {
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

// WGPUTextureUsage
public struct TextureUsage: OptionSet, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let copySrc = Self(rawValue: 0x0000_0001)
    public static let copyDst = Self(rawValue: 0x0000_0002)
    public static let textureBinding = Self(rawValue: 0x0000_0004)
    public static let storageBinding = Self(rawValue: 0x0000_0008)
    public static let renderAttachment = Self(rawValue: 0x0000_0010)
    public static let transientAttachment = Self(rawValue: 0x0000_0020)
    public static let storageAttachment = Self(rawValue: 0x0000_0040)
}

// WGPUTextureFormat
public struct TextureFormat: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let undefined = Self(rawValue: 0x0000_0000)
    public static let r8Unorm = Self(rawValue: 0x0000_0001)
    public static let r8Snorm = Self(rawValue: 0x0000_0002)
    public static let r8Uint = Self(rawValue: 0x0000_0003)
    public static let r8Sint = Self(rawValue: 0x0000_0004)
    public static let r16Unorm = Self(rawValue: 0x0000_0005)
    public static let r16Snorm = Self(rawValue: 0x0000_0006)
    public static let r16Uint = Self(rawValue: 0x0000_0007)
    public static let r16Sint = Self(rawValue: 0x0000_0008)
    public static let r16Float = Self(rawValue: 0x0000_0009)
    public static let rg8Unorm = Self(rawValue: 0x0000_000A)
    public static let rg8Snorm = Self(rawValue: 0x0000_000B)
    public static let rg8Uint = Self(rawValue: 0x0000_000C)
    public static let rg8Sint = Self(rawValue: 0x0000_000D)
    public static let r32Float = Self(rawValue: 0x0000_000E)
    public static let r32Uint = Self(rawValue: 0x0000_000F)
    public static let r32Sint = Self(rawValue: 0x0000_0010)
    public static let rg16Unorm = Self(rawValue: 0x0000_0011)
    public static let rg16Snorm = Self(rawValue: 0x0000_0012)
    public static let rg16Uint = Self(rawValue: 0x0000_0013)
    public static let rg16Sint = Self(rawValue: 0x0000_0014)
    public static let rg16Float = Self(rawValue: 0x0000_0015)
    public static let rgba8Unorm = Self(rawValue: 0x0000_0016)
    public static let rgba8UnormSrgb = Self(rawValue: 0x0000_0017)
    public static let rgba8Snorm = Self(rawValue: 0x0000_0018)
    public static let rgba8Uint = Self(rawValue: 0x0000_0019)
    public static let rgba8Sint = Self(rawValue: 0x0000_001A)
    public static let bgra8Unorm = Self(rawValue: 0x0000_001B)
    public static let bgra8UnormSrgb = Self(rawValue: 0x0000_001C)
    public static let rgb10A2Uint = Self(rawValue: 0x0000_001D)
    public static let rgb10A2Unorm = Self(rawValue: 0x0000_001E)
    public static let rg11B10Ufloat = Self(rawValue: 0x0000_001F)
    public static let rgb9E5Ufloat = Self(rawValue: 0x0000_0020)
    public static let rg32Float = Self(rawValue: 0x0000_0021)
    public static let rg32Uint = Self(rawValue: 0x0000_0022)
    public static let rg32Sint = Self(rawValue: 0x0000_0023)
    public static let rgba16Unorm = Self(rawValue: 0x0000_0024)
    public static let rgba16Snorm = Self(rawValue: 0x0000_0025)
    public static let rgba16Uint = Self(rawValue: 0x0000_0026)
    public static let rgba16Sint = Self(rawValue: 0x0000_0027)
    public static let rgba16Float = Self(rawValue: 0x0000_0028)
    public static let rgba32Float = Self(rawValue: 0x0000_0029)
    public static let rgba32Uint = Self(rawValue: 0x0000_002A)
    public static let rgba32Sint = Self(rawValue: 0x0000_002B)
    public static let stencil8 = Self(rawValue: 0x0000_002C)
    public static let depth16Unorm = Self(rawValue: 0x0000_002D)
    public static let depth24Plus = Self(rawValue: 0x0000_002E)
    public static let depth24PlusStencil8 = Self(rawValue: 0x0000_002F)
    public static let depth32Float = Self(rawValue: 0x0000_0030)
    public static let depth32FloatStencil8 = Self(rawValue: 0x0000_0031)
    public static let bc1RGBAUnorm = Self(rawValue: 0x0000_0032)
    public static let bc1RGBAUnormSrgb = Self(rawValue: 0x0000_0033)
    public static let bc2RGBAUnorm = Self(rawValue: 0x0000_0034)
    public static let bc2RGBAUnormSrgb = Self(rawValue: 0x0000_0035)
    public static let bc3RGBAUnorm = Self(rawValue: 0x0000_0036)
    public static let bc3RGBAUnormSrgb = Self(rawValue: 0x0000_0037)
    public static let bc4RUnorm = Self(rawValue: 0x0000_0038)
    public static let bc4RSnorm = Self(rawValue: 0x0000_0039)
    public static let bc5RGUnorm = Self(rawValue: 0x0000_003A)
    public static let bc5RGSnorm = Self(rawValue: 0x0000_003B)
    public static let bc6HRGBUfloat = Self(rawValue: 0x0000_003C)
    public static let bc6HRGBFloat = Self(rawValue: 0x0000_003D)
    public static let bc7RGBAUnorm = Self(rawValue: 0x0000_003E)
    public static let bc7RGBAUnormSrgb = Self(rawValue: 0x0000_003F)
    public static let etc2RGB8Unorm = Self(rawValue: 0x0000_0040)
    public static let etc2RGB8UnormSrgb = Self(rawValue: 0x0000_0041)
    public static let etc2RGB8A1Unorm = Self(rawValue: 0x0000_0042)
    public static let etc2RGB8A1UnormSrgb = Self(rawValue: 0x0000_0043)
    public static let etc2RGBA8Unorm = Self(rawValue: 0x0000_0044)
    public static let etc2RGBA8UnormSrgb = Self(rawValue: 0x0000_0045)
    public static let eacR11Unorm = Self(rawValue: 0x0000_0046)
    public static let eacR11Snorm = Self(rawValue: 0x0000_0047)
    public static let eacRG11Unorm = Self(rawValue: 0x0000_0048)
    public static let eacRG11Snorm = Self(rawValue: 0x0000_0049)
    public static let astc4x4Unorm = Self(rawValue: 0x0000_004A)
    public static let astc4x4UnormSrgb = Self(rawValue: 0x0000_004B)
    public static let astc5x4Unorm = Self(rawValue: 0x0000_004C)
    public static let astc5x4UnormSrgb = Self(rawValue: 0x0000_004D)
    public static let astc5x5Unorm = Self(rawValue: 0x0000_004E)
    public static let astc5x5UnormSrgb = Self(rawValue: 0x0000_004F)
    public static let astc6x5Unorm = Self(rawValue: 0x0000_0050)
    public static let astc6x5UnormSrgb = Self(rawValue: 0x0000_0051)
    public static let astc6x6Unorm = Self(rawValue: 0x0000_0052)
    public static let astc6x6UnormSrgb = Self(rawValue: 0x0000_0053)
    public static let astc8x5Unorm = Self(rawValue: 0x0000_0054)
    public static let astc8x5UnormSrgb = Self(rawValue: 0x0000_0055)
    public static let astc8x6Unorm = Self(rawValue: 0x0000_0056)
    public static let astc8x6UnormSrgb = Self(rawValue: 0x0000_0057)
    public static let astc8x8Unorm = Self(rawValue: 0x0000_0058)
    public static let astc8x8UnormSrgb = Self(rawValue: 0x0000_0059)
    public static let astc10x5Unorm = Self(rawValue: 0x0000_005A)
    public static let astc10x5UnormSrgb = Self(rawValue: 0x0000_005B)
    public static let astc10x6Unorm = Self(rawValue: 0x0000_005C)
    public static let astc10x6UnormSrgb = Self(rawValue: 0x0000_005D)
    public static let astc10x8Unorm = Self(rawValue: 0x0000_005E)
    public static let astc10x8UnormSrgb = Self(rawValue: 0x0000_005F)
    public static let astc10x10Unorm = Self(rawValue: 0x0000_0060)
    public static let astc10x10UnormSrgb = Self(rawValue: 0x0000_0061)
    public static let astc12x10Unorm = Self(rawValue: 0x0000_0062)
    public static let astc12x10UnormSrgb = Self(rawValue: 0x0000_0063)
    public static let astc12x12Unorm = Self(rawValue: 0x0000_0064)
    public static let astc12x12UnormSrgb = Self(rawValue: 0x0000_0065)
    public static let r8BG8Biplanar420Unorm = Self(rawValue: 0x0005_0000)
    public static let r10X6BG10X6Biplanar420Unorm = Self(rawValue: 0x0005_0001)
    public static let r8BG8A8Triplanar420Unorm = Self(rawValue: 0x0005_0002)
    public static let r8BG8Biplanar422Unorm = Self(rawValue: 0x0005_0003)
    public static let r8BG8Biplanar444Unorm = Self(rawValue: 0x0005_0004)
    public static let r10X6BG10X6Biplanar422Unorm = Self(rawValue: 0x0005_0005)
    public static let r10X6BG10X6Biplanar444Unorm = Self(rawValue: 0x0005_0006)
    public static let opaqueYCbCrAndroid = Self(rawValue: 0x0005_0007)
}

// WGPUBlendFactor
public enum BlendFactor: UInt32, Sendable {
    case undefined = 0x0000_0000
    case zero = 0x0000_0001
    case one = 0x0000_0002
    case src = 0x0000_0003
    case oneMinusSrc = 0x0000_0004
    case srcAlpha = 0x0000_0005
    case oneMinusSrcAlpha = 0x0000_0006
    case dst = 0x0000_0007
    case oneMinusDst = 0x0000_0008
    case dstAlpha = 0x0000_0009
    case oneMinusDstAlpha = 0x0000_000A
    case srcAlphaSaturated = 0x0000_000B
    case constant = 0x0000_000C
    case oneMinusConstant = 0x0000_000D
    case src1 = 0x0000_000E
    case oneMinusSrc1 = 0x0000_000F
    case src1Alpha = 0x0000_0010
    case oneMinusSrc1Alpha = 0x0000_0011
}

// WGPUBlendOperation
public enum BlendOperation: UInt32, Sendable {
    case undefined = 0x0000_0000
    case add = 0x0000_0001
    case subtract = 0x0000_0002
    case reverseSubtract = 0x0000_0003
    case min = 0x0000_0004
    case max = 0x0000_0005
}

// WGPUVertexFormat
public enum VertexFormat: UInt32, Sendable {
    case uint8 = 0x0000_0001
    case uint8x2 = 0x0000_0002
    case uint8x4 = 0x0000_0003
    case sint8 = 0x0000_0004
    case sint8x2 = 0x0000_0005
    case sint8x4 = 0x0000_0006
    case unorm8 = 0x0000_0007
    case unorm8x2 = 0x0000_0008
    case unorm8x4 = 0x0000_0009
    case snorm8 = 0x0000_000A
    case snorm8x2 = 0x0000_000B
    case snorm8x4 = 0x0000_000C
    case uint16 = 0x0000_000D
    case uint16x2 = 0x0000_000E
    case uint16x4 = 0x0000_000F
    case sint16 = 0x0000_0010
    case sint16x2 = 0x0000_0011
    case sint16x4 = 0x0000_0012
    case unorm16 = 0x0000_0013
    case unorm16x2 = 0x0000_0014
    case unorm16x4 = 0x0000_0015
    case snorm16 = 0x0000_0016
    case snorm16x2 = 0x0000_0017
    case snorm16x4 = 0x0000_0018
    case float16 = 0x0000_0019
    case float16x2 = 0x0000_001A
    case float16x4 = 0x0000_001B
    case float32 = 0x0000_001C
    case float32x2 = 0x0000_001D
    case float32x3 = 0x0000_001E
    case float32x4 = 0x0000_001F
    case uint32 = 0x0000_0020
    case uint32x2 = 0x0000_0021
    case uint32x3 = 0x0000_0022
    case uint32x4 = 0x0000_0023
    case sint32 = 0x0000_0024
    case sint32x2 = 0x0000_0025
    case sint32x3 = 0x0000_0026
    case sint32x4 = 0x0000_0027
    case unorm10_10_10_2 = 0x0000_0028
    case unorm8x4BGRA = 0x0000_0029
    case snorm10_10_10_2 = 0x0000_002A
}

// WGPUVertexStepMode
public enum VertexStepMode: UInt32, Sendable {
    case undefined = 0x0000_0000
    case vertex = 0x0000_0001
    case instance = 0x0000_0002
}

// WGPUCompareFunction
public enum CompareFunction: UInt32, Sendable {
    case undefined = 0x0000_0000
    case never = 0x0000_0001
    case less = 0x0000_0002
    case equal = 0x0000_0003
    case lessEqual = 0x0000_0004
    case greater = 0x0000_0005
    case notEqual = 0x0000_0006
    case greaterEqual = 0x0000_0007
    case always = 0x0000_0008
}

// WGPUCullMode
public enum CullMode: UInt32, Sendable {
    case undefined = 0x0000_0000
    case none = 0x0000_0001
    case front = 0x0000_0002
    case back = 0x0000_0003
}

// WGPUFrontFace
public enum FrontFace: UInt32, Sendable {
    case undefined = 0x0000_0000
    case ccw = 0x0000_0001
    case cw = 0x0000_0002
}

// WGPUIndexFormat
public enum IndexFormat: UInt32, Sendable {
    case undefined = 0x0000_0000
    case uint16 = 0x0000_0001
    case uint32 = 0x0000_0002
}

// WGPUPrimitiveTopology
public enum PrimitiveTopology: UInt32, Sendable {
    case undefined = 0x0000_0000
    case pointList = 0x0000_0001
    case lineList = 0x0000_0002
    case lineStrip = 0x0000_0003
    case triangleList = 0x0000_0004
    case triangleStrip = 0x0000_0005
}

// WGPUStencilOperation
public enum StencilOperation: UInt32, Sendable {
    case undefined = 0x0000_0000
    case keep = 0x0000_0001
    case zero = 0x0000_0002
    case replace = 0x0000_0003
    case invert = 0x0000_0004
    case incrementClamp = 0x0000_0005
    case decrementClamp = 0x0000_0006
    case incrementWrap = 0x0000_0007
    case decrementWrap = 0x0000_0008
}

// WGPUColorWriteMask
public struct ColorWriteMask: OptionSet, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let none: Self = []
    public static let red = Self(rawValue: 0x0000_0000_0000_0001)
    public static let green = Self(rawValue: 0x0000_0000_0000_0002)
    public static let blue = Self(rawValue: 0x0000_0000_0000_0004)
    public static let alpha = Self(rawValue: 0x0000_0000_0000_0008)
    public static let all: Self = [.red, .green, .blue, .alpha]
}

// WGPUBufferBindingType
public enum BufferBindingType: UInt32, Sendable {
    case bindingNotUsed = 0x0000_0000
    case undefined = 0x0000_0001
    case uniform = 0x0000_0002
    case storage = 0x0000_0003
    case readOnlyStorage = 0x0000_0004
}

// WGPUSamplerBindingType
public enum SamplerBindingType: UInt32, Sendable {
    case bindingNotUsed = 0x0000_0000
    case undefined = 0x0000_0001
    case filtering = 0x0000_0002
    case nonFiltering = 0x0000_0003
    case comparison = 0x0000_0004
}

// WGPUStorageTextureAccess
public enum StorageTextureAccess: UInt32, Sendable {
    case bindingNotUsed = 0x0000_0000
    case undefined = 0x0000_0001
    case writeOnly = 0x0000_0002
    case readOnly = 0x0000_0003
    case readWrite = 0x0000_0004
}

// WGPUTextureSampleType
public enum TextureSampleType: UInt32, Sendable {
    case bindingNotUsed = 0x0000_0000
    case undefined = 0x0000_0001
    case float = 0x0000_0002
    case unfilterableFloat = 0x0000_0003
    case depth = 0x0000_0004
    case sint = 0x0000_0005
    case uint = 0x0000_0006
}

// WGPUTextureViewDimension
public enum TextureViewDimension: UInt32, Sendable {
    case undefined = 0x0000_0000
    case `1D` = 0x0000_0001
    case `2D` = 0x0000_0002
    case `2DArray` = 0x0000_0003
    case cube = 0x0000_0004
    case cubeArray = 0x0000_0005
    case `3D` = 0x0000_0006
}

// WGPUShaderStage
public struct ShaderStage: OptionSet, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let none: Self = []
    public static let vertex = Self(rawValue: 0x0000_0000_0000_0001)
    public static let fragment = Self(rawValue: 0x0000_0000_0000_0002)
    public static let compute = Self(rawValue: 0x0000_0000_0000_0004)
}

// WGPUBufferUsage
public struct BufferUsage: OptionSet, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let none: Self = []
    public static let mapRead = Self(rawValue: 0x0000_0000_0000_0001)
    public static let mapWrite = Self(rawValue: 0x0000_0000_0000_0002)
    public static let copySrc = Self(rawValue: 0x0000_0000_0000_0004)
    public static let copyDst = Self(rawValue: 0x0000_0000_0000_0008)
    public static let index = Self(rawValue: 0x0000_0000_0000_0010)
    public static let vertex = Self(rawValue: 0x0000_0000_0000_0020)
    public static let uniform = Self(rawValue: 0x0000_0000_0000_0040)
    public static let storage = Self(rawValue: 0x0000_0000_0000_0080)
    public static let indirect = Self(rawValue: 0x0000_0000_0000_0100)
    public static let queryResolve = Self(rawValue: 0x0000_0000_0000_0200)
    public static let texelBuffer = Self(rawValue: 0x0000_0000_0000_0400)
}

// WGPUBufferDescriptor
public struct BufferDescriptor {
    public var nextInChain: (any ChainedStructNode)?
    public var label: String?
    public var usage: BufferUsage
    public var size: UInt64
    public var mappedAtCreation: Bool

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        label: String? = nil,
        usage: BufferUsage,
        size: UInt64,
        mappedAtCreation: Bool = false
    ) {
        self.nextInChain = nextInChain
        self.label = label
        self.usage = usage
        self.size = size
        self.mappedAtCreation = mappedAtCreation
    }
}

// WGPUBufferBindingLayout
public struct BufferBindingLayout {
    public var nextInChain: (any ChainedStructNode)?
    public var type: BufferBindingType
    public var hasDynamicOffset: Bool
    public var minBindingSize: UInt64

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        type: BufferBindingType = .undefined,
        hasDynamicOffset: Bool = false,
        minBindingSize: UInt64 = 0
    ) {
        self.nextInChain = nextInChain
        self.type = type
        self.hasDynamicOffset = hasDynamicOffset
        self.minBindingSize = minBindingSize
    }
}

// WGPUSamplerBindingLayout
public struct SamplerBindingLayout {
    public var nextInChain: (any ChainedStructNode)?
    public var type: SamplerBindingType

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        type: SamplerBindingType = .undefined
    ) {
        self.nextInChain = nextInChain
        self.type = type
    }
}

// WGPUTextureBindingLayout
public struct TextureBindingLayout {
    public var nextInChain: (any ChainedStructNode)?
    public var sampleType: TextureSampleType
    public var viewDimension: TextureViewDimension
    public var multisampled: Bool

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        sampleType: TextureSampleType = .undefined,
        viewDimension: TextureViewDimension = .undefined,
        multisampled: Bool = false
    ) {
        self.nextInChain = nextInChain
        self.sampleType = sampleType
        self.viewDimension = viewDimension
        self.multisampled = multisampled
    }
}

// WGPUStorageTextureBindingLayout
public struct StorageTextureBindingLayout {
    public var nextInChain: (any ChainedStructNode)?
    public var access: StorageTextureAccess
    public var format: TextureFormat
    public var viewDimension: TextureViewDimension

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        access: StorageTextureAccess = .undefined,
        format: TextureFormat = .undefined,
        viewDimension: TextureViewDimension = .undefined
    ) {
        self.nextInChain = nextInChain
        self.access = access
        self.format = format
        self.viewDimension = viewDimension
    }
}

// TODO: Migrate WGPUExternalTextureBindingLayout.
// TODO: Migrate WGPUStaticSamplerBindingLayout.
// TODO: Migrate WGPUTexelBufferAccess and WGPUTexelBufferBindingLayout.
// WGPUBindGroupLayoutEntry
public struct BindGroupLayoutEntry {
    public var nextInChain: (any ChainedStructNode)?
    public var binding: UInt32
    public var visibility: ShaderStage
    public var bindingArraySize: UInt32
    public var buffer: BufferBindingLayout
    public var sampler: SamplerBindingLayout
    public var texture: TextureBindingLayout
    public var storageTexture: StorageTextureBindingLayout

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        binding: UInt32,
        visibility: ShaderStage,
        bindingArraySize: UInt32 = 0,
        buffer: BufferBindingLayout = BufferBindingLayout(type: .bindingNotUsed),
        sampler: SamplerBindingLayout = SamplerBindingLayout(type: .bindingNotUsed),
        texture: TextureBindingLayout = TextureBindingLayout(sampleType: .bindingNotUsed),
        storageTexture: StorageTextureBindingLayout = StorageTextureBindingLayout(access: .bindingNotUsed)
    ) {
        self.nextInChain = nextInChain
        self.binding = binding
        self.visibility = visibility
        self.bindingArraySize = bindingArraySize
        self.buffer = buffer
        self.sampler = sampler
        self.texture = texture
        self.storageTexture = storageTexture
    }
}

// WGPUBindGroupLayoutDescriptor
public struct BindGroupLayoutDescriptor {
    public var nextInChain: (any ChainedStructNode)?
    public var label: String?
    public var entries: [BindGroupLayoutEntry]

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        label: String? = nil,
        entries: [BindGroupLayoutEntry]
    ) {
        self.nextInChain = nextInChain
        self.label = label
        self.entries = entries
    }
}

// WGPU_WHOLE_SIZE
public let wholeSize = UInt64.max

// WGPUBindGroupEntry
public struct BindGroupEntry {
    public var nextInChain: (any ChainedStructNode)?
    public var binding: UInt32
    public var buffer: Buffer?
    public var offset: UInt64
    public var size: UInt64
    public var sampler: Sampler?
    public var textureView: TextureView?

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        binding: UInt32,
        buffer: Buffer? = nil,
        offset: UInt64 = 0,
        size: UInt64 = wholeSize,
        sampler: Sampler? = nil,
        textureView: TextureView? = nil
    ) {
        self.nextInChain = nextInChain
        self.binding = binding
        self.buffer = buffer
        self.offset = offset
        self.size = size
        self.sampler = sampler
        self.textureView = textureView
    }
}

// WGPUBindGroupDescriptor
public struct BindGroupDescriptor {
    public var nextInChain: (any ChainedStructNode)?
    public var label: String?
    public var layout: BindGroupLayout
    public var entries: [BindGroupEntry]

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        label: String? = nil,
        layout: BindGroupLayout,
        entries: [BindGroupEntry]
    ) {
        self.nextInChain = nextInChain
        self.label = label
        self.layout = layout
        self.entries = entries
    }
}

// TODO: Migrate WGPUPipelineLayoutResourceTable.
// TODO: Migrate WGPUPipelineLayoutStorageAttachment and WGPUPipelineLayoutPixelLocalStorage.
// WGPUPipelineLayoutDescriptor
public struct PipelineLayoutDescriptor {
    public var nextInChain: (any ChainedStructNode)?
    public var label: String?
    public var bindGroupLayouts: [BindGroupLayout]
    public var immediateSize: UInt32

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        label: String? = nil,
        bindGroupLayouts: [BindGroupLayout],
        immediateSize: UInt32 = 0
    ) {
        self.nextInChain = nextInChain
        self.label = label
        self.bindGroupLayouts = bindGroupLayouts
        self.immediateSize = immediateSize
    }
}

// WGPUBlendComponent
public struct BlendComponent {
    public var operation: BlendOperation
    public var srcFactor: BlendFactor
    public var dstFactor: BlendFactor

    public init(
        operation: BlendOperation = .undefined,
        srcFactor: BlendFactor = .undefined,
        dstFactor: BlendFactor = .undefined
    ) {
        self.operation = operation
        self.srcFactor = srcFactor
        self.dstFactor = dstFactor
    }
}

// WGPUColorTargetStateExpandResolveTextureDawn
public struct ColorTargetStateExpandResolveTextureDawn: ChainedStructNode {
    public var chain: ChainedStruct
    public var enabled: Bool

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        enabled: Bool = false
    ) {
        self.chain = ChainedStruct(
            next: nextInChain,
            sType: .colorTargetStateExpandResolveTextureDawn
        )
        self.enabled = enabled
    }
}

// WGPUConstantEntry
public struct ConstantEntry {
    public var nextInChain: (any ChainedStructNode)?
    public var key: String
    public var value: Double

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        key: String,
        value: Double
    ) {
        self.nextInChain = nextInChain
        self.key = key
        self.value = value
    }
}

// WGPUVertexAttribute
public struct VertexAttribute {
    public var nextInChain: (any ChainedStructNode)?
    public var format: VertexFormat
    public var offset: UInt64
    public var shaderLocation: UInt32

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        format: VertexFormat,
        offset: UInt64,
        shaderLocation: UInt32
    ) {
        self.nextInChain = nextInChain
        self.format = format
        self.offset = offset
        self.shaderLocation = shaderLocation
    }
}

// WGPUBlendState
public struct BlendState {
    public var color: BlendComponent
    public var alpha: BlendComponent

    public init(color: BlendComponent, alpha: BlendComponent) {
        self.color = color
        self.alpha = alpha
    }
}

// WGPUVertexBufferLayout
public struct VertexBufferLayout {
    public var nextInChain: (any ChainedStructNode)?
    public var stepMode: VertexStepMode
    public var arrayStride: UInt64
    public var attributes: [VertexAttribute]

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        stepMode: VertexStepMode = .undefined,
        arrayStride: UInt64,
        attributes: [VertexAttribute]
    ) {
        self.nextInChain = nextInChain
        self.stepMode = stepMode
        self.arrayStride = arrayStride
        self.attributes = attributes
    }
}

// WGPUColorTargetState
public struct ColorTargetState {
    public var nextInChain: (any ChainedStructNode)?
    public var format: TextureFormat
    public var blend: BlendState?
    public var writeMask: ColorWriteMask

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        format: TextureFormat,
        blend: BlendState? = nil,
        writeMask: ColorWriteMask = .all
    ) {
        self.nextInChain = nextInChain
        self.format = format
        self.blend = blend
        self.writeMask = writeMask
    }
}

// WGPUVertexState
public struct VertexState {
    public var nextInChain: (any ChainedStructNode)?
    public var module: ShaderModule
    public var entryPoint: String?
    public var constants: [ConstantEntry]
    public var buffers: [VertexBufferLayout]

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        module: ShaderModule,
        entryPoint: String? = nil,
        constants: [ConstantEntry] = [],
        buffers: [VertexBufferLayout] = []
    ) {
        self.nextInChain = nextInChain
        self.module = module
        self.entryPoint = entryPoint
        self.constants = constants
        self.buffers = buffers
    }
}

// WGPUFragmentState
public struct FragmentState {
    public var nextInChain: (any ChainedStructNode)?
    public var module: ShaderModule
    public var entryPoint: String?
    public var constants: [ConstantEntry]
    public var targets: [ColorTargetState]

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        module: ShaderModule,
        entryPoint: String? = nil,
        constants: [ConstantEntry] = [],
        targets: [ColorTargetState]
    ) {
        self.nextInChain = nextInChain
        self.module = module
        self.entryPoint = entryPoint
        self.constants = constants
        self.targets = targets
    }
}

// WGPUPrimitiveState
public struct PrimitiveState {
    public var nextInChain: (any ChainedStructNode)?
    public var topology: PrimitiveTopology
    public var stripIndexFormat: IndexFormat
    public var frontFace: FrontFace
    public var cullMode: CullMode
    public var unclippedDepth: Bool

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        topology: PrimitiveTopology = .undefined,
        stripIndexFormat: IndexFormat = .undefined,
        frontFace: FrontFace = .undefined,
        cullMode: CullMode = .undefined,
        unclippedDepth: Bool = false
    ) {
        self.nextInChain = nextInChain
        self.topology = topology
        self.stripIndexFormat = stripIndexFormat
        self.frontFace = frontFace
        self.cullMode = cullMode
        self.unclippedDepth = unclippedDepth
    }
}

// WGPUStencilFaceState
public struct StencilFaceState {
    public var compare: CompareFunction
    public var failOp: StencilOperation
    public var depthFailOp: StencilOperation
    public var passOp: StencilOperation

    public init(
        compare: CompareFunction = .undefined,
        failOp: StencilOperation = .undefined,
        depthFailOp: StencilOperation = .undefined,
        passOp: StencilOperation = .undefined
    ) {
        self.compare = compare
        self.failOp = failOp
        self.depthFailOp = depthFailOp
        self.passOp = passOp
    }
}

// WGPUDepthStencilState
public struct DepthStencilState {
    public var nextInChain: (any ChainedStructNode)?
    public var format: TextureFormat
    public var depthWriteEnabled: Bool?
    public var depthCompare: CompareFunction
    public var stencilFront: StencilFaceState
    public var stencilBack: StencilFaceState
    public var stencilReadMask: UInt32
    public var stencilWriteMask: UInt32
    public var depthBias: Int32
    public var depthBiasSlopeScale: Float
    public var depthBiasClamp: Float

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        format: TextureFormat,
        depthWriteEnabled: Bool? = nil,
        depthCompare: CompareFunction = .undefined,
        stencilFront: StencilFaceState = StencilFaceState(),
        stencilBack: StencilFaceState = StencilFaceState(),
        stencilReadMask: UInt32 = UInt32.max,
        stencilWriteMask: UInt32 = UInt32.max,
        depthBias: Int32 = 0,
        depthBiasSlopeScale: Float = 0,
        depthBiasClamp: Float = 0
    ) {
        self.nextInChain = nextInChain
        self.format = format
        self.depthWriteEnabled = depthWriteEnabled
        self.depthCompare = depthCompare
        self.stencilFront = stencilFront
        self.stencilBack = stencilBack
        self.stencilReadMask = stencilReadMask
        self.stencilWriteMask = stencilWriteMask
        self.depthBias = depthBias
        self.depthBiasSlopeScale = depthBiasSlopeScale
        self.depthBiasClamp = depthBiasClamp
    }
}

// WGPUMultisampleState
public struct MultisampleState {
    public var nextInChain: (any ChainedStructNode)?
    public var count: UInt32
    public var mask: UInt32
    public var alphaToCoverageEnabled: Bool

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        count: UInt32 = 1,
        mask: UInt32 = UInt32.max,
        alphaToCoverageEnabled: Bool = false
    ) {
        self.nextInChain = nextInChain
        self.count = count
        self.mask = mask
        self.alphaToCoverageEnabled = alphaToCoverageEnabled
    }
}

// WGPURenderPipelineDescriptor
public struct RenderPipelineDescriptor {
    public var nextInChain: (any ChainedStructNode)?
    public var label: String?
    public var layout: PipelineLayout?
    public var vertex: VertexState
    public var primitive: PrimitiveState
    public var depthStencil: DepthStencilState?
    public var multisample: MultisampleState
    public var fragment: FragmentState?

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        label: String? = nil,
        layout: PipelineLayout? = nil,
        vertex: VertexState,
        primitive: PrimitiveState = PrimitiveState(),
        depthStencil: DepthStencilState? = nil,
        multisample: MultisampleState = MultisampleState(),
        fragment: FragmentState? = nil
    ) {
        self.nextInChain = nextInChain
        self.label = label
        self.layout = layout
        self.vertex = vertex
        self.primitive = primitive
        self.depthStencil = depthStencil
        self.multisample = multisample
        self.fragment = fragment
    }
}

// WGPUPresentMode
public enum PresentMode: UInt32, Sendable {
    case undefined = 0x0000_0000
    case fifo = 0x0000_0001
    case fifoRelaxed = 0x0000_0002
    case immediate = 0x0000_0003
    case mailbox = 0x0000_0004
}

// WGPUCompositeAlphaMode
public enum CompositeAlphaMode: UInt32, Sendable {
    case auto = 0x0000_0000
    case opaque = 0x0000_0001
    case premultiplied = 0x0000_0002
    case unpremultiplied = 0x0000_0003
    case inherit = 0x0000_0004
}

// WGPUSurfaceCapabilities
public struct SurfaceCapabilities {
    public var usages: TextureUsage
    public var formats: [TextureFormat]
    public var presentModes: [PresentMode]
    public var alphaModes: [CompositeAlphaMode]

    public init(
        usages: TextureUsage,
        formats: [TextureFormat],
        presentModes: [PresentMode],
        alphaModes: [CompositeAlphaMode]
    ) {
        self.usages = usages
        self.formats = formats
        self.presentModes = presentModes
        self.alphaModes = alphaModes
    }
}

// WGPUSurfaceConfiguration
public struct SurfaceConfiguration {
    public var nextInChain: (any ChainedStructNode)?
    public var device: Device
    public var format: TextureFormat
    public var usage: TextureUsage
    public var width: UInt32
    public var height: UInt32
    public var viewFormats: [TextureFormat]
    public var alphaMode: CompositeAlphaMode
    public var presentMode: PresentMode

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        device: Device,
        format: TextureFormat,
        usage: TextureUsage = .renderAttachment,
        width: UInt32,
        height: UInt32,
        viewFormats: [TextureFormat] = [],
        alphaMode: CompositeAlphaMode = .auto,
        presentMode: PresentMode = .fifo
    ) {
        self.nextInChain = nextInChain
        self.device = device
        self.format = format
        self.usage = usage
        self.width = width
        self.height = height
        self.viewFormats = viewFormats
        self.alphaMode = alphaMode
        self.presentMode = presentMode
    }
}

// WGPUSurfaceGetCurrentTextureStatus
public enum SurfaceGetCurrentTextureStatus: UInt32, Sendable {
    case successOptimal = 0x0000_0001
    case successSuboptimal = 0x0000_0002
    case timeout = 0x0000_0003
    case outdated = 0x0000_0004
    case lost = 0x0000_0005
    case error = 0x0000_0006
}

// WGPUColor
public struct Color: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

// WGPULoadOp
public enum LoadOp: UInt32, Sendable {
    case undefined = 0x0000_0000
    case load = 0x0000_0001
    case clear = 0x0000_0002
    case expandResolveTexture = 0x0005_0003
}

// WGPUStoreOp
public enum StoreOp: UInt32, Sendable {
    case undefined = 0x0000_0000
    case store = 0x0000_0001
    case discard = 0x0000_0002
}

// WGPUCommandEncoderDescriptor
public struct CommandEncoderDescriptor {
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

// WGPUCommandBufferDescriptor
public struct CommandBufferDescriptor {
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

// WGPURenderPassColorAttachment
public struct RenderPassColorAttachment {
    public var nextInChain: (any ChainedStructNode)?
    public var view: TextureView
    public var resolveTarget: TextureView?
    public var loadOp: LoadOp
    public var storeOp: StoreOp
    public var clearValue: Color

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        view: TextureView,
        resolveTarget: TextureView? = nil,
        loadOp: LoadOp,
        storeOp: StoreOp,
        clearValue: Color
    ) {
        self.nextInChain = nextInChain
        self.view = view
        self.resolveTarget = resolveTarget
        self.loadOp = loadOp
        self.storeOp = storeOp
        self.clearValue = clearValue
    }
}

// WGPURenderPassDescriptor
public struct RenderPassDescriptor {
    public var nextInChain: (any ChainedStructNode)?
    public var label: String?
    public var colorAttachments: [RenderPassColorAttachment]

    public init(
        nextInChain: (any ChainedStructNode)? = nil,
        label: String? = nil,
        colorAttachments: [RenderPassColorAttachment]
    ) {
        self.nextInChain = nextInChain
        self.label = label
        self.colorAttachments = colorAttachments
    }
}

public final class Instance: @unchecked Sendable {
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

public final class Adapter: @unchecked Sendable {
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

public final class Device: @unchecked Sendable {
    let handle: WGPUDevice
    private let adapter: Adapter

    init(handle: WGPUDevice, adapter: Adapter) {
        self.handle = handle
        self.adapter = adapter
    }

    // wgpuDeviceGetQueue
    public func getQueue() -> Queue {
        Queue(handle: wgpuDeviceGetQueue(handle), device: self)
    }

    // wgpuDeviceCreateBuffer
    public func createBuffer(
        descriptor: BufferDescriptor
    ) throws -> Buffer {
        let handle = try withCChain(descriptor.nextInChain) { nextInChain in
            try withWGPUStringView(descriptor.label) { label in
                var cDescriptor = WGPUBufferDescriptor()
                cDescriptor.nextInChain = nextInChain
                cDescriptor.label = label
                cDescriptor.usage = descriptor.usage.rawValue
                cDescriptor.size = descriptor.size
                cDescriptor.mappedAtCreation = descriptor.mappedAtCreation ? 1 : 0
                guard let handle = wgpuDeviceCreateBuffer(self.handle, &cDescriptor) else {
                    throw WebGPUError.createBufferFailed
                }
                return handle
            }
        }
        return Buffer(handle: handle, device: self)
    }

    // wgpuDeviceCreateBindGroup
    public func createBindGroup(
        descriptor: BindGroupDescriptor
    ) throws -> BindGroup {
        let handle = try withCBindGroupDescriptor(descriptor) { cDescriptor in
            guard let handle = wgpuDeviceCreateBindGroup(self.handle, cDescriptor) else {
                throw WebGPUError.createBindGroupFailed
            }
            return handle
        }
        return BindGroup(handle: handle, device: self, descriptor: descriptor)
    }

    // wgpuDeviceCreateShaderModule
    public func createShaderModule(
        descriptor: ShaderModuleDescriptor
    ) throws -> ShaderModule {
        let handle = try withCChain(descriptor.nextInChain) { nextInChain in
            try withWGPUStringView(descriptor.label) { label in
                var cDescriptor = WGPUShaderModuleDescriptor()
                cDescriptor.nextInChain = nextInChain
                cDescriptor.label = label
                guard let handle = wgpuDeviceCreateShaderModule(self.handle, &cDescriptor) else {
                    throw WebGPUError.createShaderModuleFailed
                }
                return handle
            }
        }
        return ShaderModule(handle: handle, device: self)
    }

    // wgpuDeviceCreateBindGroupLayout
    public func createBindGroupLayout(
        descriptor: BindGroupLayoutDescriptor
    ) throws -> BindGroupLayout {
        let handle = try withCBindGroupLayoutDescriptor(descriptor) { cDescriptor in
            guard let handle = wgpuDeviceCreateBindGroupLayout(self.handle, cDescriptor) else {
                throw WebGPUError.createBindGroupLayoutFailed
            }
            return handle
        }
        return BindGroupLayout(handle: handle, device: self)
    }

    // wgpuDeviceCreatePipelineLayout
    public func createPipelineLayout(
        descriptor: PipelineLayoutDescriptor
    ) throws -> PipelineLayout {
        let handle = try withCPipelineLayoutDescriptor(descriptor) { cDescriptor in
            guard let handle = wgpuDeviceCreatePipelineLayout(self.handle, cDescriptor) else {
                throw WebGPUError.createPipelineLayoutFailed
            }
            return handle
        }
        return PipelineLayout(handle: handle, device: self, descriptor: descriptor)
    }

    // wgpuDeviceCreateRenderPipeline
    public func createRenderPipeline(
        descriptor: RenderPipelineDescriptor
    ) throws -> RenderPipeline {
        let handle = try withCRenderPipelineDescriptor(descriptor) { cDescriptor in
            guard let handle = wgpuDeviceCreateRenderPipeline(self.handle, cDescriptor) else {
                throw WebGPUError.createRenderPipelineFailed
            }
            return handle
        }
        return RenderPipeline(handle: handle, device: self, descriptor: descriptor)
    }

    // wgpuDeviceCreateCommandEncoder
    public func createCommandEncoder(
        descriptor: CommandEncoderDescriptor = CommandEncoderDescriptor()
    ) throws -> CommandEncoder {
        let handle = try withCChain(descriptor.nextInChain) { nextInChain in
            try withWGPUStringView(descriptor.label) { label in
                var cDescriptor = WGPUCommandEncoderDescriptor()
                cDescriptor.nextInChain = nextInChain
                cDescriptor.label = label
                guard let handle = wgpuDeviceCreateCommandEncoder(self.handle, &cDescriptor) else {
                    throw WebGPUError.createCommandEncoderFailed
                }
                return handle
            }
        }
        return CommandEncoder(handle: handle, device: self)
    }

    deinit {
        // wgpuDeviceRelease
        wgpuDeviceRelease(handle)
    }
}

public final class Buffer {
    let handle: WGPUBuffer
    private let device: Device

    init(handle: WGPUBuffer, device: Device) {
        self.handle = handle
        self.device = device
    }

    deinit {
        // wgpuBufferRelease
        wgpuBufferRelease(handle)
    }
}

// TODO: Implement WGPUSamplerDescriptor and wgpuDeviceCreateSampler.
public final class Sampler {
    let handle: WGPUSampler
    private let device: Device

    init(handle: WGPUSampler, device: Device) {
        self.handle = handle
        self.device = device
    }

    deinit {
        // wgpuSamplerRelease
        wgpuSamplerRelease(handle)
    }
}

public final class BindGroup {
    let handle: WGPUBindGroup
    private let device: Device
    private let descriptor: BindGroupDescriptor

    init(handle: WGPUBindGroup, device: Device, descriptor: BindGroupDescriptor) {
        self.handle = handle
        self.device = device
        self.descriptor = descriptor
    }

    deinit {
        // wgpuBindGroupRelease
        wgpuBindGroupRelease(handle)
    }
}

public final class ShaderModule {
    let handle: WGPUShaderModule
    private let device: Device

    init(handle: WGPUShaderModule, device: Device) {
        self.handle = handle
        self.device = device
    }

    deinit {
        // wgpuShaderModuleRelease
        wgpuShaderModuleRelease(handle)
    }
}

public final class BindGroupLayout {
    let handle: WGPUBindGroupLayout
    private let device: Device

    init(handle: WGPUBindGroupLayout, device: Device) {
        self.handle = handle
        self.device = device
    }

    deinit {
        // wgpuBindGroupLayoutRelease
        wgpuBindGroupLayoutRelease(handle)
    }
}

public final class PipelineLayout {
    let handle: WGPUPipelineLayout
    private let device: Device
    private let descriptor: PipelineLayoutDescriptor

    init(handle: WGPUPipelineLayout, device: Device, descriptor: PipelineLayoutDescriptor) {
        self.handle = handle
        self.device = device
        self.descriptor = descriptor
    }

    deinit {
        // wgpuPipelineLayoutRelease
        wgpuPipelineLayoutRelease(handle)
    }
}

public final class RenderPipeline {
    let handle: WGPURenderPipeline
    private let device: Device
    private let descriptor: RenderPipelineDescriptor

    init(handle: WGPURenderPipeline, device: Device, descriptor: RenderPipelineDescriptor) {
        self.handle = handle
        self.device = device
        self.descriptor = descriptor
    }

    deinit {
        // wgpuRenderPipelineRelease
        wgpuRenderPipelineRelease(handle)
    }
}

public final class Queue {
    let handle: WGPUQueue
    private let device: Device

    init(handle: WGPUQueue, device: Device) {
        self.handle = handle
        self.device = device
    }

    // wgpuQueueSubmit
    public func submit(_ commands: [CommandBuffer]) {
        let handles: [WGPUCommandBuffer?] = commands.map(\.handle)
        handles.withUnsafeBufferPointer {
            wgpuQueueSubmit(handle, $0.count, $0.baseAddress)
        }
    }

    deinit {
        // wgpuQueueRelease
        wgpuQueueRelease(handle)
    }
}

public final class CommandEncoder {
    let handle: WGPUCommandEncoder
    private let device: Device

    init(handle: WGPUCommandEncoder, device: Device) {
        self.handle = handle
        self.device = device
    }

    // wgpuCommandEncoderBeginRenderPass
    public func beginRenderPass(
        descriptor: RenderPassDescriptor
    ) throws -> RenderPassEncoder {
        let handle = try withCRenderPassDescriptor(descriptor) { cDescriptor in
            guard let handle = wgpuCommandEncoderBeginRenderPass(self.handle, cDescriptor) else {
                throw WebGPUError.beginRenderPassFailed
            }
            return handle
        }
        return RenderPassEncoder(handle: handle, commandEncoder: self)
    }

    // wgpuCommandEncoderFinish
    public func finish(
        descriptor: CommandBufferDescriptor = CommandBufferDescriptor()
    ) throws -> CommandBuffer {
        let handle = try withCChain(descriptor.nextInChain) { nextInChain in
            try withWGPUStringView(descriptor.label) { label in
                var cDescriptor = WGPUCommandBufferDescriptor()
                cDescriptor.nextInChain = nextInChain
                cDescriptor.label = label
                guard let handle = wgpuCommandEncoderFinish(self.handle, &cDescriptor) else {
                    throw WebGPUError.finishCommandEncoderFailed
                }
                return handle
            }
        }
        return CommandBuffer(handle: handle, commandEncoder: self)
    }

    deinit {
        // wgpuCommandEncoderRelease
        wgpuCommandEncoderRelease(handle)
    }
}

public final class RenderPassEncoder {
    let handle: WGPURenderPassEncoder
    private let commandEncoder: CommandEncoder

    init(handle: WGPURenderPassEncoder, commandEncoder: CommandEncoder) {
        self.handle = handle
        self.commandEncoder = commandEncoder
    }

    // wgpuRenderPassEncoderDraw
    public func draw(
        vertexCount: UInt32,
        instanceCount: UInt32,
        firstVertex: UInt32,
        firstInstance: UInt32
    ) {
        wgpuRenderPassEncoderDraw(
            handle,
            vertexCount,
            instanceCount,
            firstVertex,
            firstInstance
        )
    }

    // wgpuRenderPassEncoderEnd
    public func end() {
        wgpuRenderPassEncoderEnd(handle)
    }

    // wgpuRenderPassEncoderSetPipeline
    public func setPipeline(_ pipeline: RenderPipeline) {
        wgpuRenderPassEncoderSetPipeline(handle, pipeline.handle)
    }

    deinit {
        // wgpuRenderPassEncoderRelease
        wgpuRenderPassEncoderRelease(handle)
    }
}

public final class CommandBuffer {
    let handle: WGPUCommandBuffer
    private let commandEncoder: CommandEncoder

    init(handle: WGPUCommandBuffer, commandEncoder: CommandEncoder) {
        self.handle = handle
        self.commandEncoder = commandEncoder
    }

    deinit {
        // wgpuCommandBufferRelease
        wgpuCommandBufferRelease(handle)
    }
}

public final class Texture {
    let handle: WGPUTexture
    private let surface: Surface

    init(handle: WGPUTexture, surface: Surface) {
        self.handle = handle
        self.surface = surface
    }

    // wgpuTextureCreateView
    public func createView() throws -> TextureView {
        guard let handle = wgpuTextureCreateView(handle, nil) else {
            throw WebGPUError.createTextureViewFailed
        }
        return TextureView(handle: handle, texture: self)
    }

    deinit {
        // wgpuTextureRelease
        wgpuTextureRelease(handle)
    }
}

public final class TextureView {
    let handle: WGPUTextureView
    private let texture: Texture

    init(handle: WGPUTextureView, texture: Texture) {
        self.handle = handle
        self.texture = texture
    }

    deinit {
        // wgpuTextureViewRelease
        wgpuTextureViewRelease(handle)
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

    // wgpuSurfaceGetCapabilities
    public func getCapabilities(adapter: Adapter) throws -> SurfaceCapabilities {
        var cCapabilities = WGPUSurfaceCapabilities()
        let status = wgpuSurfaceGetCapabilities(
            handle,
            adapter.handle,
            &cCapabilities
        )
        guard status == WGPUStatus_Success else {
            throw WebGPUError.getSurfaceCapabilitiesFailed(
                status: UInt32(truncatingIfNeeded: status.rawValue)
            )
        }
        defer {
            // wgpuSurfaceCapabilitiesFreeMembers
            wgpuSurfaceCapabilitiesFreeMembers(cCapabilities)
        }

        let formats = UnsafeBufferPointer(
            start: cCapabilities.formats,
            count: cCapabilities.formatCount
        ).map {
            TextureFormat(rawValue: UInt32(truncatingIfNeeded: $0.rawValue))
        }
        let presentModes = UnsafeBufferPointer(
            start: cCapabilities.presentModes,
            count: cCapabilities.presentModeCount
        ).compactMap {
            PresentMode(rawValue: UInt32(truncatingIfNeeded: $0.rawValue))
        }
        let alphaModes = UnsafeBufferPointer(
            start: cCapabilities.alphaModes,
            count: cCapabilities.alphaModeCount
        ).compactMap {
            CompositeAlphaMode(rawValue: UInt32(truncatingIfNeeded: $0.rawValue))
        }

        return SurfaceCapabilities(
            usages: TextureUsage(rawValue: cCapabilities.usages),
            formats: formats,
            presentModes: presentModes,
            alphaModes: alphaModes
        )
    }

    // wgpuSurfaceConfigure
    public func configure(_ configuration: SurfaceConfiguration) throws {
        let viewFormats = try configuration.viewFormats.map { try $0.cValue }
        try withCChain(configuration.nextInChain) { nextInChain in
            try viewFormats.withUnsafeBufferPointer { viewFormats in
                var cConfiguration = WGPUSurfaceConfiguration()
                cConfiguration.nextInChain = nextInChain
                cConfiguration.device = configuration.device.handle
                cConfiguration.format = try configuration.format.cValue
                cConfiguration.usage = configuration.usage.rawValue
                cConfiguration.width = configuration.width
                cConfiguration.height = configuration.height
                cConfiguration.viewFormatCount = viewFormats.count
                cConfiguration.viewFormats = viewFormats.baseAddress
                cConfiguration.alphaMode = configuration.alphaMode.cValue
                cConfiguration.presentMode = configuration.presentMode.cValue
                wgpuSurfaceConfigure(handle, &cConfiguration)
            }
        }
    }

    // wgpuSurfaceGetCurrentTexture
    public func getCurrentTexture() throws -> Texture {
        var surfaceTexture = WGPUSurfaceTexture()
        wgpuSurfaceGetCurrentTexture(handle, &surfaceTexture)
        let status = SurfaceGetCurrentTextureStatus(
            rawValue: UInt32(truncatingIfNeeded: surfaceTexture.status.rawValue)
        )
        guard status == .successOptimal || status == .successSuboptimal,
              let handle = surfaceTexture.texture else {
            throw WebGPUError.getCurrentTextureFailed(
                status: UInt32(truncatingIfNeeded: surfaceTexture.status.rawValue)
            )
        }
        return Texture(handle: handle, surface: self)
    }

    // wgpuSurfacePresent
    public func present() throws {
        let status = wgpuSurfacePresent(handle)
        guard status == WGPUStatus_Success else {
            throw WebGPUError.presentFailed(
                status: UInt32(truncatingIfNeeded: status.rawValue)
            )
        }
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
        case .shaderSourceSPIRV: WGPUSType_ShaderSourceSPIRV
        case .shaderSourceWGSL: WGPUSType_ShaderSourceWGSL
        case .surfaceSourceMetalLayer: WGPUSType_SurfaceSourceMetalLayer
        case .surfaceSourceWindowsHWND: WGPUSType_SurfaceSourceWindowsHWND
        case .surfaceSourceXlibWindow: WGPUSType_SurfaceSourceXlibWindow
        case .surfaceSourceWaylandSurface: WGPUSType_SurfaceSourceWaylandSurface
        case .dawnShaderModuleSPIRVOptionsDescriptor:
            WGPUSType_DawnShaderModuleSPIRVOptionsDescriptor
        case .shaderModuleCompilationOptions: WGPUSType_ShaderModuleCompilationOptions
        case .colorTargetStateExpandResolveTextureDawn:
            WGPUSType_ColorTargetStateExpandResolveTextureDawn
        case .dawnShaderSourceSPIRV: WGPUSType_DawnShaderSourceSPIRV
        }
    }
}

private extension BlendFactor {
    var cValue: WGPUBlendFactor {
        switch self {
        case .undefined: WGPUBlendFactor_Undefined
        case .zero: WGPUBlendFactor_Zero
        case .one: WGPUBlendFactor_One
        case .src: WGPUBlendFactor_Src
        case .oneMinusSrc: WGPUBlendFactor_OneMinusSrc
        case .srcAlpha: WGPUBlendFactor_SrcAlpha
        case .oneMinusSrcAlpha: WGPUBlendFactor_OneMinusSrcAlpha
        case .dst: WGPUBlendFactor_Dst
        case .oneMinusDst: WGPUBlendFactor_OneMinusDst
        case .dstAlpha: WGPUBlendFactor_DstAlpha
        case .oneMinusDstAlpha: WGPUBlendFactor_OneMinusDstAlpha
        case .srcAlphaSaturated: WGPUBlendFactor_SrcAlphaSaturated
        case .constant: WGPUBlendFactor_Constant
        case .oneMinusConstant: WGPUBlendFactor_OneMinusConstant
        case .src1: WGPUBlendFactor_Src1
        case .oneMinusSrc1: WGPUBlendFactor_OneMinusSrc1
        case .src1Alpha: WGPUBlendFactor_Src1Alpha
        case .oneMinusSrc1Alpha: WGPUBlendFactor_OneMinusSrc1Alpha
        }
    }
}

private extension BlendOperation {
    var cValue: WGPUBlendOperation {
        switch self {
        case .undefined: WGPUBlendOperation_Undefined
        case .add: WGPUBlendOperation_Add
        case .subtract: WGPUBlendOperation_Subtract
        case .reverseSubtract: WGPUBlendOperation_ReverseSubtract
        case .min: WGPUBlendOperation_Min
        case .max: WGPUBlendOperation_Max
        }
    }
}

private extension VertexStepMode {
    var cValue: WGPUVertexStepMode {
        switch self {
        case .undefined: WGPUVertexStepMode_Undefined
        case .vertex: WGPUVertexStepMode_Vertex
        case .instance: WGPUVertexStepMode_Instance
        }
    }
}

private extension VertexFormat {
    var cValue: WGPUVertexFormat {
        switch self {
        case .uint8: WGPUVertexFormat_Uint8
        case .uint8x2: WGPUVertexFormat_Uint8x2
        case .uint8x4: WGPUVertexFormat_Uint8x4
        case .sint8: WGPUVertexFormat_Sint8
        case .sint8x2: WGPUVertexFormat_Sint8x2
        case .sint8x4: WGPUVertexFormat_Sint8x4
        case .unorm8: WGPUVertexFormat_Unorm8
        case .unorm8x2: WGPUVertexFormat_Unorm8x2
        case .unorm8x4: WGPUVertexFormat_Unorm8x4
        case .snorm8: WGPUVertexFormat_Snorm8
        case .snorm8x2: WGPUVertexFormat_Snorm8x2
        case .snorm8x4: WGPUVertexFormat_Snorm8x4
        case .uint16: WGPUVertexFormat_Uint16
        case .uint16x2: WGPUVertexFormat_Uint16x2
        case .uint16x4: WGPUVertexFormat_Uint16x4
        case .sint16: WGPUVertexFormat_Sint16
        case .sint16x2: WGPUVertexFormat_Sint16x2
        case .sint16x4: WGPUVertexFormat_Sint16x4
        case .unorm16: WGPUVertexFormat_Unorm16
        case .unorm16x2: WGPUVertexFormat_Unorm16x2
        case .unorm16x4: WGPUVertexFormat_Unorm16x4
        case .snorm16: WGPUVertexFormat_Snorm16
        case .snorm16x2: WGPUVertexFormat_Snorm16x2
        case .snorm16x4: WGPUVertexFormat_Snorm16x4
        case .float16: WGPUVertexFormat_Float16
        case .float16x2: WGPUVertexFormat_Float16x2
        case .float16x4: WGPUVertexFormat_Float16x4
        case .float32: WGPUVertexFormat_Float32
        case .float32x2: WGPUVertexFormat_Float32x2
        case .float32x3: WGPUVertexFormat_Float32x3
        case .float32x4: WGPUVertexFormat_Float32x4
        case .uint32: WGPUVertexFormat_Uint32
        case .uint32x2: WGPUVertexFormat_Uint32x2
        case .uint32x3: WGPUVertexFormat_Uint32x3
        case .uint32x4: WGPUVertexFormat_Uint32x4
        case .sint32: WGPUVertexFormat_Sint32
        case .sint32x2: WGPUVertexFormat_Sint32x2
        case .sint32x3: WGPUVertexFormat_Sint32x3
        case .sint32x4: WGPUVertexFormat_Sint32x4
        case .unorm10_10_10_2: WGPUVertexFormat_Unorm10_10_10_2
        case .unorm8x4BGRA: WGPUVertexFormat_Unorm8x4BGRA
        case .snorm10_10_10_2: WGPUVertexFormat_Snorm10_10_10_2
        }
    }
}

private extension CompareFunction {
    var cValue: WGPUCompareFunction {
        switch self {
        case .undefined: WGPUCompareFunction_Undefined
        case .never: WGPUCompareFunction_Never
        case .less: WGPUCompareFunction_Less
        case .equal: WGPUCompareFunction_Equal
        case .lessEqual: WGPUCompareFunction_LessEqual
        case .greater: WGPUCompareFunction_Greater
        case .notEqual: WGPUCompareFunction_NotEqual
        case .greaterEqual: WGPUCompareFunction_GreaterEqual
        case .always: WGPUCompareFunction_Always
        }
    }
}

private extension CullMode {
    var cValue: WGPUCullMode {
        switch self {
        case .undefined: WGPUCullMode_Undefined
        case .none: WGPUCullMode_None
        case .front: WGPUCullMode_Front
        case .back: WGPUCullMode_Back
        }
    }
}

private extension FrontFace {
    var cValue: WGPUFrontFace {
        switch self {
        case .undefined: WGPUFrontFace_Undefined
        case .ccw: WGPUFrontFace_CCW
        case .cw: WGPUFrontFace_CW
        }
    }
}

private extension IndexFormat {
    var cValue: WGPUIndexFormat {
        switch self {
        case .undefined: WGPUIndexFormat_Undefined
        case .uint16: WGPUIndexFormat_Uint16
        case .uint32: WGPUIndexFormat_Uint32
        }
    }
}

private extension PrimitiveTopology {
    var cValue: WGPUPrimitiveTopology {
        switch self {
        case .undefined: WGPUPrimitiveTopology_Undefined
        case .pointList: WGPUPrimitiveTopology_PointList
        case .lineList: WGPUPrimitiveTopology_LineList
        case .lineStrip: WGPUPrimitiveTopology_LineStrip
        case .triangleList: WGPUPrimitiveTopology_TriangleList
        case .triangleStrip: WGPUPrimitiveTopology_TriangleStrip
        }
    }
}

private extension StencilOperation {
    var cValue: WGPUStencilOperation {
        switch self {
        case .undefined: WGPUStencilOperation_Undefined
        case .keep: WGPUStencilOperation_Keep
        case .zero: WGPUStencilOperation_Zero
        case .replace: WGPUStencilOperation_Replace
        case .invert: WGPUStencilOperation_Invert
        case .incrementClamp: WGPUStencilOperation_IncrementClamp
        case .decrementClamp: WGPUStencilOperation_DecrementClamp
        case .incrementWrap: WGPUStencilOperation_IncrementWrap
        case .decrementWrap: WGPUStencilOperation_DecrementWrap
        }
    }
}

private extension TextureFormat {
    var cValue: WGPUTextureFormat {
        get throws {
            switch self {
            case .undefined: WGPUTextureFormat_Undefined
            case .r8Unorm: WGPUTextureFormat_R8Unorm
            case .r8Snorm: WGPUTextureFormat_R8Snorm
            case .r8Uint: WGPUTextureFormat_R8Uint
            case .r8Sint: WGPUTextureFormat_R8Sint
            case .r16Unorm: WGPUTextureFormat_R16Unorm
            case .r16Snorm: WGPUTextureFormat_R16Snorm
            case .r16Uint: WGPUTextureFormat_R16Uint
            case .r16Sint: WGPUTextureFormat_R16Sint
            case .r16Float: WGPUTextureFormat_R16Float
            case .rg8Unorm: WGPUTextureFormat_RG8Unorm
            case .rg8Snorm: WGPUTextureFormat_RG8Snorm
            case .rg8Uint: WGPUTextureFormat_RG8Uint
            case .rg8Sint: WGPUTextureFormat_RG8Sint
            case .r32Float: WGPUTextureFormat_R32Float
            case .r32Uint: WGPUTextureFormat_R32Uint
            case .r32Sint: WGPUTextureFormat_R32Sint
            case .rg16Unorm: WGPUTextureFormat_RG16Unorm
            case .rg16Snorm: WGPUTextureFormat_RG16Snorm
            case .rg16Uint: WGPUTextureFormat_RG16Uint
            case .rg16Sint: WGPUTextureFormat_RG16Sint
            case .rg16Float: WGPUTextureFormat_RG16Float
            case .rgba8Unorm: WGPUTextureFormat_RGBA8Unorm
            case .rgba8UnormSrgb: WGPUTextureFormat_RGBA8UnormSrgb
            case .rgba8Snorm: WGPUTextureFormat_RGBA8Snorm
            case .rgba8Uint: WGPUTextureFormat_RGBA8Uint
            case .rgba8Sint: WGPUTextureFormat_RGBA8Sint
            case .bgra8Unorm: WGPUTextureFormat_BGRA8Unorm
            case .bgra8UnormSrgb: WGPUTextureFormat_BGRA8UnormSrgb
            case .rgb10A2Uint: WGPUTextureFormat_RGB10A2Uint
            case .rgb10A2Unorm: WGPUTextureFormat_RGB10A2Unorm
            case .rg11B10Ufloat: WGPUTextureFormat_RG11B10Ufloat
            case .rgb9E5Ufloat: WGPUTextureFormat_RGB9E5Ufloat
            case .rg32Float: WGPUTextureFormat_RG32Float
            case .rg32Uint: WGPUTextureFormat_RG32Uint
            case .rg32Sint: WGPUTextureFormat_RG32Sint
            case .rgba16Unorm: WGPUTextureFormat_RGBA16Unorm
            case .rgba16Snorm: WGPUTextureFormat_RGBA16Snorm
            case .rgba16Uint: WGPUTextureFormat_RGBA16Uint
            case .rgba16Sint: WGPUTextureFormat_RGBA16Sint
            case .rgba16Float: WGPUTextureFormat_RGBA16Float
            case .rgba32Float: WGPUTextureFormat_RGBA32Float
            case .rgba32Uint: WGPUTextureFormat_RGBA32Uint
            case .rgba32Sint: WGPUTextureFormat_RGBA32Sint
            case .stencil8: WGPUTextureFormat_Stencil8
            case .depth16Unorm: WGPUTextureFormat_Depth16Unorm
            case .depth24Plus: WGPUTextureFormat_Depth24Plus
            case .depth24PlusStencil8: WGPUTextureFormat_Depth24PlusStencil8
            case .depth32Float: WGPUTextureFormat_Depth32Float
            case .depth32FloatStencil8: WGPUTextureFormat_Depth32FloatStencil8
            case .bc1RGBAUnorm: WGPUTextureFormat_BC1RGBAUnorm
            case .bc1RGBAUnormSrgb: WGPUTextureFormat_BC1RGBAUnormSrgb
            case .bc2RGBAUnorm: WGPUTextureFormat_BC2RGBAUnorm
            case .bc2RGBAUnormSrgb: WGPUTextureFormat_BC2RGBAUnormSrgb
            case .bc3RGBAUnorm: WGPUTextureFormat_BC3RGBAUnorm
            case .bc3RGBAUnormSrgb: WGPUTextureFormat_BC3RGBAUnormSrgb
            case .bc4RUnorm: WGPUTextureFormat_BC4RUnorm
            case .bc4RSnorm: WGPUTextureFormat_BC4RSnorm
            case .bc5RGUnorm: WGPUTextureFormat_BC5RGUnorm
            case .bc5RGSnorm: WGPUTextureFormat_BC5RGSnorm
            case .bc6HRGBUfloat: WGPUTextureFormat_BC6HRGBUfloat
            case .bc6HRGBFloat: WGPUTextureFormat_BC6HRGBFloat
            case .bc7RGBAUnorm: WGPUTextureFormat_BC7RGBAUnorm
            case .bc7RGBAUnormSrgb: WGPUTextureFormat_BC7RGBAUnormSrgb
            case .etc2RGB8Unorm: WGPUTextureFormat_ETC2RGB8Unorm
            case .etc2RGB8UnormSrgb: WGPUTextureFormat_ETC2RGB8UnormSrgb
            case .etc2RGB8A1Unorm: WGPUTextureFormat_ETC2RGB8A1Unorm
            case .etc2RGB8A1UnormSrgb: WGPUTextureFormat_ETC2RGB8A1UnormSrgb
            case .etc2RGBA8Unorm: WGPUTextureFormat_ETC2RGBA8Unorm
            case .etc2RGBA8UnormSrgb: WGPUTextureFormat_ETC2RGBA8UnormSrgb
            case .eacR11Unorm: WGPUTextureFormat_EACR11Unorm
            case .eacR11Snorm: WGPUTextureFormat_EACR11Snorm
            case .eacRG11Unorm: WGPUTextureFormat_EACRG11Unorm
            case .eacRG11Snorm: WGPUTextureFormat_EACRG11Snorm
            case .astc4x4Unorm: WGPUTextureFormat_ASTC4x4Unorm
            case .astc4x4UnormSrgb: WGPUTextureFormat_ASTC4x4UnormSrgb
            case .astc5x4Unorm: WGPUTextureFormat_ASTC5x4Unorm
            case .astc5x4UnormSrgb: WGPUTextureFormat_ASTC5x4UnormSrgb
            case .astc5x5Unorm: WGPUTextureFormat_ASTC5x5Unorm
            case .astc5x5UnormSrgb: WGPUTextureFormat_ASTC5x5UnormSrgb
            case .astc6x5Unorm: WGPUTextureFormat_ASTC6x5Unorm
            case .astc6x5UnormSrgb: WGPUTextureFormat_ASTC6x5UnormSrgb
            case .astc6x6Unorm: WGPUTextureFormat_ASTC6x6Unorm
            case .astc6x6UnormSrgb: WGPUTextureFormat_ASTC6x6UnormSrgb
            case .astc8x5Unorm: WGPUTextureFormat_ASTC8x5Unorm
            case .astc8x5UnormSrgb: WGPUTextureFormat_ASTC8x5UnormSrgb
            case .astc8x6Unorm: WGPUTextureFormat_ASTC8x6Unorm
            case .astc8x6UnormSrgb: WGPUTextureFormat_ASTC8x6UnormSrgb
            case .astc8x8Unorm: WGPUTextureFormat_ASTC8x8Unorm
            case .astc8x8UnormSrgb: WGPUTextureFormat_ASTC8x8UnormSrgb
            case .astc10x5Unorm: WGPUTextureFormat_ASTC10x5Unorm
            case .astc10x5UnormSrgb: WGPUTextureFormat_ASTC10x5UnormSrgb
            case .astc10x6Unorm: WGPUTextureFormat_ASTC10x6Unorm
            case .astc10x6UnormSrgb: WGPUTextureFormat_ASTC10x6UnormSrgb
            case .astc10x8Unorm: WGPUTextureFormat_ASTC10x8Unorm
            case .astc10x8UnormSrgb: WGPUTextureFormat_ASTC10x8UnormSrgb
            case .astc10x10Unorm: WGPUTextureFormat_ASTC10x10Unorm
            case .astc10x10UnormSrgb: WGPUTextureFormat_ASTC10x10UnormSrgb
            case .astc12x10Unorm: WGPUTextureFormat_ASTC12x10Unorm
            case .astc12x10UnormSrgb: WGPUTextureFormat_ASTC12x10UnormSrgb
            case .astc12x12Unorm: WGPUTextureFormat_ASTC12x12Unorm
            case .astc12x12UnormSrgb: WGPUTextureFormat_ASTC12x12UnormSrgb
            case .r8BG8Biplanar420Unorm: WGPUTextureFormat_R8BG8Biplanar420Unorm
            case .r10X6BG10X6Biplanar420Unorm: WGPUTextureFormat_R10X6BG10X6Biplanar420Unorm
            case .r8BG8A8Triplanar420Unorm: WGPUTextureFormat_R8BG8A8Triplanar420Unorm
            case .r8BG8Biplanar422Unorm: WGPUTextureFormat_R8BG8Biplanar422Unorm
            case .r8BG8Biplanar444Unorm: WGPUTextureFormat_R8BG8Biplanar444Unorm
            case .r10X6BG10X6Biplanar422Unorm: WGPUTextureFormat_R10X6BG10X6Biplanar422Unorm
            case .r10X6BG10X6Biplanar444Unorm: WGPUTextureFormat_R10X6BG10X6Biplanar444Unorm
            case .opaqueYCbCrAndroid: WGPUTextureFormat_OpaqueYCbCrAndroid
            default: throw WebGPUError.unsupportedTextureFormat(self)
            }
        }
    }
}

private extension BufferBindingType {
    var cValue: WGPUBufferBindingType {
        switch self {
        case .bindingNotUsed: WGPUBufferBindingType_BindingNotUsed
        case .undefined: WGPUBufferBindingType_Undefined
        case .uniform: WGPUBufferBindingType_Uniform
        case .storage: WGPUBufferBindingType_Storage
        case .readOnlyStorage: WGPUBufferBindingType_ReadOnlyStorage
        }
    }
}

private extension SamplerBindingType {
    var cValue: WGPUSamplerBindingType {
        switch self {
        case .bindingNotUsed: WGPUSamplerBindingType_BindingNotUsed
        case .undefined: WGPUSamplerBindingType_Undefined
        case .filtering: WGPUSamplerBindingType_Filtering
        case .nonFiltering: WGPUSamplerBindingType_NonFiltering
        case .comparison: WGPUSamplerBindingType_Comparison
        }
    }
}

private extension StorageTextureAccess {
    var cValue: WGPUStorageTextureAccess {
        switch self {
        case .bindingNotUsed: WGPUStorageTextureAccess_BindingNotUsed
        case .undefined: WGPUStorageTextureAccess_Undefined
        case .writeOnly: WGPUStorageTextureAccess_WriteOnly
        case .readOnly: WGPUStorageTextureAccess_ReadOnly
        case .readWrite: WGPUStorageTextureAccess_ReadWrite
        }
    }
}

private extension TextureSampleType {
    var cValue: WGPUTextureSampleType {
        switch self {
        case .bindingNotUsed: WGPUTextureSampleType_BindingNotUsed
        case .undefined: WGPUTextureSampleType_Undefined
        case .float: WGPUTextureSampleType_Float
        case .unfilterableFloat: WGPUTextureSampleType_UnfilterableFloat
        case .depth: WGPUTextureSampleType_Depth
        case .sint: WGPUTextureSampleType_Sint
        case .uint: WGPUTextureSampleType_Uint
        }
    }
}

private extension TextureViewDimension {
    var cValue: WGPUTextureViewDimension {
        switch self {
        case .undefined: WGPUTextureViewDimension_Undefined
        case .`1D`: WGPUTextureViewDimension_1D
        case .`2D`: WGPUTextureViewDimension_2D
        case .`2DArray`: WGPUTextureViewDimension_2DArray
        case .cube: WGPUTextureViewDimension_Cube
        case .cubeArray: WGPUTextureViewDimension_CubeArray
        case .`3D`: WGPUTextureViewDimension_3D
        }
    }
}

private extension PresentMode {
    var cValue: WGPUPresentMode {
        switch self {
        case .undefined: WGPUPresentMode_Undefined
        case .fifo: WGPUPresentMode_Fifo
        case .fifoRelaxed: WGPUPresentMode_FifoRelaxed
        case .immediate: WGPUPresentMode_Immediate
        case .mailbox: WGPUPresentMode_Mailbox
        }
    }
}

private extension CompositeAlphaMode {
    var cValue: WGPUCompositeAlphaMode {
        switch self {
        case .auto: WGPUCompositeAlphaMode_Auto
        case .opaque: WGPUCompositeAlphaMode_Opaque
        case .premultiplied: WGPUCompositeAlphaMode_Premultiplied
        case .unpremultiplied: WGPUCompositeAlphaMode_Unpremultiplied
        case .inherit: WGPUCompositeAlphaMode_Inherit
        }
    }
}

private extension LoadOp {
    var cValue: WGPULoadOp {
        switch self {
        case .undefined: WGPULoadOp_Undefined
        case .load: WGPULoadOp_Load
        case .clear: WGPULoadOp_Clear
        case .expandResolveTexture: WGPULoadOp_ExpandResolveTexture
        }
    }
}

private extension StoreOp {
    var cValue: WGPUStoreOp {
        switch self {
        case .undefined: WGPUStoreOp_Undefined
        case .store: WGPUStoreOp_Store
        case .discard: WGPUStoreOp_Discard
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
    case let state as ColorTargetStateExpandResolveTextureDawn:
        return try withCChain(state.chain.next) { next in
            var cState = WGPUColorTargetStateExpandResolveTextureDawn()
            cState.chain.next = next
            cState.chain.sType = state.chain.sType.cValue
            cState.enabled = state.enabled ? 1 : 0
            return try withUnsafeMutablePointer(to: &cState) { state in
                try body(
                    UnsafeMutableRawPointer(state)
                        .assumingMemoryBound(to: WGPUChainedStruct.self)
                )
            }
        }
    case let options as DawnShaderModuleSPIRVOptionsDescriptor:
        return try withCChain(options.chain.next) { next in
            var cOptions = WGPUDawnShaderModuleSPIRVOptionsDescriptor()
            cOptions.chain.next = next
            cOptions.chain.sType = options.chain.sType.cValue
            cOptions.allowNonUniformDerivatives = options.allowNonUniformDerivatives ? 1 : 0
            return try withUnsafeMutablePointer(to: &cOptions) { options in
                try body(
                    UnsafeMutableRawPointer(options)
                        .assumingMemoryBound(to: WGPUChainedStruct.self)
                )
            }
        }
    case let source as DawnShaderSourceSPIRV:
        return try withCChain(source.chain.next) { next in
            try source.code.withUnsafeBufferPointer { code in
                var cSource = WGPUDawnShaderSourceSPIRV()
                cSource.chain.next = next
                cSource.chain.sType = source.chain.sType.cValue
                cSource.codeSize = code.count
                cSource.code = code.baseAddress
                return try withUnsafeMutablePointer(to: &cSource) { source in
                    try body(
                        UnsafeMutableRawPointer(source)
                            .assumingMemoryBound(to: WGPUChainedStruct.self)
                    )
                }
            }
        }
    case let options as ShaderModuleCompilationOptions:
        return try withCChain(options.chain.next) { next in
            var cOptions = WGPUShaderModuleCompilationOptions()
            cOptions.chain.next = next
            cOptions.chain.sType = options.chain.sType.cValue
            cOptions.strictMath = options.strictMath ? 1 : 0
            return try withUnsafeMutablePointer(to: &cOptions) { options in
                try body(
                    UnsafeMutableRawPointer(options)
                        .assumingMemoryBound(to: WGPUChainedStruct.self)
                )
            }
        }
    case let source as ShaderSourceSPIRV:
        guard let codeSize = UInt32(exactly: source.code.count) else {
            throw WebGPUError.shaderSourceSPIRVTooLarge
        }
        return try withCChain(source.chain.next) { next in
            try source.code.withUnsafeBufferPointer { code in
                var cSource = WGPUShaderSourceSPIRV()
                cSource.chain.next = next
                cSource.chain.sType = source.chain.sType.cValue
                cSource.codeSize = codeSize
                cSource.code = code.baseAddress
                return try withUnsafeMutablePointer(to: &cSource) { source in
                    try body(
                        UnsafeMutableRawPointer(source)
                            .assumingMemoryBound(to: WGPUChainedStruct.self)
                    )
                }
            }
        }
    case let source as ShaderSourceWGSL:
        return try withCChain(source.chain.next) { next in
            try withWGPUStringView(source.code) { code in
                var cSource = WGPUShaderSourceWGSL()
                cSource.chain.next = next
                cSource.chain.sType = source.chain.sType.cValue
                cSource.code = code
                return try withUnsafeMutablePointer(to: &cSource) { source in
                    try body(
                        UnsafeMutableRawPointer(source)
                            .assumingMemoryBound(to: WGPUChainedStruct.self)
                    )
                }
            }
        }
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

private func withCRenderPipelineDescriptor<Result>(
    _ descriptor: RenderPipelineDescriptor,
    body: (UnsafePointer<WGPURenderPipelineDescriptor>) throws -> Result
) throws -> Result {
    try withCChain(descriptor.nextInChain) { nextInChain in
        try withWGPUStringView(descriptor.label) { label in
            try withCVertexState(descriptor.vertex) { vertex in
                try withCPrimitiveState(descriptor.primitive) { primitive in
                    try withCDepthStencilState(descriptor.depthStencil) { depthStencil in
                        try withCMultisampleState(descriptor.multisample) { multisample in
                            try withOptionalCFragmentState(descriptor.fragment) { fragment in
                                var cDescriptor = WGPURenderPipelineDescriptor()
                                cDescriptor.nextInChain = nextInChain
                                cDescriptor.label = label
                                cDescriptor.layout = descriptor.layout?.handle
                                cDescriptor.vertex = vertex
                                cDescriptor.primitive = primitive
                                cDescriptor.depthStencil = depthStencil
                                cDescriptor.multisample = multisample
                                cDescriptor.fragment = fragment
                                return try withUnsafePointer(to: &cDescriptor, body)
                            }
                        }
                    }
                }
            }
        }
    }
}

private func withCPrimitiveState<Result>(
    _ state: PrimitiveState,
    body: (WGPUPrimitiveState) throws -> Result
) throws -> Result {
    try withCChain(state.nextInChain) { nextInChain in
        var cState = WGPUPrimitiveState()
        cState.nextInChain = nextInChain
        cState.topology = state.topology.cValue
        cState.stripIndexFormat = state.stripIndexFormat.cValue
        cState.frontFace = state.frontFace.cValue
        cState.cullMode = state.cullMode.cValue
        cState.unclippedDepth = state.unclippedDepth ? 1 : 0
        return try body(cState)
    }
}

private func withCDepthStencilState<Result>(
    _ state: DepthStencilState?,
    body: (UnsafePointer<WGPUDepthStencilState>?) throws -> Result
) throws -> Result {
    guard let state else {
        return try body(nil)
    }

    return try withCChain(state.nextInChain) { nextInChain in
        var cState = WGPUDepthStencilState()
        cState.nextInChain = nextInChain
        cState.format = try state.format.cValue
        cState.depthWriteEnabled = state.depthWriteEnabled.cValue
        cState.depthCompare = state.depthCompare.cValue
        cState.stencilFront = state.stencilFront.cValue
        cState.stencilBack = state.stencilBack.cValue
        cState.stencilReadMask = state.stencilReadMask
        cState.stencilWriteMask = state.stencilWriteMask
        cState.depthBias = state.depthBias
        cState.depthBiasSlopeScale = state.depthBiasSlopeScale
        cState.depthBiasClamp = state.depthBiasClamp
        return try withUnsafePointer(to: &cState, body)
    }
}

private func withCMultisampleState<Result>(
    _ state: MultisampleState,
    body: (WGPUMultisampleState) throws -> Result
) throws -> Result {
    try withCChain(state.nextInChain) { nextInChain in
        var cState = WGPUMultisampleState()
        cState.nextInChain = nextInChain
        cState.count = state.count
        cState.mask = state.mask
        cState.alphaToCoverageEnabled = state.alphaToCoverageEnabled ? 1 : 0
        return try body(cState)
    }
}

private func withOptionalCFragmentState<Result>(
    _ state: FragmentState?,
    body: (UnsafePointer<WGPUFragmentState>?) throws -> Result
) throws -> Result {
    guard let state else {
        return try body(nil)
    }

    return try withCFragmentState(state) { state in
        var state = state
        return try withUnsafePointer(to: &state, body)
    }
}

private func withCVertexState<Result>(
    _ state: VertexState,
    body: (WGPUVertexState) throws -> Result
) throws -> Result {
    try withCChain(state.nextInChain) { nextInChain in
        try withWGPUStringView(state.entryPoint) { entryPoint in
            try withCConstantEntries(state.constants, index: 0, converted: []) { constants in
                try withCVertexBufferLayouts(state.buffers, index: 0, converted: []) { buffers in
                    try constants.withUnsafeBufferPointer { constants in
                        try buffers.withUnsafeBufferPointer { buffers in
                            var cState = WGPUVertexState()
                            cState.nextInChain = nextInChain
                            cState.module = state.module.handle
                            cState.entryPoint = entryPoint
                            cState.constantCount = constants.count
                            cState.constants = constants.baseAddress
                            cState.bufferCount = buffers.count
                            cState.buffers = buffers.baseAddress
                            return try body(cState)
                        }
                    }
                }
            }
        }
    }
}

private func withCFragmentState<Result>(
    _ state: FragmentState,
    body: (WGPUFragmentState) throws -> Result
) throws -> Result {
    try withCChain(state.nextInChain) { nextInChain in
        try withWGPUStringView(state.entryPoint) { entryPoint in
            try withCConstantEntries(state.constants, index: 0, converted: []) { constants in
                try withCColorTargetStates(state.targets, index: 0, converted: []) { targets in
                    try constants.withUnsafeBufferPointer { constants in
                        try targets.withUnsafeBufferPointer { targets in
                            var cState = WGPUFragmentState()
                            cState.nextInChain = nextInChain
                            cState.module = state.module.handle
                            cState.entryPoint = entryPoint
                            cState.constantCount = constants.count
                            cState.constants = constants.baseAddress
                            cState.targetCount = targets.count
                            cState.targets = targets.baseAddress
                            return try body(cState)
                        }
                    }
                }
            }
        }
    }
}

private func withCConstantEntries<Result>(
    _ entries: [ConstantEntry],
    index: Int,
    converted: [WGPUConstantEntry],
    body: ([WGPUConstantEntry]) throws -> Result
) throws -> Result {
    guard index < entries.count else {
        return try body(converted)
    }

    let entry = entries[index]
    return try withCChain(entry.nextInChain) { nextInChain in
        try withWGPUStringView(entry.key) { key in
            var cEntry = WGPUConstantEntry()
            cEntry.nextInChain = nextInChain
            cEntry.key = key
            cEntry.value = entry.value
            var converted = converted
            converted.append(cEntry)
            return try withCConstantEntries(
                entries,
                index: index + 1,
                converted: converted,
                body: body
            )
        }
    }
}

private func withCVertexAttributes<Result>(
    _ attributes: [VertexAttribute],
    index: Int,
    converted: [WGPUVertexAttribute],
    body: ([WGPUVertexAttribute]) throws -> Result
) throws -> Result {
    guard index < attributes.count else {
        return try body(converted)
    }

    let attribute = attributes[index]
    return try withCChain(attribute.nextInChain) { nextInChain in
        var cAttribute = WGPUVertexAttribute()
        cAttribute.nextInChain = nextInChain
        cAttribute.format = attribute.format.cValue
        cAttribute.offset = attribute.offset
        cAttribute.shaderLocation = attribute.shaderLocation
        var converted = converted
        converted.append(cAttribute)
        return try withCVertexAttributes(
            attributes,
            index: index + 1,
            converted: converted,
            body: body
        )
    }
}

private func withCVertexBufferLayouts<Result>(
    _ layouts: [VertexBufferLayout],
    index: Int,
    converted: [WGPUVertexBufferLayout],
    body: ([WGPUVertexBufferLayout]) throws -> Result
) throws -> Result {
    guard index < layouts.count else {
        return try body(converted)
    }

    let layout = layouts[index]
    return try withCChain(layout.nextInChain) { nextInChain in
        try withCVertexAttributes(layout.attributes, index: 0, converted: []) { attributes in
            try attributes.withUnsafeBufferPointer { attributes in
                var cLayout = WGPUVertexBufferLayout()
                cLayout.nextInChain = nextInChain
                cLayout.stepMode = layout.stepMode.cValue
                cLayout.arrayStride = layout.arrayStride
                cLayout.attributeCount = attributes.count
                cLayout.attributes = attributes.baseAddress
                var converted = converted
                converted.append(cLayout)
                return try withCVertexBufferLayouts(
                    layouts,
                    index: index + 1,
                    converted: converted,
                    body: body
                )
            }
        }
    }
}

private func withCColorTargetStates<Result>(
    _ targets: [ColorTargetState],
    index: Int,
    converted: [WGPUColorTargetState],
    body: ([WGPUColorTargetState]) throws -> Result
) throws -> Result {
    guard index < targets.count else {
        return try body(converted)
    }

    let target = targets[index]
    return try withCChain(target.nextInChain) { nextInChain in
        var cTarget = WGPUColorTargetState()
        cTarget.nextInChain = nextInChain
        cTarget.format = try target.format.cValue
        cTarget.writeMask = target.writeMask.rawValue

        guard let blend = target.blend else {
            var converted = converted
            converted.append(cTarget)
            return try withCColorTargetStates(
                targets,
                index: index + 1,
                converted: converted,
                body: body
            )
        }

        var cBlend = WGPUBlendState(
            color: blend.color.cValue,
            alpha: blend.alpha.cValue
        )
        return try withUnsafePointer(to: &cBlend) { blend in
            cTarget.blend = blend
            var converted = converted
            converted.append(cTarget)
            return try withCColorTargetStates(
                targets,
                index: index + 1,
                converted: converted,
                body: body
            )
        }
    }
}

private extension BlendComponent {
    var cValue: WGPUBlendComponent {
        WGPUBlendComponent(
            operation: operation.cValue,
            srcFactor: srcFactor.cValue,
            dstFactor: dstFactor.cValue
        )
    }
}

private extension Optional where Wrapped == Bool {
    var cValue: WGPUOptionalBool {
        switch self {
        case nil: WGPUOptionalBool_Undefined
        case true: WGPUOptionalBool_True
        case false: WGPUOptionalBool_False
        }
    }
}

private extension StencilFaceState {
    var cValue: WGPUStencilFaceState {
        WGPUStencilFaceState(
            compare: compare.cValue,
            failOp: failOp.cValue,
            depthFailOp: depthFailOp.cValue,
            passOp: passOp.cValue
        )
    }
}

private func withCPipelineLayoutDescriptor<Result>(
    _ descriptor: PipelineLayoutDescriptor,
    body: (UnsafePointer<WGPUPipelineLayoutDescriptor>) throws -> Result
) throws -> Result {
    try withCChain(descriptor.nextInChain) { nextInChain in
        try withWGPUStringView(descriptor.label) { label in
            let bindGroupLayouts: [WGPUBindGroupLayout?] =
                descriptor.bindGroupLayouts.map(\.handle)
            return try bindGroupLayouts.withUnsafeBufferPointer { bindGroupLayouts in
                var cDescriptor = WGPUPipelineLayoutDescriptor()
                cDescriptor.nextInChain = nextInChain
                cDescriptor.label = label
                cDescriptor.bindGroupLayoutCount = bindGroupLayouts.count
                cDescriptor.bindGroupLayouts = bindGroupLayouts.baseAddress
                cDescriptor.immediateSize = descriptor.immediateSize
                return try withUnsafePointer(to: &cDescriptor, body)
            }
        }
    }
}

private func withCBindGroupLayoutDescriptor<Result>(
    _ descriptor: BindGroupLayoutDescriptor,
    body: (UnsafePointer<WGPUBindGroupLayoutDescriptor>) throws -> Result
) throws -> Result {
    try withCChain(descriptor.nextInChain) { nextInChain in
        try withWGPUStringView(descriptor.label) { label in
            try withCBindGroupLayoutEntries(
                descriptor.entries,
                index: 0,
                converted: []
            ) { entries in
                try entries.withUnsafeBufferPointer { entries in
                    var cDescriptor = WGPUBindGroupLayoutDescriptor()
                    cDescriptor.nextInChain = nextInChain
                    cDescriptor.label = label
                    cDescriptor.entryCount = entries.count
                    cDescriptor.entries = entries.baseAddress
                    return try withUnsafePointer(to: &cDescriptor, body)
                }
            }
        }
    }
}

private func withCBindGroupDescriptor<Result>(
    _ descriptor: BindGroupDescriptor,
    body: (UnsafePointer<WGPUBindGroupDescriptor>) throws -> Result
) throws -> Result {
    try withCChain(descriptor.nextInChain) { nextInChain in
        try withWGPUStringView(descriptor.label) { label in
            try withCBindGroupEntries(
                descriptor.entries,
                index: 0,
                converted: []
            ) { entries in
                try entries.withUnsafeBufferPointer { entries in
                    var cDescriptor = WGPUBindGroupDescriptor()
                    cDescriptor.nextInChain = nextInChain
                    cDescriptor.label = label
                    cDescriptor.layout = descriptor.layout.handle
                    cDescriptor.entryCount = entries.count
                    cDescriptor.entries = entries.baseAddress
                    return try withUnsafePointer(to: &cDescriptor, body)
                }
            }
        }
    }
}

private func withCBindGroupEntries<Result>(
    _ entries: [BindGroupEntry],
    index: Int,
    converted: [WGPUBindGroupEntry],
    body: ([WGPUBindGroupEntry]) throws -> Result
) throws -> Result {
    guard index < entries.count else {
        return try body(converted)
    }

    let entry = entries[index]
    return try withCChain(entry.nextInChain) { nextInChain in
        var cEntry = WGPUBindGroupEntry()
        cEntry.nextInChain = nextInChain
        cEntry.binding = entry.binding
        cEntry.buffer = entry.buffer?.handle
        cEntry.offset = entry.offset
        cEntry.size = entry.size
        cEntry.sampler = entry.sampler?.handle
        cEntry.textureView = entry.textureView?.handle

        var converted = converted
        converted.append(cEntry)
        return try withCBindGroupEntries(
            entries,
            index: index + 1,
            converted: converted,
            body: body
        )
    }
}

private func withCBindGroupLayoutEntries<Result>(
    _ entries: [BindGroupLayoutEntry],
    index: Int,
    converted: [WGPUBindGroupLayoutEntry],
    body: ([WGPUBindGroupLayoutEntry]) throws -> Result
) throws -> Result {
    guard index < entries.count else {
        return try body(converted)
    }

    let entry = entries[index]
    return try withCChain(entry.nextInChain) { nextInChain in
        try withCChain(entry.buffer.nextInChain) { bufferNextInChain in
            try withCChain(entry.sampler.nextInChain) { samplerNextInChain in
                try withCChain(entry.texture.nextInChain) { textureNextInChain in
                    try withCChain(entry.storageTexture.nextInChain) { storageTextureNextInChain in
                        var cBuffer = WGPUBufferBindingLayout()
                        cBuffer.nextInChain = bufferNextInChain
                        cBuffer.type = entry.buffer.type.cValue
                        cBuffer.hasDynamicOffset = entry.buffer.hasDynamicOffset ? 1 : 0
                        cBuffer.minBindingSize = entry.buffer.minBindingSize

                        var cSampler = WGPUSamplerBindingLayout()
                        cSampler.nextInChain = samplerNextInChain
                        cSampler.type = entry.sampler.type.cValue

                        var cTexture = WGPUTextureBindingLayout()
                        cTexture.nextInChain = textureNextInChain
                        cTexture.sampleType = entry.texture.sampleType.cValue
                        cTexture.viewDimension = entry.texture.viewDimension.cValue
                        cTexture.multisampled = entry.texture.multisampled ? 1 : 0

                        var cStorageTexture = WGPUStorageTextureBindingLayout()
                        cStorageTexture.nextInChain = storageTextureNextInChain
                        cStorageTexture.access = entry.storageTexture.access.cValue
                        cStorageTexture.format = try entry.storageTexture.format.cValue
                        cStorageTexture.viewDimension = entry.storageTexture.viewDimension.cValue

                        var cEntry = WGPUBindGroupLayoutEntry()
                        cEntry.nextInChain = nextInChain
                        cEntry.binding = entry.binding
                        cEntry.visibility = entry.visibility.rawValue
                        cEntry.bindingArraySize = entry.bindingArraySize
                        cEntry.buffer = cBuffer
                        cEntry.sampler = cSampler
                        cEntry.texture = cTexture
                        cEntry.storageTexture = cStorageTexture

                        var converted = converted
                        converted.append(cEntry)
                        return try withCBindGroupLayoutEntries(
                            entries,
                            index: index + 1,
                            converted: converted,
                            body: body
                        )
                    }
                }
            }
        }
    }
}

private func withCRenderPassDescriptor<Result>(
    _ descriptor: RenderPassDescriptor,
    body: (UnsafePointer<WGPURenderPassDescriptor>) throws -> Result
) throws -> Result {
    try withCChain(descriptor.nextInChain) { nextInChain in
        try withWGPUStringView(descriptor.label) { label in
            try withCRenderPassColorAttachments(
                descriptor.colorAttachments,
                index: 0,
                converted: []
            ) { colorAttachments in
                try colorAttachments.withUnsafeBufferPointer { colorAttachments in
                    var cDescriptor = WGPURenderPassDescriptor()
                    cDescriptor.nextInChain = nextInChain
                    cDescriptor.label = label
                    cDescriptor.colorAttachmentCount = colorAttachments.count
                    cDescriptor.colorAttachments = colorAttachments.baseAddress
                    return try withUnsafePointer(to: &cDescriptor, body)
                }
            }
        }
    }
}

private func withCRenderPassColorAttachments<Result>(
    _ attachments: [RenderPassColorAttachment],
    index: Int,
    converted: [WGPURenderPassColorAttachment],
    body: ([WGPURenderPassColorAttachment]) throws -> Result
) throws -> Result {
    guard index < attachments.count else {
        return try body(converted)
    }

    let attachment = attachments[index]
    return try withCChain(attachment.nextInChain) { nextInChain in
        var converted = converted
        var cAttachment = WGPURenderPassColorAttachment()
        cAttachment.nextInChain = nextInChain
        cAttachment.view = attachment.view.handle
        cAttachment.depthSlice = WGPU_DEPTH_SLICE_UNDEFINED
        cAttachment.resolveTarget = attachment.resolveTarget?.handle
        cAttachment.loadOp = attachment.loadOp.cValue
        cAttachment.storeOp = attachment.storeOp.cValue
        cAttachment.clearValue = WGPUColor(
            r: attachment.clearValue.r,
            g: attachment.clearValue.g,
            b: attachment.clearValue.b,
            a: attachment.clearValue.a
        )
        converted.append(cAttachment)
        return try withCRenderPassColorAttachments(
            attachments,
            index: index + 1,
            converted: converted,
            body: body
        )
    }
}
