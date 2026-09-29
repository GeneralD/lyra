import Foundation
import Testing

@testable import Entity

@Suite("OcclusionPauseConfig")
struct OcclusionPauseConfigTests {

    private func decode(_ json: String) throws -> OcclusionPauseConfig {
        try JSONDecoder().decode(OcclusionPauseConfig.self, from: Data(json.utf8))
    }

    // MARK: - decode

    @Test("an empty section decodes to the disabled, 0.9-threshold defaults")
    func emptySectionDecodesToDefaults() throws {
        let config = try decode("{}")
        #expect(config.enabled == false)
        #expect(config.threshold.value == 0.9)
    }

    @Test("a partially-specified section fills the missing key from defaults")
    func partialSpecificationFillsMissingKeyFromDefaults() throws {
        let enabledOnly = try decode(#"{"enabled": true}"#)
        #expect(enabledOnly.enabled == true)
        #expect(enabledOnly.threshold.value == 0.9)

        let thresholdOnly = try decode(#"{"threshold": 0.75}"#)
        #expect(thresholdOnly.enabled == false)
        #expect(thresholdOnly.threshold.value == 0.75)
    }

    @Test("a fully-specified section decodes both values")
    func fullySpecifiedSectionDecodesBothValues() throws {
        let config = try decode(#"{"enabled": true, "threshold": 0.5}"#)
        #expect(config.enabled == true)
        #expect(config.threshold.value == 0.5)
    }

    @Test("threshold accepts an integer as well as a float, via FlexibleDouble")
    func thresholdAcceptsInteger() throws {
        let config = try decode(#"{"threshold": 1}"#)
        #expect(config.threshold.value == 1.0)
    }
}
