import Domain
import Testing

@testable import RandomSource

@Suite("SystemRandomSource")
struct SystemRandomSourceTests {
    @Test("returns values in [0, count)")
    func withinRange() {
        let source = SystemRandomSource()
        for count in 1...32 {
            for _ in 0..<50 {
                let value = source.next(below: count)
                #expect(value >= 0)
                #expect(value < count)
            }
        }
    }

    @Test("returns 0 when count is 1")
    func singleValue() {
        let source = SystemRandomSource()
        for _ in 0..<10 {
            #expect(source.next(below: 1) == 0)
        }
    }
}
