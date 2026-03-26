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
