struct RenderProcessContext {
    let sampleRate: Float
    let frameCount: Int
    let currentFrame: Int64
    let parameterValues: [AudioParamID: [Float]]
}
