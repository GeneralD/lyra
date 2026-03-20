import Domain
import Foundation

// MARK: - CharacterPool

struct CharacterPool {
    private let characters: [Character]

    init(charsets: Set<CharsetName>) {
        characters = charsets.flatMap(\.allCharacters)
    }

    var random: Character { characters.randomElement() ?? "?" }

    func random(count: Int) -> String {
        String((0 ..< count).map { _ in random })
    }
}

private extension CharsetName {
    var allCharacters: [Character] {
        switch self {
        case .latin:    Array("ÄÖÜßÆØÅÐÞÀÁÂÃÈÉÊËÌÍÎÏÒÓÔÕÙÚÛÝŒàáâãäåæèéêëìíîïòóôõöùúûüý")
        case .cyrillic: scalars(in: 0x0410...0x042F, 0x0430...0x044F)
        case .greek:    scalars(in: 0x0391...0x03A9, 0x03B1...0x03C9)
        case .symbols:  Array("†‡§¶©®™±≠≈∞∆∑∏√∫◊♠♣♥♦")
        case .cjk:      scalars(in: 0x4E00...0x9FFF)
        }
    }

    func scalars(in ranges: ClosedRange<UInt32>...) -> [Character] {
        ranges.flatMap { $0.compactMap(UnicodeScalar.init).map(Character.init) }
    }
}

// MARK: - DecodeEffectState

@MainActor
final class DecodeEffectState {
    private(set) var displayText: String = ""
    private(set) var isAnimating: Bool = false
    var onUpdate: ((String) -> Void)?
    private var targetText: String = ""
    private var lockedIndices: Set<Int> = []
    private var timer: Timer?
    private let duration: Double
    private let pool: CharacterPool

    init(config: ResolvedDecodeEffectConfig) {
        self.duration = config.duration
        self.pool = CharacterPool(charsets: config.charsets)
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
        updateDisplay(pool.random(count: placeholderLength))

        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickLoading() }
        }
    }

    func decode(to text: String, onComplete: (() -> Void)? = nil) {
        stop()
        isAnimating = true
        targetText = text
        lockedIndices = []
        updateDisplay(pool.random(count: text.count))

        let totalChars = text.count
        guard totalChars > 0 else {
            updateDisplay(text)
            finish(onComplete)
            return
        }

        var elapsed: Double = 0
        let interval: Double = 0.03
        let animationDuration = duration
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                elapsed += interval
                let progress = min(elapsed / animationDuration, 1.0)
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

private extension DecodeEffectState {
    func finish(_ onComplete: (() -> Void)?) {
        stop()
        onComplete?()
    }

    func updateDisplay(_ text: String) {
        displayText = text
        onUpdate?(text)
    }

    func tickLoading() {
        updateDisplay(pool.random(count: displayText.count))
    }

    func tickDecode() {
        let chars = Array(targetText)
        updateDisplay(
            chars.enumerated()
                .map { lockedIndices.contains($0.offset) ? String($0.element) : String(pool.random) }
                .joined()
        )
    }
}
