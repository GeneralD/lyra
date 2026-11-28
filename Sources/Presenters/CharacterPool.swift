import Domain
import Foundation

struct CharacterPool {
    let characters: [Character]

    init(charsets: Set<CharsetName>) {
        characters = charsets.flatMap(\.allCharacters)
    }

    var count: Int { characters.count }

    func character(at index: Int) -> Character { characters[index] }
}

extension CharsetName {
    fileprivate var allCharacters: [Character] {
        switch self {
        case .latin: Array("ÄÖÜßÆØÅÐÞÀÁÂÃÈÉÊËÌÍÎÏÒÓÔÕÙÚÛÝŒàáâãäåæèéêëìíîïòóôõöùúûüý")
        case .cyrillic: scalars(in: 0x0410...0x042F, 0x0430...0x044F)
        case .greek: scalars(in: 0x0391...0x03A9, 0x03B1...0x03C9)
        case .symbols: Array("†‡§¶©®™±≠≈∞∆∑∏√∫◊♠♣♥♦")
        case .cjk: scalars(in: 0x4E00...0x9FFF)
        }
    }

    fileprivate func scalars(in ranges: ClosedRange<UInt32>...) -> [Character] {
        ranges.flatMap { $0.compactMap(UnicodeScalar.init).map(Character.init) }
    }
}
