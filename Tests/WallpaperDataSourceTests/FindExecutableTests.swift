import Foundation
import Testing

@testable import WallpaperDataSource

@Suite("findExecutableInPath")
struct FindExecutableTests {
    @Test("resolves a well-known executable via the known-path scan")
    func resolvesKnownPath() {
        // `ls` lives at /bin/ls on current macOS; accept /usr/bin/ls too so the
        // test asserts "the known-path scan resolved a real system location",
        // not one exact path that could shift if Apple relocates the binary.
        let resolved = findExecutableInPath("ls")
        #expect(resolved == "/bin/ls" || resolved == "/usr/bin/ls")
    }

    @Test("returns nil when neither known paths nor `which` locate the tool")
    func returnsNilForMissingTool() {
        // A random name is absent from every known path AND from `which`, so the
        // fallback runs `which`, sees a non-zero exit, and returns nil.
        let absentName = "lyra-not-a-real-binary-\(UUID().uuidString)"
        #expect(findExecutableInPath(absentName) == nil)
    }
}
