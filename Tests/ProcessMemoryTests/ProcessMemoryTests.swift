import ProcessMemory
import Testing

@Suite("ProcessMemory")
struct ProcessMemoryTests {
    @Test
    func countsTheProcess() throws {
        let current = try #require(currentMemory())
        let peak = try #require(peakMemory())
        // More than a megabyte, less than a terabyte.
        #expect(current > 1 << 20 && current < 1 << 40)
        #expect(peak >= current)
    }

    @Test
    func growsWithWhatIsTouched() throws {
        let before = try #require(currentMemory())
        // 64 MB, written so that it is in RAM.
        let count = 64 << 20
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        defer { bytes.deallocate() }
        for index in stride(from: 0, to: count, by: 4096) {
            bytes[index] = UInt8(truncatingIfNeeded: index)
        }
        let after = try #require(currentMemory())
        #expect(after > before + (32 << 20))
        #expect(try #require(peakMemory()) >= after)
    }
}
