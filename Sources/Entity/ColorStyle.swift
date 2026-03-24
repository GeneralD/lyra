public enum ColorStyle {
    case solid(String)
    case gradient([String])
}

extension ColorStyle: Sendable, Equatable {}

extension ColorStyle: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .solid(str)
            return
        }
        let arr = try container.decode([String].self)
        self = arr.count == 1 ? .solid(arr[0]) : .gradient(arr)
    }
}

extension ColorStyle: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .solid(let hex): try container.encode(hex)
        case .gradient(let hexes): try container.encode(hexes)
        }
    }
}
