import Testing
@testable import SDL3

@MainActor
extension SDL3Tests {
    @Test
    func versionNumberRoundTripsComponents() {
        let value = Version(major: 3, minor: 4, patch: 16)

        #expect(value.rawValue == 3_004_016)
        #expect(value.major == 3)
        #expect(value.minor == 4)
        #expect(value.micro == 16)
    }

    @Test
    func headerAndLinkedVersionsAreAvailable() {
        #expect(version == Version(
            major: majorVersion,
            minor: minorVersion,
            patch: microVersion
        ))
        #expect(versionAtLeast(major: 3, minor: 2, patch: 0))
        #expect(getVersion().major == 3)
        #expect(!getRevision().contains("\0"))
    }
}
