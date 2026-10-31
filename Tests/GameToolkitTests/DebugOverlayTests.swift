import Dawn
@testable import GameToolkit
import Testing

@Suite("describe")
struct DescribeTests {
    @Test
    func describesANativeAdapter() {
        let lines = describe(
            AdapterInfo(
                vendor: "apple", architecture: "metal-3", device: "Apple M1 Pro",
                description: "Metal driver on macOS", backendType: .metal, adapterType: .integratedGPU))
        #expect(lines == ["Apple M1 Pro", "Metal, integrated GPU", "apple metal-3", "Metal driver on macOS"])
    }

    @Test
    func leavesOutWhatABrowserDoesNotSay() {
        let lines = describe(
            AdapterInfo(vendor: "apple", architecture: "metal-3", backendType: .webGPU, adapterType: .unknown))
        #expect(lines == ["WebGPU", "apple metal-3"])
    }
}

@Suite("FPSCounter")
struct FPSCounterTests {
    @Test
    func describesTheMemoryUsed() throws {
        let text = try #require(FPSCounter.memoryDescription())
        print("MEMORY", text)
        #expect(text.hasPrefix("memory "))
        #expect(text.hasSuffix(" MB"))
    }
}
