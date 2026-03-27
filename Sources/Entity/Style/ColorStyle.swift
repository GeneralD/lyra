public enum ColorStyle {
    case solid(ColorConfig)
    case gradient([ColorConfig])
}

extension ColorStyle: Sendable {}
extension ColorStyle: Equatable {}

extension ColorStyle: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let color = try? container.decode(ColorConfig.self) {
            self = .solid(color)
            return
        }
        let arr = try container.decode([ColorConfig].self)
        self = arr.count == 1 ? .solid(arr[0]) : .gradient(arr)
    }
}

extension ColorStyle: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .solid(let config): try container.encode(config.hex)
        case .gradient(let configs): try container.encode(configs.map(\.hex))
        }
    }
}
