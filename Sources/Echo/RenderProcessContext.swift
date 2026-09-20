struct RenderProcessContext {
    let sampleRate: Float
    let frameCount: Int
    let currentFrame: Int64
    let params: [AudioParamID: RenderParamState]
}
