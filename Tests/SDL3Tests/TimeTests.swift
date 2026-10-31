import Testing

@testable import SDL3

@Suite("Time")
struct TimeTests {
    @Test
    func convertsTimesToDates() throws {
        // 2001-09-09 01:46:40 UTC, a Sunday.
        let date = try timeToDateTime(ticks: 1_000_000_000 * 1_000_000_000, localTime: false)
        #expect(date == DateTime(
            year: 2001, month: 9, day: 9, hour: 1, minute: 46, second: 40, nanosecond: 0, dayOfWeek: 0,
            utcOffset: 0))
        #expect(try getCurrentTime() > 1_000_000_000 * 1_000_000_000)
    }
}
