import Domain
import Testing

@testable import FrequencyAnalyzer

@Suite("LiveFrequencyAnalyzerFactory")
struct LiveFrequencyAnalyzerFactoryTests {
    @Test("builds a working analyzer honoring the requested bar count")
    func factoryBuildsWorkingAnalyzer() {
        let analyzer = LiveFrequencyAnalyzerFactory().analyzer(
            fftSize: 256, barCount: 8, minDb: -70, maxDb: -20,
            linearScale: true, minFrequency: 40, maxFrequency: 14000,
            sampleRate: 48000)
        let silence = [Float](repeating: 0, count: 256)
        #expect(analyzer.magnitudes(of: silence) == [Float](repeating: 0, count: 8))
    }
}
