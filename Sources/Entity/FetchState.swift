// Copyright (C) 2026 GeneralD (yumejustice@gmail.com)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

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