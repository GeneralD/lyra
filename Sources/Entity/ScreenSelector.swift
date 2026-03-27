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

public enum ScreenSelector {
    case main
    case primary
    case index(Int)
    case smallest
    case largest
}

extension ScreenSelector: Sendable {}
extension ScreenSelector: Equatable {}

extension ScreenSelector: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let n = try? container.decode(Int.self) {
            self = .index(n)
            return
        }
        let s = try container.decode(String.self)
        switch s.lowercased() {
        case "main": self = .main
        case "primary": self = .primary
        case "smallest": self = .smallest
        case "largest": self = .largest
        default: self = .main
        }
    }
}

extension ScreenSelector: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .main: try container.encode("main")
        case .primary: try container.encode("primary")
        case .index(let n): try container.encode(n)
        case .smallest: try container.encode("smallest")
        case .largest: try container.encode("largest")
        }
    }
}