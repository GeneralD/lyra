public enum BenchmarkUpdate: Sendable {
    case header
    case live(BenchmarkEntry)
    case completed(BenchmarkEntry)
}
