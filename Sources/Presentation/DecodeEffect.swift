import Domain
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

@MainActor
final class DecodeEffectState {
    private(set) var displayText: String = ""
    private(set) var isAnimating: Bool = false
    var onUpdate: ((String) -> Void)?
    private var targetText: String = ""
    private var lockedIndices: Set<Int> = []
    private var timer: Timer?
    private let config: ResolvedDecodeEffectConfig

    init(config: ResolvedDecodeEffectConfig) {
        self.config = config
    }

    deinit {
        // Timer only weakly references self via [weak self] in closures,
        // so it will fire harmlessly after dealloc. No explicit invalidation
        // needed — callers are responsible for calling stop() before release.
    }
}

extension DecodeEffectState {
    func startLoading(placeholderLength: Int = 12) {
        stop()
        isAnimating = true
        updateDisplay((0 ..< placeholderLength).map { _ in String(config.randomCharacter()) }.joined())

        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickLoading() }
        }
    }

    func decode(to text: String, onComplete: (() -> Void)? = nil) {
        stop()
        isAnimating = true
        targetText = text
        lockedIndices = []
        updateDisplay(String(text.map { _ in config.randomCharacter() }))

        let totalChars = text.count
        guard totalChars > 0 else {
            updateDisplay(text)
            finish(onComplete)
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
                self.updateDisplay(self.targetText)
                self.finish(onComplete)
            }
        }
    }

    func set(_ text: String) {
        stop()
        updateDisplay(text)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isAnimating = false
    }
}

extension DecodeEffectState {
    private func finish(_ onComplete: (() -> Void)?) {
        stop()
        onComplete?()
    }

    private func updateDisplay(_ text: String) {
        displayText = text
        onUpdate?(text)
    }

    private func tickLoading() {
        updateDisplay(displayText.map { _ in String(config.randomCharacter()) }.joined())
    }

    private func tickDecode() {
        let chars = Array(targetText)
        updateDisplay(
            chars.enumerated()
                .map { lockedIndices.contains($0.offset) ? String($0.element) : String(config.randomCharacter()) }
                .joined()
        )
    }
}
