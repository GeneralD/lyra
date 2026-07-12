import Dependencies

/// 停止可能な監視ハンドル。
public protocol ConfigWatchToken: Sendable {
    func stop()
}

/// config ディレクトリを監視し、変更のたびに `onChange` を呼ぶ OS 境界。
/// 実体は DispatchSource（fake 注入でテスト可能、AudioTapGateway と同じ正当化）。
public protocol ConfigWatchGateway: Sendable {
    /// `directory` を監視開始。イベント毎に `onChange` を任意キューで呼ぶ。
    /// 監視を張れない場合は nil。
    func watch(directory: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)?
}

public enum ConfigWatchGatewayKey: TestDependencyKey {
    public static let testValue: any ConfigWatchGateway = UnimplementedConfigWatchGateway()
}

extension DependencyValues {
    public var configWatchGateway: any ConfigWatchGateway {
        get { self[ConfigWatchGatewayKey.self] }
        set { self[ConfigWatchGatewayKey.self] = newValue }
    }
}

private struct UnimplementedConfigWatchGateway: ConfigWatchGateway {
    func watch(directory: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? { nil }
}
