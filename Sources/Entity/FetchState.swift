public enum FetchState<T> {
    case idle
    case loading
    case revealing(T)
    case success(T)
    case failure
}

extension FetchState: Sendable where T: Sendable {}
extension FetchState: Equatable where T: Equatable {}
