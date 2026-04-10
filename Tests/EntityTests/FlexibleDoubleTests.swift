import Foundation
import Testing

@testable import Entity

@Suite("FlexibleDouble")
struct FlexibleDoubleTests {
    @Test("decodes from JSON Double")
    func decodesDouble() throws {
        let json = Data(#"3.14"#.utf8)
        let result = try JSONDecoder().decode(FlexibleDouble.self, from: json)
        #expect(result.value == 3.14)
    }

    @Test("decodes from JSON Int")
    func decodesInt() throws {
        let json = Data(#"42"#.utf8)
        let result = try JSONDecoder().decode(FlexibleDouble.self, from: json)
        #expect(result.value == 42.0)
    }

    @Test("encodes to JSON Double")
    func encodesToDouble() throws {
        let value = FlexibleDouble(2.5)
        let data = try JSONEncoder().encode(value)
        let str = String(data: data, encoding: .utf8)
        #expect(str == "2.5")
    }

    @Test("roundtrips through JSON")
    func roundtrip() throws {
        let original = FlexibleDouble(99.9)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FlexibleDouble.self, from: data)
        #expect(decoded.value == original.value)
    }
}
