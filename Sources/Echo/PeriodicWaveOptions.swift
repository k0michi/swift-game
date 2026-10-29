public struct PeriodicWaveConstraints: Sendable, Equatable {
    public var disableNormalization: Bool

    public init(disableNormalization: Bool = false) {
        self.disableNormalization = disableNormalization
    }
}

public struct PeriodicWaveOptions: Sendable, Equatable {
    public var real: [Float]?
    public var imag: [Float]?
    public var disableNormalization: Bool

    public init(real: [Float]? = nil, imag: [Float]? = nil, disableNormalization: Bool = false) {
        self.real = real
        self.imag = imag
        self.disableNormalization = disableNormalization
    }

    // [[real]] and [[imag]], as the PeriodicWave constructor makes them. A
    // missing array is zeros, neither makes a sine, and the DC terms are 0.
    func coefficients() throws -> (real: [Float], imag: [Float]) {
        // The members are sequence<float>, which takes only finite values.
        for values in [real, imag] {
            if let values, !values.allSatisfy(\.isFinite) { throw WebAudioError.rangeError }
        }
        var coefficients: (real: [Float], imag: [Float])
        switch (real, imag) {
        case let (real?, imag?):
            guard real.count == imag.count, real.count >= 2 else { throw WebAudioError.indexSize }
            coefficients = (real, imag)
        case let (real?, nil):
            guard real.count >= 2 else { throw WebAudioError.indexSize }
            coefficients = (real, [Float](repeating: 0, count: real.count))
        case let (nil, imag?):
            guard imag.count >= 2 else { throw WebAudioError.indexSize }
            coefficients = ([Float](repeating: 0, count: imag.count), imag)
        case (nil, nil):
            coefficients = ([0, 0], [0, 1])
        }
        coefficients.real[0] = 0
        coefficients.imag[0] = 0
        return coefficients
    }
}
