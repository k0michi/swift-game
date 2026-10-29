#if os(Emscripten)
@MainActor
public final class PeriodicWave {
    public let context: BaseAudioContext
    let object: JSObjectReference

    public init(context: BaseAudioContext, options: PeriodicWaveOptions = PeriodicWaveOptions()) throws {
        // Checked here too, so that values JSON cannot carry, which are not
        // finite, throw as they would natively.
        let (real, imag) = try options.coefficients()
        self.context = context
        object = try JSObjectReference.new("PeriodicWave", context: context.object, options: [
            ("real", .array(real.map { .number(Double($0)) })),
            ("imag", .array(imag.map { .number(Double($0)) })),
            ("disableNormalization", .bool(options.disableNormalization)),
        ])
    }
}
#endif
