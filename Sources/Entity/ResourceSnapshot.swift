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
