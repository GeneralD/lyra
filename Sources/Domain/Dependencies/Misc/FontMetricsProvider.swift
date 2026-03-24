import Dependencies
import Foundation

public protocol FontMetricsProvider: Sendable {
    @MainActor func lineHeight(fontName: String, fontSize: Double, spacing: Double) -> Double
}

public enum FontMetricsProviderKey: TestDependencyKey {
    public static let testValue: any FontMetricsProvider = StubFontMetrics()
}

extension DependencyValues {
    public var fontMetrics: any FontMetricsProvider {
        get { self[FontMetricsProviderKey.self] }
        set { self[FontMetricsProviderKey.self] = newValue }
    }
}

private struct StubFontMetrics: FontMetricsProvider {
    @MainActor func lineHeight(fontName: String, fontSize: Double, spacing: Double) -> Double {
        fontSize + spacing * 2
    }
}
