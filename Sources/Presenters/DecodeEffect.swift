// Copyright (C) 2026 GeneralD (yumejustice@gmail.com)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

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
    private var timer: Timer?
    private var completionHandler: (() -> Void)?
    private let duration: Double
    private let pool: CharacterPool

    init(config: DecodeEffect) {
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
        completionHandler = onComplete
        updateDisplay(pool.random(count: text.count))

        let totalChars = text.count
        guard totalChars > 0 else {
            updateDisplay(text)
            finish()
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
                    let remaining = (0..<totalChars).filter { !self.lockedIndices.contains($0) }
                    guard let idx = remaining.randomElement() else { break }
                    self.lockedIndices.insert(idx)
                }

                self.tickDecode()

                guard self.lockedIndices.count >= totalChars else { return }
                self.updateDisplay(self.targetText)
                self.finish()
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
    fileprivate func finish() {
        let handler = completionHandler
        completionHandler = nil
        stop()
        handler?()
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