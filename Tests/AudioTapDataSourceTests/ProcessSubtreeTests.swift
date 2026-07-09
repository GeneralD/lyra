import Foundation
import Testing

@testable import AudioTapDataSource

@Suite("parentPid")
struct ParentPidTests {
    @Test("the current process's parent pid is readable and positive")
    func readsRealParentPid() {
        let parent = parentPid(of: getpid())
        #expect((parent ?? 0) > 0)
    }
}

@Suite("isInProcessSubtree")
struct IsInProcessSubtreeTests {
    // Synthetic tree: 300 → 200 → 100 → 1 (child → parent).
    private let parents: [pid_t: pid_t] = [300: 200, 200: 100, 100: 1]
    private func parent(_ pid: pid_t) -> pid_t? { parents[pid] }

    @Test("a pid equal to the root is in the subtree")
    func equalsRoot() {
        #expect(isInProcessSubtree(200, root: 200, parent: parent))
    }

    @Test("a descendant is in the subtree via the parent walk")
    func descendantIncluded() {
        #expect(isInProcessSubtree(300, root: 100, parent: parent))
    }

    @Test("an unrelated root is not an ancestor")
    func unrelatedExcluded() {
        #expect(!isInProcessSubtree(300, root: 999, parent: parent))
    }

    @Test("a nil pid is never in a subtree")
    func nilExcluded() {
        #expect(!isInProcessSubtree(nil, root: 100, parent: parent))
    }

    @Test("an unreadable parent stops the walk short")
    func brokenLookupStops() {
        // 400 has no known parent, so the walk can't reach root 100.
        #expect(!isInProcessSubtree(400, root: 100, parent: parent))
    }
}
