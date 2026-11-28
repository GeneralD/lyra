import Dependencies
import Domain
import Foundation

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
    @Dependency(\.randomSource) private var randomSource

    init(config: DecodeEffect) {
        self.duration = config.duration
        self.pool = CharacterPool(charsets: config.charsets)
    }
}

extension DecodeEffectState {
    func startLoading(placeholderLength: Int = 12) {
        stop()
        isAnimating = true
        updateDisplay(randomString(count: placeholderLength))

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

        updateDisplay(randomString(count: text.count))

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
                    guard !remaining.isEmpty else { break }
                    let idx = remaining[randomSource.next(below: remaining.count)]
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
    private func finish() {
        stop()
    }

    private func updateDisplay(_ text: String) {
        displayText = text
        onUpdate?(text)
    }

    private func tickLoading() {
        updateDisplay(randomString(count: displayText.count))
    }

    private func tickDecode() {
        let chars = Array(targetText)
        updateDisplay(
            chars.enumerated()
                .map { lockedIndices.contains($0.offset) ? String($0.element) : String(randomCharacter()) }
                .joined()
        )
    }

    private func randomCharacter() -> Character {
        guard pool.count > 0 else { return "?" }
        return pool.character(at: randomSource.next(below: pool.count))
    }

    private func randomString(count: Int) -> String {
        String((0..<count).map { _ in randomCharacter() })
    }
}
