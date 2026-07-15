import Dependencies
import Domain
import os

public final class ConfigUseCaseImpl: @unchecked Sendable {
    @Dependency(\.configRepository) private var repository
    private let store: OSAllocatedUnfairLock<AppStyle>

    public init() {
        @Dependency(\.configRepository) var repository
        // Load once at startup, preserving the previous single-load behavior in mutable storage.
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
            // An empty tryDecode result for an existing file indicates a read failure,
            // such as during an atomic save. Retain the previous value.
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
