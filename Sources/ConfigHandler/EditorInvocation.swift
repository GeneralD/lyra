import Domain
import Foundation

struct EditorInvocation: Equatable {
    var executable: String
    var arguments: [String]

    static func parsed(
        from source: String,
        executableResolver: (String) -> String?
    ) -> Result<EditorInvocation, ConfigFailure> {
        guard source.rangeOfCharacter(from: .newlines) == nil else {
            return .failure(.failed(detail: "$EDITOR must not contain newline characters"))
        }

        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.failed(detail: "$EDITOR is not set. Set it with: export EDITOR=vim"))
        }

        switch words(from: trimmed) {
        case .success(let words):
            guard let executableName = words.first, !executableName.isEmpty else {
                return .failure(.failed(detail: "$EDITOR does not contain an executable command"))
            }

            let executable: String
            if executableName.contains("/") {
                executable = executableName
            } else if let resolved = executableResolver(executableName) {
                executable = resolved
            } else {
                return .failure(.failed(detail: "Editor executable not found: \(executableName)"))
            }

            return .success(Self(executable: executable, arguments: Array(words.dropFirst())))
        case .failure(let error):
            return .failure(error)
        }
    }

    private static func words(from source: String) -> Result<[String], ConfigFailure> {
        var words: [String] = []
        var word = ""
        var quotedBy: Character?
        var escaping = false
        var hasWord = false

        for character in source {
            if escaping {
                word.append(character)
                escaping = false
                hasWord = true
                continue
            }

            if let quote = quotedBy {
                if character == quote {
                    quotedBy = nil
                    hasWord = true
                } else if quote == "\"", character == "\\" {
                    escaping = true
                    hasWord = true
                } else {
                    word.append(character)
                    hasWord = true
                }
                continue
            }

            if character == "\\" {
                escaping = true
                hasWord = true
            } else if character == "'" || character == "\"" {
                quotedBy = character
                hasWord = true
            } else if isWhitespace(character) {
                if hasWord {
                    words.append(word)
                    word = ""
                    hasWord = false
                }
            } else {
                word.append(character)
                hasWord = true
            }
        }

        guard !escaping else {
            return .failure(.failed(detail: "$EDITOR ends with an unfinished escape"))
        }
        guard quotedBy == nil else {
            return .failure(.failed(detail: "$EDITOR contains an unclosed quote"))
        }
        if hasWord {
            words.append(word)
        }
        return .success(words)
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespaces.contains($0) }
    }
}
