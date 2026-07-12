import Combine
import Dependencies
import Domain
import Foundation

/// config ファイルの親ディレクトリを監視し、変更を debounce したうえで
/// `ConfigUseCase.reload()` を呼び、結果を配信する Interactor の実装。
///
/// 監視トークンと debounce Task が可変状態として存在するため `final class` +
/// `@unchecked Sendable`（swift-conventions の class 正当化基準を満たす）。
public final class ConfigInteractorImpl: @unchecked Sendable {
    @Dependency(\.configWatchGateway) private var gateway
    @Dependency(\.configUseCase) private var configUseCase
    @Dependency(\.continuousClock) private var clock

    private let appStyleSubject = PassthroughSubject<Void, Never>()
    private let invalidSubject = CurrentValueSubject<ConfigReloadFailure?, Never>(nil)
    private let lock = NSLock()
    private var token: (any ConfigWatchToken)?
    private var debounceTask: Task<Void, Never>?

    public init() {}

    deinit {
        token?.stop()
        debounceTask?.cancel()
    }
}

extension ConfigInteractorImpl: ConfigInteractor {
    public var appStyleChanges: AnyPublisher<Void, Never> { appStyleSubject.eraseToAnyPublisher() }
    public var invalidConfig: AnyPublisher<ConfigReloadFailure?, Never> { invalidSubject.eraseToAnyPublisher() }

    public func start() {
        // config ファイルが在るときだけ、その親ディレクトリを監視。
        guard let path = configUseCase.existingConfigPath else { return }
        let directory = (path as NSString).deletingLastPathComponent
        let watchedGateway = gateway
        lock.withLock {
            token = watchedGateway.watch(directory: directory) { [weak self] in self?.scheduleReload() }
        }
    }

    public func stop() {
        lock.withLock {
            token?.stop()
            token = nil
            debounceTask?.cancel()
            debounceTask = nil
        }
    }

    // 監視イベントを debounce（連続イベント・巨大書込を coalesce）してから reload。
    private func scheduleReload() {
        lock.withLock {
            debounceTask?.cancel()
            debounceTask = Task { [weak self, clock] in
                try? await clock.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                self?.applyReload()
            }
        }
    }

    private func applyReload() {
        switch configUseCase.reload() {
        case .updated:
            invalidSubject.send(nil)
            appStyleSubject.send(())
        case .invalid(let failure):
            invalidSubject.send(failure)
        }
    }
}
