import CSDL3

// SDL_DateTime
public struct DateTime: Equatable, Sendable {
    public var year: Int32
    public var month: Int32
    public var day: Int32
    public var hour: Int32
    public var minute: Int32
    public var second: Int32
    public var nanosecond: Int32
    public var dayOfWeek: Int32
    public var utcOffset: Int32
}

// SDL_GetCurrentTime: nanoseconds since the Unix epoch.
public func getCurrentTime() throws -> Int64 {
    var ticks: SDL_Time = 0
    guard SDL_GetCurrentTime(&ticks) else {
        throw SDLError(operation: "SDL_GetCurrentTime")
    }
    return ticks
}

// SDL_TimeToDateTime
public func timeToDateTime(ticks: Int64, localTime: Bool) throws -> DateTime {
    var dateTime = SDL_DateTime()
    guard SDL_TimeToDateTime(ticks, &dateTime, localTime) else {
        throw SDLError(operation: "SDL_TimeToDateTime")
    }
    return DateTime(
        year: dateTime.year, month: dateTime.month, day: dateTime.day, hour: dateTime.hour,
        minute: dateTime.minute, second: dateTime.second, nanosecond: dateTime.nanosecond,
        dayOfWeek: dateTime.day_of_week, utcOffset: dateTime.utc_offset)
}
