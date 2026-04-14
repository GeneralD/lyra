import Dependencies
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
        String((0..<count).map { _ in random })
    }
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

// MARK: - DecodeEffectState

@MainActor
final class DecodeEffectState {
    private(set) var displayText: String = ""
    private(set) var isAnimating: Bool = false
    var onUpdate: ((String) -> Void)?
    private var targetText: String = ""
    private var lockedIndices: Set<Int> = []
    private(set) var task: Task<Void, Never>?
    private let duration: Double
    private let pool: CharacterPool
    @Dependency(\.continuousClock) private var clock

    init(config: DecodeEffect) {
        self.duration = config.duration
        self.pool = CharacterPool(charsets: config.charsets)
    }
}

extension DecodeEffectState {
    func startLoading(placeholderLength: Int = 12) {
        stop()
        isAnimating = true
        updateDisplay(pool.random(count: placeholderLength))

        let clock = self.clock
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await clock.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled else { break }
                tickLoading()
            }
        }
    }

    func decode(to text: String, onComplete: (() -> Void)? = nil) {
        stop()
        isAnimating = true
        targetText = text
        lockedIndices = []

        guard duration > 0 else {
            updateDisplay(text)
            finish()
            onComplete?()
            return
        }

        updateDisplay(pool.random(count: text.count))

        let totalChars = text.count
        guard totalChars > 0 else {
            updateDisplay(text)
            finish()
            onComplete?()
            return
        }

        let clock = self.clock
        let animationDuration = duration
        task = Task { [weak self] in
            var elapsed: Double = 0
            let interval: Double = 0.03
            while !Task.isCancelled {
                try? await clock.sleep(for: .milliseconds(30))
                guard let self, !Task.isCancelled else { return }
                elapsed += interval
                let progress = min(elapsed / animationDuration, 1.0)
                let easedProgress = progress * progress * progress
                let targetLocked = Int(easedProgress * Double(totalChars))

                while lockedIndices.count < targetLocked {
                    let remaining = (0..<totalChars).filter { !lockedIndices.contains($0) }
                    guard let idx = remaining.randomElement() else { break }
                    lockedIndices.insert(idx)
                }

                tickDecode()

                guard lockedIndices.count >= totalChars else { continue }
                updateDisplay(targetText)
                finish()
                onComplete?()
                return
            }
        }
    }

    func set(_ text: String) {
        stop()
        updateDisplay(text)
    }

    func stop() {
        task?.cancel()
        task = nil
        isAnimating = false
    }
}

extension DecodeEffectState {
    fileprivate func finish() {
        stop()
    }

    fileprivate func updateDisplay(_ text: String) {
        displayText = text
        onUpdate?(text)
    }

    fileprivate func tickLoading() {
        updateDisplay(pool.random(count: displayText.count))
    }

    fileprivate func tickDecode() {
        let chars = Array(targetText)
        updateDisplay(
            chars.enumerated()
                .map { lockedIndices.contains($0.offset) ? String($0.element) : String(pool.random) }
                .joined()
        )
    }
}
