import Testing

@testable import MediaRemoteDataSource

@Suite("NowPlayingClientSelector")
struct NowPlayingClientSelectorTests {
    private let selector = NowPlayingClientSelector()

    /// Selects from the clients in both orders: the helper's ordering must never
    /// decide, and a rank comparison that reads one side wrongly shows up as a
    /// disagreement between the two.
    private func selectedKey(
        _ clients: [HelperClient], systemPid: Int? = nil, following followed: String? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> String? {
        let selected = [clients, clients.reversed()].map {
            selector.selection(in: HelperFrame(systemPid: systemPid, clients: $0), following: followed)?.key
        }
        #expect(selected[0] == selected[1], "selection depends on client order", sourceLocation: sourceLocation)
        return selected[0]
    }

    @Test("no clients selects nothing")
    func emptyFrame() {
        #expect(selectedKey([]) == nil)
    }

    @Test("clients without a title are never selected")
    func titlelessClientsAreIneligible() {
        let clients = [
            helperClient(bundleID: "com.displaylink.DisplayLinkUserAgent", pid: 1, title: nil, rate: 0),
            helperClient(bundleID: "empty.title", pid: 2, title: ""),
        ]

        #expect(selectedKey(clients, systemPid: 1) == nil)
    }

    @Test("a playing client wins over a title-less system client (#358)")
    func playingClientBeatsHijackedSystemSlot() {
        let clients = [
            helperClient(bundleID: "com.displaylink.DisplayLinkUserAgent", pid: 1, title: nil, rate: 0),
            helperClient(bundleID: "com.google.Chrome", pid: 2, title: "Song", rate: 1),
        ]

        #expect(selectedKey(clients, systemPid: 1) == "com.google.Chrome")
    }

    @Test("a playing client wins over a paused system client that has a title")
    func playingBeatsPausedSystem() {
        let clients = [
            helperClient(bundleID: "com.apple.Music", pid: 1, rate: 0, timestamp: 99),
            helperClient(bundleID: "com.google.Chrome", pid: 2, rate: 1, timestamp: 1),
        ]

        #expect(selectedKey(clients, systemPid: 1, following: "com.apple.Music") == "com.google.Chrome")
    }

    @Test("among playing clients the system client wins, even over the followed one")
    func systemBeatsFollowedWhenBothPlay() {
        let clients = [
            helperClient(bundleID: "com.apple.Music", pid: 1, timestamp: 1),
            helperClient(bundleID: "com.google.Chrome", pid: 2, timestamp: 99),
        ]

        #expect(selectedKey(clients, systemPid: 1, following: "com.google.Chrome") == "com.apple.Music")
    }

    @Test("among playing non-system clients the followed one wins over a newer timestamp")
    func followedIsSticky() {
        let clients = [
            helperClient(bundleID: "a.player", pid: 1, timestamp: 1),
            helperClient(bundleID: "b.player", pid: 2, timestamp: 99),
        ]

        #expect(selectedKey(clients, systemPid: 3, following: "a.player") == "a.player")
    }

    @Test("without system or followed client the newer timestamp wins")
    func newerTimestampWins() {
        let clients = [
            helperClient(bundleID: "a.player", timestamp: 1),
            helperClient(bundleID: "b.player", timestamp: 99),
        ]

        #expect(selectedKey(clients) == "b.player")
    }

    @Test("a missing timestamp ranks below any reported one")
    func missingTimestampRanksLowest() {
        let clients = [
            helperClient(bundleID: "a.player", timestamp: nil),
            helperClient(bundleID: "b.player", timestamp: -1),
        ]

        #expect(selectedKey(clients) == "b.player")
    }

    @Test("a full tie resolves to the smallest key regardless of input order")
    func fullTieIsDeterministic() {
        let clients = [
            helperClient(bundleID: "b.player", timestamp: 5),
            helperClient(bundleID: "a.player", timestamp: 5),
        ]

        #expect(selectedKey(clients) == "a.player")
        #expect(selectedKey(clients.reversed()) == "a.player")
    }

    @Test("a client that reports no rate counts as playing")
    func missingRateCountsAsPlaying() {
        let clients = [
            helperClient(bundleID: "paused.system", pid: 1, rate: 0),
            helperClient(bundleID: "unknown.rate", pid: 2, rate: nil),
        ]

        #expect(selectedKey(clients, systemPid: 1) == "unknown.rate")
    }

    @Test("when everything is paused behind a title-less system slot, the followed client stays")
    func pausedFollowedClientSurvivesHijackedSlot() {
        let clients = [
            helperClient(bundleID: "com.displaylink.DisplayLinkUserAgent", pid: 1, title: nil, rate: 0),
            helperClient(bundleID: "a.player", pid: 2, rate: 0, timestamp: 1),
            helperClient(bundleID: "b.player", pid: 3, rate: 0, timestamp: 99),
        ]

        #expect(selectedKey(clients, systemPid: 1, following: "a.player") == "a.player")
    }

    @Test("when everything is paused, a titled system client wins over the followed one")
    func pausedSystemBeatsPausedFollowed() {
        let clients = [
            helperClient(bundleID: "com.apple.Music", pid: 1, rate: 0),
            helperClient(bundleID: "com.google.Chrome", pid: 2, rate: 0),
        ]

        #expect(selectedKey(clients, systemPid: 1, following: "com.google.Chrome") == "com.apple.Music")
    }

    @Test("a client without a pid is never the system client, even when no system pid is known")
    func pidlessClientIsNotSystem() {
        // Matching `nil == nil` would make the older, pid-less client the system one.
        let clients = [
            helperClient(bundleID: "a.player", pid: nil, timestamp: 1),
            helperClient(bundleID: "b.player", pid: 5, timestamp: 99),
        ]

        #expect(selectedKey(clients, systemPid: nil) == "b.player")
    }
}
