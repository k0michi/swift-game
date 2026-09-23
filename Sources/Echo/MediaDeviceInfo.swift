public struct MediaDeviceInfo: Sendable {
    public let deviceId: String
    public let kind: MediaDeviceKind
    public let label: String
    public let groupId: String

    public init(deviceId: String, kind: MediaDeviceKind, label: String, groupId: String = "") {
        self.deviceId = deviceId
        self.kind = kind
        self.label = label
        self.groupId = groupId
    }
}
