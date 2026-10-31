import GameToolkit
import Testing

@Suite("Formatting")
struct FormattingTests {
    @Test
    func padsWithZeros() {
        #expect(formatZeroPadded(7, width: 2) == "07")
        #expect(formatZeroPadded(42, width: 2) == "42")
        #expect(formatZeroPadded(2026, width: 2) == "2026")
        #expect(formatZeroPadded(0, width: 3) == "000")
        #expect(formatZeroPadded(-5, width: 3) == "-005")
        #expect(formatZeroPadded(Int32.min, width: 1) == "-2147483648")
        #expect(formatZeroPadded(UInt8(9), width: 0) == "9")
    }
}
