import Foundation

public struct ColorConfig: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = ColorConfig(red: 1, green: 1, blue: 1)
    public static let black = ColorConfig(red: 0, green: 0, blue: 0)
}

// MARK: - Hex String ↔ RGBA

extension ColorConfig {
    public init(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard let value = UInt64(h, radix: 16) else {
            self = .white
            return
        }
        switch h.count {
        case 3:
            self.init(
                red: Double((value >> 8) & 0xF) / 0xF,
                green: Double((value >> 4) & 0xF) / 0xF,
                blue: Double(value & 0xF) / 0xF)
        case 6:
            self.init(
                red: Double((value >> 16) & 0xFF) / 0xFF,
                green: Double((value >> 8) & 0xFF) / 0xFF,
                blue: Double(value & 0xFF) / 0xFF)
        case 8:
            self.init(
                red: Double((value >> 24) & 0xFF) / 0xFF,
                green: Double((value >> 16) & 0xFF) / 0xFF,
                blue: Double((value >> 8) & 0xFF) / 0xFF,
                alpha: Double(value & 0xFF) / 0xFF)
        default:
            self = .white
        }
    }

    public var hex: String {
        func toByte(_ value: Double) -> Int {
            Int(min(max(value * 0xFF, 0), 0xFF).rounded())
        }
        let r = toByte(red)
        let g = toByte(green)
        let b = toByte(blue)
        let a = toByte(alpha)
        return a == 255
            ? String(format: "#%02X%02X%02X", r, g, b)
            : String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}

// MARK: - HSB Conversion

extension ColorConfig {
    public var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let maxC = max(red, green, blue)
        let delta = maxC - min(red, green, blue)
        let hue: Double =
            delta == 0
            ? 0
            : maxC == red
                ? (((green - blue) / delta).truncatingRemainder(dividingBy: 6)) / 6
                : maxC == green
                    ? ((blue - red) / delta + 2) / 6
                    : ((red - green) / delta + 4) / 6
        let saturation = maxC == 0 ? 0 : delta / maxC
        return (hue < 0 ? hue + 1 : hue, saturation, maxC)
    }

    public init(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1) {
        let h = hue.truncatingRemainder(dividingBy: 1)
        let normalizedHue = h < 0 ? h + 1 : h
        let c = brightness * saturation
        let x = c * (1 - abs((normalizedHue * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let (r1, g1, b1): (Double, Double, Double) =
            switch normalizedHue {
            case 0..<1 / 6: (c, x, 0)
            case 1 / 6..<1 / 3: (x, c, 0)
            case 1 / 3..<1 / 2: (0, c, x)
            case 1 / 2..<2 / 3: (0, x, c)
            case 2 / 3..<5 / 6: (x, 0, c)
            default: (c, 0, x)
            }
        self.init(red: r1 + m, green: g1 + m, blue: b1 + m, alpha: alpha)
    }
}

// MARK: - ExpressibleByStringLiteral

extension ColorConfig: ExpressibleByStringLiteral {
    public init(stringLiteral hex: String) {
        self.init(hex: hex)
    }
}

// MARK: - Codable (hex string ↔ RGBA)

extension ColorConfig: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(hex: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}
