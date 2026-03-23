public enum FetchState<T> {
    case idle
    case loading
    case revealing(T)
    case success(T)
    case failure
}

extension FetchState: Sendable where T: Sendable {}
extension FetchState: Equatable where T: Equatable {}

extension FetchState {
    public var value: T? {
        switch self {
        case .success(let v), .revealing(let v): return v
        case .idle, .loading, .failure: return nil
        }
    }

    public var isLoading: Bool {
        guard case .loading = self else { return false }
        return true
    }

    public var isRevealing: Bool {
        guard case .revealing = self else { return false }
        return true
    }

    public var isIdle: Bool {
        guard case .idle = self else { return false }
        return true
    }
}
