import Combine
import Dependencies

/// config ファイルの変更を監視し、reload の結果を配信する Interactor。
///
/// `ConfigWatchGateway` で親ディレクトリの変更を検知し、debounce の後
/// `ConfigUseCase.reload()` を呼ぶ。`.updated` は Presenter への Void ping
/// (`appStyleChanges`) として、`.invalid` は最新値を保持するストリーム
/// (`invalidConfig`) としてエラーオーバーレイへ流す。
public protocol ConfigInteractor: Sendable {
    /// reload が新しい AppStyle を適用した時に発火する Void ping。
    var appStyleChanges: AnyPublisher<Void, Never> { get }
    /// 現在の不正状態（nil=正常、非nil=前回値保持中）。最新値を replay。
    var invalidConfig: AnyPublisher<ConfigReloadFailure?, Never> { get }
    func start()
    func stop()
}

public enum ConfigInteractorKey: TestDependencyKey {
    public static let testValue: any ConfigInteractor = UnimplementedConfigInteractor()
}

extension DependencyValues {
    public var configInteractor: any ConfigInteractor {
        get { self[ConfigInteractorKey.self] }
        set { self[ConfigInteractorKey.self] = newValue }
    }
}

private struct UnimplementedConfigInteractor: ConfigInteractor {
    var appStyleChanges: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var invalidConfig: AnyPublisher<ConfigReloadFailure?, Never> { Just(nil).eraseToAnyPublisher() }
    func start() {}
    func stop() {}
}
