import Foundation
import Testing

@testable import MediaRemoteDataSource

@Suite("HelperFrame")
struct HelperFrameTests {
    @Test("decodes the system pid and every client field")
    func decodesAllFields() throws {
        let line = frameLine(
            systemPid: 7,
            clients: [
                clientEntry(
                    bundleID: "com.google.Chrome", pid: 44, title: "Song", artist: "Artist",
                    duration: 200.0, elapsed: 12.5, rate: 1.0, timestamp: 700.0,
                    artworkDigest: "abc", artworkBase64: "Zm9v")
            ])

        let frame = try #require(HelperFrame(line: line))

        #expect(frame.systemPid == 7)
        #expect(
            frame.clients == [
                HelperClient(
                    bundleID: "com.google.Chrome", pid: 44, title: "Song", artist: "Artist",
                    duration: 200.0, elapsed: 12.5, rate: 1.0, timestamp: 700.0,
                    artworkDigest: "abc", artworkBase64: "Zm9v")
            ])
    }

    @Test("absent optional fields decode as nil")
    func absentFieldsAreNil() throws {
        let frame = try #require(HelperFrame(line: #"{"clients":[{}]}"#))

        #expect(frame.systemPid == nil)
        #expect(
            frame.clients == [
                HelperClient(
                    bundleID: nil, pid: nil, title: nil, artist: nil, duration: nil, elapsed: nil,
                    rate: nil, timestamp: nil, artworkDigest: nil, artworkBase64: nil)
            ])
    }

    @Test("integral JSON numbers decode into Double fields")
    func integralNumbersDecodeAsDouble() throws {
        let frame = try #require(
            HelperFrame(line: #"{"clients":[{"rate":0,"duration":9,"elapsed":1,"timestamp":5}]}"#))

        #expect(frame.clients.first?.rate == 0)
        #expect(frame.clients.first?.duration == 9)
    }

    @Test(
        "lines that are not a frame decode as nil",
        arguments: [
            "", "{not-json}", #"{"has_info":false}"#, #"{"clients":"x"}"#, #"[1,2]"#,
            #"{"clients":[{"pid":"nope"}]}"#,
        ])
    func nonFramesAreNil(line: String) {
        #expect(HelperFrame(line: line) == nil)
    }

    @Test("a client is keyed by bundle id, then by pid, then as unknown")
    func clientKey() {
        #expect(helperClient(bundleID: "com.google.Chrome", pid: 1).key == "com.google.Chrome")
        #expect(helperClient(bundleID: nil, pid: 42).key == "pid:42")
        #expect(helperClient(bundleID: nil, pid: nil).key == "unknown")
    }
}
