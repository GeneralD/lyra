import Testing

@testable import ConfigDataSource

@Suite("sanitizeTomlFloats")
struct SanitizeTomlFloatsSpec {
    private let ds = ConfigDataSourceImpl()

    @Test("truncates long decimal fractions")
    func truncatesLong() {
        let input = "opacity = 0.80000000000000004"
        let result = ds.sanitizeTomlFloats(input)
        #expect(result == "opacity = 0.8")
    }

    @Test("leaves short decimals unchanged")
    func shortUnchanged() {
        let input = "opacity = 0.8"
        let result = ds.sanitizeTomlFloats(input)
        #expect(result == "opacity = 0.8")
    }

    @Test("handles multiple floats on separate lines")
    func multipleLines() {
        let input = """
            size = 12.000000000000001
            spacing = 6.0
            opacity = 0.80000000000000004
            """
        let result = ds.sanitizeTomlFloats(input)
        #expect(result.contains("size = 12"))
        #expect(result.contains("spacing = 6.0"))
        #expect(result.contains("opacity = 0.8"))
    }

    @Test("does not modify strings that look like floats")
    func stringValues() {
        let input = #"name = "1.23456789012345""#
        let result = ds.sanitizeTomlFloats(input)
        #expect(result == input)
    }

    @Test("does not modify integers")
    func integers() {
        let input = "port = 8080"
        let result = ds.sanitizeTomlFloats(input)
        #expect(result == "port = 8080")
    }
}
