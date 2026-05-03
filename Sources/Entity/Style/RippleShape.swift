public enum RippleShape {
    case circle
    case polygon(sides: Int, angle: Double)

    public static let `default` = RippleShape.circle

    public static let minimumPolygonSides = 3
    public static let maximumPolygonSides = 256
}

extension RippleShape: Sendable {}
extension RippleShape: Equatable {}

extension RippleShape: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case sides
        case angle
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
            let bare = try? single.decode(String.self)
        {
            self = try Self.decoded(typeName: bare, container: nil, fallbackContainer: single)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeName = try container.decode(String.self, forKey: .type)
        self = try Self.decoded(typeName: typeName, container: container, fallbackContainer: nil)
    }

    private static func decoded(
        typeName: String,
        container: KeyedDecodingContainer<CodingKeys>?,
        fallbackContainer: SingleValueDecodingContainer?
    ) throws -> RippleShape {
        switch typeName {
        case "circle":
            return .circle
        case "polygon":
            guard let container else {
                let context = DecodingError.Context(
                    codingPath: fallbackContainer?.codingPath ?? [],
                    debugDescription: "shape \"polygon\" requires a table with sides")
                throw DecodingError.dataCorrupted(context)
            }
            let rawSides = try container.decode(Int.self, forKey: .sides)
            guard rawSides >= Self.minimumPolygonSides, rawSides <= Self.maximumPolygonSides else {
                throw DecodingError.dataCorruptedError(
                    forKey: .sides, in: container,
                    debugDescription:
                        "polygon sides must be in \(Self.minimumPolygonSides)...\(Self.maximumPolygonSides), got \(rawSides)"
                )
            }
            let angle = try container.decodeIfPresent(FlexibleDouble.self, forKey: .angle)?.value ?? 0
            return .polygon(sides: rawSides, angle: angle)
        default:
            let context = DecodingError.Context(
                codingPath: container?.codingPath ?? fallbackContainer?.codingPath ?? [],
                debugDescription: "unknown shape \"\(typeName)\"")
            throw DecodingError.dataCorrupted(context)
        }
    }
}

extension RippleShape: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .circle:
            try container.encode("circle", forKey: .type)
        case .polygon(let sides, let angle):
            try container.encode("polygon", forKey: .type)
            try container.encode(sides, forKey: .sides)
            try container.encode(angle, forKey: .angle)
        }
    }
}
