import Foundation
import Testing

@testable import Entity

@Suite("WallpaperConfig")
struct WallpaperConfigTests {

    // MARK: - Time Parsing

    @Suite("parseTime")
    struct ParseTime {
        @Test("parses M:SS format")
        func minutesSeconds() {
            #expect(WallpaperConfig.parseTime("1:30") == 90.0)
        }

        @Test("parses H:MM:SS format")
        func hoursMinutesSeconds() {
            #expect(WallpaperConfig.parseTime("1:05:30") == 3930.0)
        }

        @Test("parses zero")
        func zero() {
            #expect(WallpaperConfig.parseTime("0:00") == 0.0)
        }

        @Test("parses fractional seconds")
        func fractional() {
            #expect(WallpaperConfig.parseTime("1:23.5") == 83.5)
        }

        @Test("parses large values")
        func largeValue() {
            #expect(WallpaperConfig.parseTime("59:59") == 3599.0)
        }

        @Test("parses bare seconds")
        func bareSeconds() {
            #expect(WallpaperConfig.parseTime("42") == 42.0)
        }

        @Test("returns nil for empty string")
        func emptyString() {
            #expect(WallpaperConfig.parseTime("") == nil)
        }

        @Test("returns nil for invalid format")
        func invalid() {
            #expect(WallpaperConfig.parseTime("abc") == nil)
        }

        @Test("returns nil for too many colons")
        func tooManyColons() {
            #expect(WallpaperConfig.parseTime("1:2:3:4") == nil)
        }
    }

    // MARK: - Time Formatting

    @Suite("formatTime")
    struct FormatTime {
        @Test("formats minutes and seconds")
        func minutesSeconds() {
            #expect(WallpaperConfig.formatTime(90) == "1:30")
        }

        @Test("formats hours")
        func hours() {
            #expect(WallpaperConfig.formatTime(3930) == "1:05:30")
        }

        @Test("formats zero")
        func zero() {
            #expect(WallpaperConfig.formatTime(0) == "0:00")
        }

        @Test("formats fractional seconds")
        func fractional() {
            #expect(WallpaperConfig.formatTime(83.5) == "1:23.5")
        }

        @Test("round-trip: parseTime then formatTime")
        func roundTrip() {
            let original = "2:15"
            let interval = WallpaperConfig.parseTime(original)!
            #expect(WallpaperConfig.formatTime(interval) == original)
        }

        @Test("round-trip with fractional")
        func roundTripFractional() {
            let original = "1:23.5"
            let interval = WallpaperConfig.parseTime(original)!
            #expect(WallpaperConfig.formatTime(interval) == original)
        }
    }

    // MARK: - Validation

    @Suite("validate")
    struct Validate {
        @Test("nil start and end pass through")
        func bothNil() {
            let (s, e) = WallpaperConfig.validate(start: nil, end: nil)
            #expect(s == nil)
            #expect(e == nil)
        }

        @Test("positive values pass through")
        func positiveValues() {
            let (s, e) = WallpaperConfig.validate(start: 30, end: 120)
            #expect(s == 30)
            #expect(e == 120)
        }

        @Test("negative start clamped to zero")
        func negativeStart() {
            let (s, e) = WallpaperConfig.validate(start: -5, end: 60)
            #expect(s == 0)
            #expect(e == 60)
        }

        @Test("negative end clamped to zero")
        func negativeEnd() {
            let (s, e) = WallpaperConfig.validate(start: 10, end: -3)
            #expect(s == 10)
            #expect(e == nil)  // 10 >= 0 → end discarded
        }

        @Test("start equal to end discards end")
        func startEqualsEnd() {
            let (s, e) = WallpaperConfig.validate(start: 60, end: 60)
            #expect(s == 60)
            #expect(e == nil)
        }

        @Test("start greater than end discards end")
        func startGreaterThanEnd() {
            let (s, e) = WallpaperConfig.validate(start: 120, end: 30)
            #expect(s == 120)
            #expect(e == nil)
        }

