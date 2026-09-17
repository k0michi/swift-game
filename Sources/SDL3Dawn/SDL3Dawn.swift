import Dawn
import SDL3

public enum SDL3DawnError: Error, Equatable {
    case surfaceSourceUnavailable
}

public extension Instance {
    // wgpuInstanceCreateSurface
    @MainActor
    func createSurface(from window: Window) throws -> Surface {
        #if os(macOS)
        let metalView = try metalCreateView(window: window)
        let surface = try createSurface(
            descriptor: SurfaceDescriptor(
                nextInChain: SurfaceSourceMetalLayer(
                    layer: try metalGetLayer(view: metalView)
                )
            )
        )
        return surface
        #elseif os(Windows)
        let properties = try getWindowProperties(window: window)
        guard let hinstance = getPointerProperty(
            props: properties,
            name: propWindowWin32InstancePointer,
            boundTo: window
        ), let hwnd = getPointerProperty(
            props: properties,
            name: propWindowWin32HWNDPointer,
            boundTo: window
        ) else {
            throw SDL3DawnError.surfaceSourceUnavailable
        }

        let surface = try createSurface(
            descriptor: SurfaceDescriptor(
                nextInChain: SurfaceSourceWindowsHWND(
                    hinstance: hinstance,
                    hwnd: hwnd
                )
            )
        )
        return surface
        #elseif os(Linux)
        let properties = try getWindowProperties(window: window)

        let surface: Surface
        if let display = getPointerProperty(
            props: properties,
            name: propWindowWaylandDisplayPointer,
            boundTo: window
        ), let waylandSurface = getPointerProperty(
            props: properties,
            name: propWindowWaylandSurfacePointer,
            boundTo: window
        ) {
            surface = try createSurface(
                descriptor: SurfaceDescriptor(
                    nextInChain: SurfaceSourceWaylandSurface(
                        display: display,
                        surface: waylandSurface
                    )
                )
            )
        } else if let display = getPointerProperty(
            props: properties,
            name: propWindowX11DisplayPointer,
            boundTo: window
        ) {
            let x11Window = getNumberProperty(
                props: properties,
                name: propWindowX11WindowNumber
            )
            guard x11Window > 0 else {
                throw SDL3DawnError.surfaceSourceUnavailable
            }
            surface = try createSurface(
                descriptor: SurfaceDescriptor(
                    nextInChain: SurfaceSourceXlibWindow(
                        display: display,
                        window: UInt64(x11Window)
                    )
                )
            )
        } else {
            throw SDL3DawnError.surfaceSourceUnavailable
        }
        return surface
        #else
        throw SDL3DawnError.surfaceSourceUnavailable
        #endif
    }
}
