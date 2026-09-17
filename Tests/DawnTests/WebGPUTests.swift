import Interop
import Testing

@testable import Dawn

@Suite("WebGPU")
struct WebGPUTests {
    @Test
    func surfaceDescriptorPreservesChain() throws {
        final class Owner {}

        let owner = Owner()
        let pointer = try #require(UnsafeMutableRawPointer(bitPattern: 1))
        let boundPointer = UnsafeLifetimeBoundRawPointer(
            pointer,
            boundTo: owner
        )
        let tail = SurfaceSourceXlibWindow(
            display: boundPointer,
            window: 42
        )
        let descriptor = SurfaceDescriptor(
            nextInChain: SurfaceSourceMetalLayer(
                nextInChain: tail,
                layer: boundPointer
            ),
            label: "surface"
        )

        let head = try #require(
            descriptor.nextInChain as? SurfaceSourceMetalLayer
        )
        let next = try #require(
            head.chain.next as? SurfaceSourceXlibWindow
        )
        #expect(head.chain.sType == .surfaceSourceMetalLayer)
        #expect(next.chain.sType == .surfaceSourceXlibWindow)
        #expect(next.window == 42)
        #expect(descriptor.label == "surface")
    }

    @Test
    func requestsNullAdapter() async throws {
        let instance = try createInstance()
        let adapter = try await instance.requestAdapter(
            options: RequestAdapterOptions(backendType: .null)
        )

        withExtendedLifetime((instance, adapter)) {}
    }

    @Test
    func requestsDeviceFromNullAdapter() async throws {
        let instance = try createInstance()
        let adapter = try await instance.requestAdapter(
            options: RequestAdapterOptions(backendType: .null)
        )
        let device = try await adapter.requestDevice()
        let configuration = SurfaceConfiguration(
            device: device,
            format: .bgra8Unorm,
            width: 1280,
            height: 720
        )

        #expect(configuration.usage == .renderAttachment)
        #expect(configuration.presentMode == .fifo)
        withExtendedLifetime((instance, adapter, device)) {}
    }
}
