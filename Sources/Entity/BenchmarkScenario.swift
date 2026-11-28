public enum BenchmarkScenario: String, CaseIterable, Sendable, Codable {
    case idle
    case cpuSpike = "cpu_spike"
    case memoryAlloc = "memory_alloc"
}
