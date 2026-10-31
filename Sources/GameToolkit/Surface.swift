import Dawn
import SDL3

public enum SurfaceError: Error {
    case formatUnavailable
    case alphaModeUnavailable
    case presentModeUnavailable
    case renderAttachmentUnsupported
    case invalidWindowPixelSize
}

/// Configures `surface` to present to `window` at its size in pixels, in the
/// surface's preferred format, with vertical sync where it can, and returns
/// the configuration. Its textures can be copied from, for screenshots,
/// where the surface allows.
@MainActor
@discardableResult
public func configureSurface(
    _ surface: Surface, device: Device, adapter: Adapter, window: Window
) throws -> SurfaceConfiguration {
    let capabilities = try surface.getCapabilities(adapter: adapter)
    guard capabilities.usages.contains(.renderAttachment) else {
        throw SurfaceError.renderAttachmentUnsupported
    }
    guard let format = capabilities.formats.first else {
        throw SurfaceError.formatUnavailable
    }
    guard
        let alphaMode = capabilities.alphaModes.contains(.auto)
            ? CompositeAlphaMode.auto : capabilities.alphaModes.first
    else {
        throw SurfaceError.alphaModeUnavailable
    }
    guard
        let presentMode = capabilities.presentModes.contains(.fifo)
            ? PresentMode.fifo : capabilities.presentModes.first
    else {
        throw SurfaceError.presentModeUnavailable
    }
    let size = try getWindowSizeInPixels(window: window)
    guard size.w > 0, size.h > 0 else {
        throw SurfaceError.invalidWindowPixelSize
    }
    let usage: TextureUsage =
        capabilities.usages.contains(.copySrc) ? [.renderAttachment, .copySrc] : .renderAttachment
    let configuration = SurfaceConfiguration(
        device: device, format: format, usage: usage, width: UInt32(size.w),
        height: UInt32(size.h), viewFormats: [], alphaMode: alphaMode, presentMode: presentMode)
    try surface.configure(configuration)
    return configuration
}

/// A depth texture of `width` by `height` pixels, for render passes into a
/// surface of that size.
public func createDepthTexture(
    device: Device, width: UInt32, height: UInt32, format: TextureFormat = .depth24Plus
) throws -> TextureView {
    try device.createTexture(
        descriptor: TextureDescriptor(
            label: "depth", usage: .renderAttachment, dimension: .`2D`,
            size: Extent3D(width: width, height: height, depthOrArrayLayers: 1), format: format)
    ).createView()
}
