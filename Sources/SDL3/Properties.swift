import CSDL3
import Interop

// SDL_PropertiesID
public struct PropertiesID: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

// SDL_GetPointerProperty
public func getPointerProperty(
    props: PropertiesID,
    name: String,
    defaultValue: UnsafeMutableRawPointer? = nil
) -> UnsafeMutableRawPointer? {
    SDL_GetPointerProperty(props.rawValue, name, defaultValue)
}

// SDL_GetPointerProperty
public func getPointerProperty<Owner: AnyObject>(
    props: PropertiesID,
    name: String,
    boundTo owner: Owner
) -> UnsafeLifetimeBoundRawPointer? {
    SDL_GetPointerProperty(props.rawValue, name, nil).map {
        UnsafeLifetimeBoundRawPointer($0, boundTo: owner)
    }
}

// SDL_GetNumberProperty
public func getNumberProperty(
    props: PropertiesID,
    name: String,
    defaultValue: Int64 = 0
) -> Int64 {
    SDL_GetNumberProperty(props.rawValue, name, defaultValue)
}
