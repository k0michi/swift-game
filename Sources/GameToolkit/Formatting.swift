/// `value` with one decimal place, rounded down.
public func formatTenths(_ value: Float) -> String {
    let tenths = Int(value * 10)
    return "\(tenths / 10).\(tenths % 10)"
}

/// `value` in decimal, with zeros in front to make at least `width` digits.
public func formatZeroPadded(_ value: some BinaryInteger, width: Int) -> String {
    let digits = String(value.magnitude)
    let padding = String(repeating: "0", count: max(0, width - digits.count))
    return (value < 0 ? "-" : "") + padding + digits
}