        @Test("start only with no end")
        func startOnly() {
            let (s, e) = WallpaperConfig.validate(start: 30, end: nil)
            #expect(s == 30)
            #expect(e == nil)
        }

        @Test("end only with no start")
        func endOnly() {
            let (s, e) = WallpaperConfig.validate(start: nil, end: 120)
            #expect(s == nil)
            #expect(e == 120)
        }

        @Test("both negative clamps to zero, then start >= end discards end")
        func bothNegative() {
            let (s, e) = WallpaperConfig.validate(start: -10, end: -5)
            #expect(s == 0)
            #expect(e == nil)  // 0 >= 0 → end discarded
        }
    }

    // MARK: - Decoding

    @Suite("Codable")
    struct CodableTests {
        @Test("decodes bare string")
        func bareString() throws {
            let json = #""loop.mp4""#.data(using: .utf8)!
            let config = try JSONDecoder().decode(WallpaperConfig.self, from: json)
            #expect(config.location == "loop.mp4")
            #expect(config.start == nil)
            #expect(config.end == nil)
        }

        @Test("decodes table with location only")
        func tableLocationOnly() throws {
            let json = #"{"location":"bg.mp4"}"#.data(using: .utf8)!
            let config = try JSONDecoder().decode(WallpaperConfig.self, from: json)
            #expect(config.location == "bg.mp4")
            #expect(config.start == nil)
            #expect(config.end == nil)
        }

        @Test("decodes table with start and end")
        func tableWithTrim() throws {
            let json = #"{"location":"video.mp4","start":"0:30","end":"3:45"}"#.data(using: .utf8)!
            let config = try JSONDecoder().decode(WallpaperConfig.self, from: json)
            #expect(config.location == "video.mp4")
            #expect(config.start == 30.0)
            #expect(config.end == 225.0)
        }

        @Test("decodes table with start only")
        func tableStartOnly() throws {
            let json = #"{"location":"v.mp4","start":"1:00"}"#.data(using: .utf8)!
            let config = try JSONDecoder().decode(WallpaperConfig.self, from: json)
            #expect(config.start == 60.0)
            #expect(config.end == nil)
        }

        @Test("encodes bare string when no trim")
        func encodeBareString() throws {
            let config = WallpaperConfig(location: "file.mp4")
            let data = try JSONEncoder().encode(config)
            let decoded = try JSONDecoder().decode(String.self, from: data)
            #expect(decoded == "file.mp4")
        }

        @Test("encodes table when trim present")
        func encodeTable() throws {
            let config = WallpaperConfig(location: "file.mp4", start: 30, end: 120)
            let data = try JSONEncoder().encode(config)
            let decoded = try JSONDecoder().decode(WallpaperConfig.self, from: data)
            #expect(decoded.location == "file.mp4")
            #expect(decoded.start == 30)
            #expect(decoded.end == 120)
        }

        @Test("round-trip preserves values")
        func roundTrip() throws {
            let original = WallpaperConfig(location: "https://youtu.be/XXX", start: 90, end: 225)
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(WallpaperConfig.self, from: data)
            #expect(decoded == original)
        }

        @Test("validation applies during decode: negative start clamped to zero")
        func decodeNegativeStart() throws {
            let json = #"{"location":"v.mp4","start":"-5","end":"1:00"}"#.data(using: .utf8)!
            let config = try JSONDecoder().decode(WallpaperConfig.self, from: json)
            #expect(config.start == 0)  // -5 parsed then clamped to 0
            #expect(config.end == 60.0)
        }

        @Test("validation applies during decode: start >= end discards end")
        func decodeStartGteEnd() throws {
            let json = #"{"location":"v.mp4","start":"2:00","end":"1:00"}"#.data(using: .utf8)!
            let config = try JSONDecoder().decode(WallpaperConfig.self, from: json)
            #expect(config.start == 120.0)
            #expect(config.end == nil)
        }
    }
}
