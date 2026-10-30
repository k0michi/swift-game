/// `value` with one decimal place, rounded down.
public func formatTenths(_ value: Float) -> String {
    let tenths = Int(value * 10)
    return "\(tenths / 10).\(tenths % 10)"
}
