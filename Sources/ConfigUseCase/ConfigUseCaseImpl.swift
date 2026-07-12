import Dependencies
import Domain
import os

public final class ConfigUseCaseImpl: @unchecked Sendable {
    @Dependency(\.configRepository) private var repository
    private let store: OSAllocatedUnfairLock<AppStyle>

    public init() {
        @Dependency(\.configRepository) var repository
        // 起動時に一度ロード（従来の lazy 初回ロードと同挙動、ただし可変 store に保持）
        store = OSAllocatedUnfairLock(initialState: repository.loadAppStyle())
    }
}

extension ConfigUseCaseImpl: ConfigUseCase {
    public var appStyle: AppStyle { store.withLock { $0 } }

    public func reload() -> ConfigReloadOutcome {
        let fileExists = repository.existingConfigPath != nil
        switch repository.validate() {
        case .loaded:
            let style = repository.loadAppStyle()
            store.withLock { $0 = style }
            return .updated(style)
        case .defaults where !fileExists:
            let style = repository.loadAppStyle()
            store.withLock { $0 = style }
            return .updated(style)
        case .defaults:
            // ファイルは在るが tryDecode が "" を返した = 読取失敗（atomic-save 中等）→ 前回値保持
            return .invalid(.init(path: repository.existingConfigPath ?? "", reason: .unreadable))
        case .unreadable(let path):
            return .invalid(.init(path: path, reason: .unreadable))
        case .decodeError(let path, let error):
            return .invalid(.init(path: path, reason: .decode(error)))
        }
    }

    public func template(format: ConfigFormat) -> String? {
        repository.template(format: format)
    }

    public func writeTemplate(format: ConfigFormat, force: Bool) throws -> String {
        try repository.writeTemplate(format: format, force: force)
    }

    public var existingConfigPath: String? {
        repository.existingConfigPath
    }
}
