import Domain

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

    public var isSuccess: Bool {
        guard case .success = self else { return false }
        return true
    }
}
