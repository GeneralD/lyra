public enum BenchmarkScenario: String, CaseIterable, Sendable, Codable {
    case idle
    case cpuSpike = "cpu_spike"
    case memoryAlloc = "memory_alloc"
}

public enum BenchmarkUpdate: Sendable {
    case header
    case live(BenchmarkEntry)
    case completed(BenchmarkEntry)
}

public struct ResourceSnapshot: Sendable, Equatable {
    public let cpuUser: Double
    public let cpuSystem: Double
    public let peakRSS: Int64
    public let currentRSS: Int64

    public init(cpuUser: Double, cpuSystem: Double, peakRSS: Int64, currentRSS: Int64) {
        self.cpuUser = cpuUser
        self.cpuSystem = cpuSystem
        self.peakRSS = peakRSS
        self.currentRSS = currentRSS
    }
}

public struct BenchmarkEntry: Sendable, Codable {
    public let scenario: BenchmarkScenario
    public let durationSeconds: Double
    public let cpuUserSeconds: Double
    public let cpuSystemSeconds: Double
    public let peakRSSBytes: Int64
    public let currentRSSBytes: Int64

    public init(
        scenario: BenchmarkScenario,
        durationSeconds: Double,
        cpuUserSeconds: Double,
        cpuSystemSeconds: Double,
        peakRSSBytes: Int64,
        currentRSSBytes: Int64
    ) {
        self.scenario = scenario
        self.durationSeconds = durationSeconds
        self.cpuUserSeconds = cpuUserSeconds
        self.cpuSystemSeconds = cpuSystemSeconds
        self.peakRSSBytes = peakRSSBytes
        self.currentRSSBytes = currentRSSBytes
    }
}
