public enum BiquadFilterType: String, CaseIterable, Sendable {
    case lowpass
    case highpass
    case bandpass
    case lowshelf
    case highshelf
    case peaking
    case notch
    case allpass
}
