public enum CharsetName: String {
    case latin
    case cyrillic
    case greek
    case symbols
    case cjk
}

extension CharsetName: Sendable, Codable, Hashable, CaseIterable {}
