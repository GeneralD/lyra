import Foundation
import Testing

@testable import MediaRemoteDataSource

@Suite("ArtworkCache")
struct ArtworkCacheTests {
    private let cover = Data("cover".utf8)
    private var coverBase64: String { cover.base64EncodedString() }

    @Test("a new digest with a payload is decoded and served")
    func newDigestIsDecoded() {
        let decoder = CountingDecoder()

        let cache = ArtworkCache().updated(
            by: [helperClient(bundleID: "a", artworkDigest: "d1", artworkBase64: coverBase64)],
            decode: decoder.decode)

        #expect(cache.artwork(for: "a") == cover)
        #expect(decoder.count == 1)
    }

    @Test("an unchanged digest reuses the cached cover without the payload (#255)")
    func unchangedDigestIsReused() {
        let decoder = CountingDecoder()

        let cache = ArtworkCache()
            .updated(
                by: [helperClient(bundleID: "a", artworkDigest: "d1", artworkBase64: coverBase64)],
                decode: decoder.decode
            )
            .updated(by: [helperClient(bundleID: "a", artworkDigest: "d1")], decode: decoder.decode)

        #expect(cache.artwork(for: "a") == cover)
        #expect(decoder.count == 1)
    }

    @Test("an unchanged digest is not re-decoded even when the payload is resent (#270)")
    func resentPayloadIsNotRedecoded() {
        let decoder = CountingDecoder()
        let client = helperClient(bundleID: "a", artworkDigest: "d1", artworkBase64: coverBase64)

        let cache = ArtworkCache()
            .updated(by: [client], decode: decoder.decode)
            .updated(by: [client], decode: decoder.decode)

        #expect(cache.artwork(for: "a") == cover)
        #expect(decoder.count == 1)
    }

    @Test("a changed digest with a payload replaces the cover")
    func changedDigestReplaces() {
        let decoder = CountingDecoder()
        let next = Data("next".utf8)

        let cache = ArtworkCache()
            .updated(
                by: [helperClient(bundleID: "a", artworkDigest: "d1", artworkBase64: coverBase64)],
                decode: decoder.decode
            )
            .updated(
                by: [
                    helperClient(
                        bundleID: "a", artworkDigest: "d2", artworkBase64: next.base64EncodedString())
                ],
                decode: decoder.decode)

        #expect(cache.artwork(for: "a") == next)
        #expect(decoder.count == 2)
    }

    @Test("a client without a digest has no cover and drops the cached one")
    func missingDigestClears() {
        let decoder = CountingDecoder()

        let cache = ArtworkCache()
            .updated(
                by: [helperClient(bundleID: "a", artworkDigest: "d1", artworkBase64: coverBase64)],
                decode: decoder.decode
            )
            .updated(by: [helperClient(bundleID: "a")], decode: decoder.decode)
            .updated(by: [helperClient(bundleID: "a", artworkDigest: "d1")], decode: decoder.decode)

        // Once dropped, the old digest no longer resolves without its payload.
        #expect(cache.artwork(for: "a") == nil)
        #expect(decoder.count == 1)
    }

    @Test("a changed digest without its payload serves no cover rather than the stale one")
    func changedDigestWithoutPayloadIsNil() {
        let decoder = CountingDecoder()

        let cache = ArtworkCache()
            .updated(
                by: [helperClient(bundleID: "a", artworkDigest: "d1", artworkBase64: coverBase64)],
                decode: decoder.decode
            )
            .updated(by: [helperClient(bundleID: "a", artworkDigest: "d2")], decode: decoder.decode)

        #expect(cache.artwork(for: "a") == nil)
    }

    @Test("clients absent from the frame are evicted")
    func absentClientsAreEvicted() {
        let decoder = CountingDecoder()

        let cache = ArtworkCache()
            .updated(
                by: [helperClient(bundleID: "a", artworkDigest: "d1", artworkBase64: coverBase64)],
                decode: decoder.decode
            )
            .updated(by: [helperClient(bundleID: "b")], decode: decoder.decode)
            .updated(by: [helperClient(bundleID: "a", artworkDigest: "d1")], decode: decoder.decode)

        #expect(cache.artwork(for: "a") == nil)
    }

    @Test("covers are kept per client, so switching clients needs no resend")
    func coversArePerClient() {
        let decoder = CountingDecoder()
        let other = Data("other".utf8)

        let cache = ArtworkCache().updated(
            by: [
                helperClient(bundleID: "a", artworkDigest: "d1", artworkBase64: coverBase64),
                helperClient(bundleID: "b", artworkDigest: "d2", artworkBase64: other.base64EncodedString()),
            ],
            decode: decoder.decode)

        #expect(cache.artwork(for: "a") == cover)
        #expect(cache.artwork(for: "b") == other)
        #expect(cache.artwork(for: "c") == nil)
    }

    @Test("an undecodable payload is remembered as no cover and not retried")
    func undecodablePayloadIsNotRetried() {
        let decoder = CountingDecoder()
        let client = helperClient(bundleID: "a", artworkDigest: "d1", artworkBase64: "%%%")

        let cache = ArtworkCache()
            .updated(by: [client], decode: decoder.decode)
            .updated(by: [helperClient(bundleID: "a", artworkDigest: "d1")], decode: decoder.decode)

        #expect(cache.artwork(for: "a") == nil)
        #expect(decoder.count == 1)
    }
}
