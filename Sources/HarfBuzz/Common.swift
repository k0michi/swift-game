import CHarfBuzz

// hb_direction_t
public enum Direction: UInt32, Sendable {
    case invalid = 0
    case ltr = 4
    case rtl = 5
    case ttb = 6
    case btt = 7
}

// hb_script_t, an ISO 15924 tag.
public struct Script: RawRepresentable, Equatable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    // C enums are Int32 on Windows and UInt32 elsewhere.
    init(_ script: hb_script_t) {
        rawValue = UInt32(truncatingIfNeeded: script.rawValue)
    }

    // HB_SCRIPT_INVALID
    public static let invalid = Script(HB_SCRIPT_INVALID)
    // HB_SCRIPT_COMMON
    public static let common = Script(HB_SCRIPT_COMMON)
    // HB_SCRIPT_LATIN
    public static let latin = Script(HB_SCRIPT_LATIN)
    // HB_SCRIPT_HIRAGANA
    public static let hiragana = Script(HB_SCRIPT_HIRAGANA)
    // HB_SCRIPT_KATAKANA
    public static let katakana = Script(HB_SCRIPT_KATAKANA)
    // HB_SCRIPT_HAN
    public static let han = Script(HB_SCRIPT_HAN)
}

// hb_script_from_string
public func scriptFromString(str: String) -> Script {
    Script(hb_script_from_string(str, -1))
}

// hb_language_t
public struct Language: Equatable, @unchecked Sendable {
    let pointer: hb_language_t?
}

// hb_language_from_string
public func languageFromString(str: String) -> Language {
    Language(pointer: hb_language_from_string(str, -1))
}

// hb_language_to_string
public func languageToString(language: Language) -> String? {
    hb_language_to_string(language.pointer).map { String(cString: $0) }
}

// hb_feature_t
public struct Feature: Equatable, Sendable {
    public var tag: UInt32
    public var value: UInt32
    public var start: UInt32
    public var end: UInt32

    init(_ feature: hb_feature_t) {
        tag = feature.tag
        value = feature.value
        start = feature.start
        end = feature.end
    }

    var cFeature: hb_feature_t {
        hb_feature_t(tag: tag, value: value, start: start, end: end)
    }
}

// hb_feature_from_string, nil where it cannot parse `str`.
public func featureFromString(str: String) -> Feature? {
    var feature = hb_feature_t()
    guard hb_feature_from_string(str, -1, &feature) != 0 else { return nil }
    return Feature(feature)
}
