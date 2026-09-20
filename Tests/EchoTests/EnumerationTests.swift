import Echo
import Testing

@Test func webIDLEnumerationsPreserveTheirValuesAndOrder() {
    #expect(
        AudioContextState.allCases.map(\.rawValue) == [
            "suspended", "running", "closed", "interrupted",
        ])
    #expect(
        AudioContextRenderSizeCategory.allCases.map(\.rawValue) == [
            "default", "hardware",
        ])
    #expect(
        AudioContextLatencyCategory.allCases.map(\.rawValue) == [
            "balanced", "interactive", "playback",
        ])
    #expect(AudioSinkType.allCases.map(\.rawValue) == ["none"])
    #expect(
        ChannelCountMode.allCases.map(\.rawValue) == [
            "max", "clamped-max", "explicit",
        ])
    #expect(
        ChannelInterpretation.allCases.map(\.rawValue) == [
            "speakers", "discrete",
        ])
    #expect(AutomationRate.allCases.map(\.rawValue) == ["a-rate", "k-rate"])
    #expect(
        BiquadFilterType.allCases.map(\.rawValue) == [
            "lowpass", "highpass", "bandpass", "lowshelf", "highshelf", "peaking", "notch",
            "allpass",
        ])
    #expect(
        OscillatorType.allCases.map(\.rawValue) == [
            "sine", "square", "sawtooth", "triangle", "custom",
        ])
    #expect(PanningModelType.allCases.map(\.rawValue) == ["equalpower", "HRTF"])
    #expect(
        DistanceModelType.allCases.map(\.rawValue) == [
            "linear", "inverse", "exponential",
        ])
    #expect(OverSampleType.allCases.map(\.rawValue) == ["none", "2x", "4x"])
}
