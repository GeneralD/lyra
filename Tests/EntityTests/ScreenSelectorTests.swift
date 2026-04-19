import Entity
import Foundation
import Testing

@Suite("ScreenSelector")
struct ScreenSelectorTests {
    private func decode(_ json: String) throws -> ScreenSelector {
        try JSONDecoder().decode(ScreenSelector.self, from: Data(json.utf8))
    }

    private func encode(_ selector: ScreenSelector) throws -> String {
        let data = try JSONEncoder().encode(selector)
        return String(decoding: data, as: UTF8.self)
    }

    @Test("decodes integer as .index")
    func decodeInteger() throws {
        #expect(try decode("2") == .index(2))
        #expect(try decode("0") == .index(0))
    }

    @Test("decodes known string cases")
    func decodeKnownStrings() throws {
        #expect(try decode("\"main\"") == .main)
        #expect(try decode("\"primary\"") == .primary)
        #expect(try decode("\"smallest\"") == .smallest)
        #expect(try decode("\"largest\"") == .largest)
        #expect(try decode("\"vacant\"") == .vacant)
    }

    @Test("decoding is case-insensitive")
    func decodeCaseInsensitive() throws {
        #expect(try decode("\"MAIN\"") == .main)
        #expect(try decode("\"Vacant\"") == .vacant)
    }

    @Test("unknown string falls back to .main")
    func decodeUnknownFallsBack() throws {
        #expect(try decode("\"bogus\"") == .main)
    }

    @Test("round-trips through Codable")
    func roundTrip() throws {
        for selector in [ScreenSelector.main, .primary, .smallest, .largest, .vacant, .index(3)] {
            let json = try encode(selector)
            #expect(try decode(json) == selector)
        }
    }
}
