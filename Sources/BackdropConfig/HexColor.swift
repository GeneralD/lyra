import SwiftUI

public func parseHexColor(_ hex: String) -> Color {
    let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard h.count == 6 || h.count == 8,
          let value = UInt64(h, radix: 16) else { return .white }
    let r, g, b, a: Double
    switch h.count {
    case 8:
        r = Double((value >> 24) & 0xFF) / 255
        g = Double((value >> 16) & 0xFF) / 255
        b = Double((value >> 8) & 0xFF) / 255
        a = Double(value & 0xFF) / 255
    default:
        r = Double((value >> 16) & 0xFF) / 255
        g = Double((value >> 8) & 0xFF) / 255
        b = Double(value & 0xFF) / 255
        a = 1
    }
    return Color(red: r, green: g, blue: b, opacity: a)
}
