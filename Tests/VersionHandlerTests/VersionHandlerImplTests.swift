import Testing

@testable import VersionHandler

@Suite("VersionHandlerImpl")
struct VersionHandlerImplTests {
    @Test("returns version string from bundled resource")
    func returnsVersion() {
        let handler = VersionHandlerImpl()
        let version = handler.version
        #expect(!version.isEmpty)
        #expect(version != "unknown")
    }

    @Test("version matches semver pattern")
    func semver() {
        let handler = VersionHandlerImpl()
        let pattern = #/^\d+\.\d+\.\d+$/#
        #expect(handler.version.wholeMatch(of: pattern) != nil)
    }
}
