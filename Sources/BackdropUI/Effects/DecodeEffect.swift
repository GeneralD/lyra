import BackdropDomain
import Foundation

extension CharsetName {
    var characters: [Character] {
        switch self {
        case .latin: Array("ÄÖÜßÆØÅÐÞÀÁÂÃÈÉÊËÌÍÎÏÒÓÔÕÙÚÛÝŒàáâãäåæèéêëìíîïòóôõöùúûüý")
        case .cyrillic: Array("ЖЗИКЛМНПРСТУФХЦЧШЩЭЮЯжзиклмнпрстуфхцчшщэюя")
        case .greek: Array("αβγδεζηθικλμνξπρστυφχψωΑΒΓΔΕΖΗΘΙΚΛΜΝΞΠΡΣΤΥΦΧΨΩ")
        case .symbols: Array("†‡§¶©®™±≠≈∞∆∑∏√∫◊♠♣♥♦")
        }
    }
}

extension ResolvedDecodeEffectConfig {
    var allCharacters: [Character] {
        charsets.flatMap(\.characters)
    }

    func randomCharacter() -> Character {
        allCharacters.randomElement() ?? "?"
    }
}

/// Manages the decode animation state for a single string.
/// Characters flicker randomly, then lock into place with exponential acceleration.
@MainActor @Observable
public final class DecodeEffectState {
    public private(set) var displayText: String = ""
    private var targetText: String = ""
    private var lockedIndices: Set<Int> = []
    private var timer: Timer?
    private let config: ResolvedDecodeEffectConfig

    public init(config: ResolvedDecodeEffectConfig) {
        self.config = config
    }
}

extension DecodeEffectState {
    /// Start flickering with placeholder text while loading
    public func startLoading(placeholderLength: Int = 12) {
        stop()
        targetText = ""
        lockedIndices = []
        displayText = (0 ..< placeholderLength)
            .map { _ in String(config.randomCharacter()) }
            .joined()

        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickLoading() }
        }
    }

    /// Received the real text — begin decode animation
    public func decode(to text: String) {
        stop()
        targetText = text
        lockedIndices = []
        displayText = String(text.map { _ in config.randomCharacter() })

        let totalChars = text.count
        guard totalChars > 0 else {
            displayText = text
            return
        }

        var elapsed: Double = 0
        let interval: Double = 0.03
        let duration = config.duration
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                elapsed += interval
                let progress = min(elapsed / duration, 1.0)
                let easedProgress = progress * progress * progress
                let targetLocked = Int(easedProgress * Double(totalChars))

                while self.lockedIndices.count < targetLocked {
                    let remaining = (0 ..< totalChars).filter { !self.lockedIndices.contains($0) }
                    guard let idx = remaining.randomElement() else { break }
                    self.lockedIndices.insert(idx)
                }

                self.tickDecode()

                guard self.lockedIndices.count >= totalChars else { return }
                self.displayText = self.targetText
                self.stop()
            }
        }
    }

    /// Set text immediately without animation
    public func set(_ text: String) {
        stop()
        targetText = text
        displayText = text
        lockedIndices = Set(0 ..< text.count)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tickLoading() {
        displayText = displayText.map { _ in String(config.randomCharacter()) }.joined()
    }

    private func tickDecode() {
        let chars = Array(targetText)
        displayText = chars.enumerated()
            .map { lockedIndices.contains($0.offset) ? String($0.element) : String(config.randomCharacter()) }
            .joined()
    }
}
