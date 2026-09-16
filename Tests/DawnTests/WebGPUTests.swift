import Testing

@testable import Dawn

@Suite("WebGPU")
struct WebGPUTests {
    @Test
    func requestsNullAdapter() async throws {
        let instance = try createInstance()
        let adapter = try await instance.requestAdapter(
            options: RequestAdapterOptions(backendType: .null)
        )

        withExtendedLifetime((instance, adapter)) {}
    }
}
