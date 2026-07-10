import Dependencies
import Domain
import FrequencyAnalyzer

extension FrequencyAnalyzerFactoryKey: DependencyKey {
    public static let liveValue: any FrequencyAnalyzerFactory = LiveFrequencyAnalyzerFactory()
}
