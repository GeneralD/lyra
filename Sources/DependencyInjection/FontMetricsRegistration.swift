import AppKitFontMetrics
import Dependencies
import Domain

extension FontMetricsProviderKey: DependencyKey {
    public static let liveValue: any FontMetricsProvider = AppKitFontMetrics()
}
