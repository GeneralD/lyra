#!/usr/bin/env swift
// Checks that every Swift file under Sources/ is named after a top-level type it declares (#372).
//
// Usage: swift scripts/lint-file-names.swift [root]   (root defaults to "Sources")
//
// A file passes when any of these holds:
//   1. its basename equals the name of a top-level type or typealias it declares;
//   2. its basename contains "+" (a `Type+Feature.swift` extension file);
//   3. its basename ends with "Registration" (DI wiring, may hold private stub types);
//   4. its basename is `X` + "API" and it declares `protocol X` under an `@API` attribute
//      (Papyrus generates the `XAPI` type that callers use);
//   5. it declares no top-level type at all (free functions, re-exports, extensions only).
// A type inside a top-level `#if` block counts as top-level, a backtick-escaped name is compared
// without its backticks, and comments and string-literal text declare nothing. Paths with a `Resources` component
// and hidden files (which SwiftPM does not compile) are skipped.
import Foundation

struct Declaration {
    let kind: String
    let name: String
    let attributes: [String]

    var isPapyrusAPI: Bool { kind == "protocol" && attributes.contains("@API") }
}

/// Modifiers, then the declaration keyword and name, once any leading attributes are removed.
let declarationPattern =
    #/(?:(?:public|internal|private|fileprivate|package|open|final|indirect|nonisolated)\s+)*(?<kind>class|struct|enum|protocol|actor|typealias)\s+`?(?<name>\w+)/#

let tripleQuote = "\"\"\""

/// Index just past the `"` that closes a one-line string literal whose text starts at `index`;
/// the line's end when the literal does not close on it.
func indexAfterString(in chars: [Character], from index: Int) -> Int {
    guard index < chars.count else { return chars.count }
    switch chars[index] {
    case "\\": return indexAfterString(in: chars, from: index + 2)
    case "\"": return index + 1
    default: return indexAfterString(in: chars, from: index + 1)
    }
}

/// The code on a line with comments and string-literal text removed, read left to right, plus the
/// block-comment depth (Swift nests them) and `"""` state the next line starts in. `/*`, `*/` and
/// `//` inside a string literal are text, and a string inside a block comment is comment.
func strippedCode(
    _ chars: [Character], from index: Int = 0, depth: Int, inText: Bool, kept: String = ""
) -> (code: String, depth: Int, inText: Bool) {
    guard index < chars.count else { return (kept, depth, inText) }
    let rest = chars[index...]
    switch (inText, depth > 0) {
    case (true, _):
        return rest.starts(with: tripleQuote)
            ? strippedCode(chars, from: index + 3, depth: depth, inText: false, kept: kept)
            : strippedCode(chars, from: index + 1, depth: depth, inText: true, kept: kept)
    case (false, true):
        let delta = rest.starts(with: "/*") ? 1 : rest.starts(with: "*/") ? -1 : 0
        return strippedCode(chars, from: index + (delta == 0 ? 1 : 2), depth: depth + delta, inText: false, kept: kept)
    case (false, false) where rest.starts(with: "//"):
        return (kept, 0, false)
    case (false, false) where rest.starts(with: "/*"):
        return strippedCode(chars, from: index + 2, depth: 1, inText: false, kept: kept)
    case (false, false) where rest.starts(with: tripleQuote):
        return strippedCode(chars, from: index + 3, depth: 0, inText: true, kept: kept + "\"\"")
    case (false, false) where chars[index] == "\"":
        let next = indexAfterString(in: chars, from: index + 1)
        return strippedCode(chars, from: next, depth: 0, inText: false, kept: kept + "\"\"")
    case (false, false):
        return strippedCode(chars, from: index + 1, depth: 0, inText: false, kept: kept + String(chars[index]))
    }
}

/// Index just past the `)` that closes the `(` at `index`, ignoring parentheses inside string literals;
/// nil when the arguments continue on a later line.
func indexAfterArguments(
    in chars: [Character], from index: Int, depth: Int = 0, inString: Bool = false, escaped: Bool = false
) -> Int? {
    guard index < chars.count else { return nil }
    let next = index + 1
    switch (inString, escaped, chars[index]) {
    case (true, true, _): return indexAfterArguments(in: chars, from: next, depth: depth, inString: true)
    case (true, false, "\\"): return indexAfterArguments(in: chars, from: next, depth: depth, inString: true, escaped: true)
    case (true, false, "\""): return indexAfterArguments(in: chars, from: next, depth: depth)
    case (true, false, _): return indexAfterArguments(in: chars, from: next, depth: depth, inString: true)
    case (false, _, "\""): return indexAfterArguments(in: chars, from: next, depth: depth, inString: true)
    case (false, _, "("): return indexAfterArguments(in: chars, from: next, depth: depth + 1)
    case (false, _, ")"): return depth == 1 ? next : indexAfterArguments(in: chars, from: next, depth: depth - 1)
    default: return indexAfterArguments(in: chars, from: next, depth: depth)
    }
}

/// The attributes a line starts with (`@MainActor`, `@available(*, message: "use bar()")`) and the text after them.
func leadingAttributes(of chars: [Character], from index: Int = 0, found: [String] = []) -> (attributes: [String], rest: String) {
    let start = chars[index...].firstIndex { !$0.isWhitespace } ?? chars.count
    guard start < chars.count, chars[start] == "@" else { return (found, String(chars[start...])) }
    let nameEnd = chars[(start + 1)...].firstIndex { !($0.isLetter || $0.isNumber || $0 == "_") } ?? chars.count
    let attributes = found + [String(chars[start..<nameEnd])]
    let hasArguments = nameEnd < chars.count && chars[nameEnd] == "("
    guard let next = hasArguments ? indexAfterArguments(in: chars, from: nameEnd) : nameEnd else { return (attributes, "") }
    return leadingAttributes(of: chars, from: next, found: attributes)
}

/// Lines with comments and string-literal text removed but their indentation kept, so neither
/// commented-out code nor text in a `"""` literal declares anything. A line left with no code is empty.
func uncommentedLines(_ lines: [String]) -> [String] {
    lines.reduce(into: (depth: 0, inText: false, result: [String]())) { state, line in
        let scanned = strippedCode(Array(line), depth: state.depth, inText: state.inText)
        let code = scanned.code.drop(while: \.isWhitespace)
        state.result.append(code.isEmpty ? "" : String(line.prefix(while: \.isWhitespace)) + code)
        state.depth = scanned.depth
        state.inText = scanned.inText
    }.result
}

/// Lines with the indentation of their enclosing top-level `#if` blocks removed, so a type inside
/// `#if os(macOS)` reads as top-level (swift-format indents each conditional block by 4 spaces).
func topLevelLines(_ lines: [String]) -> [String] {
    lines.reduce(into: (depth: 0, result: [String]())) { state, line in
        let outer = String(repeating: " ", count: 4 * max(state.depth - 1, 0))
        let closesBlock = state.depth > 0 && line.hasPrefix(outer + "#endif")
        let continuesBlock = state.depth > 0 && (line.hasPrefix(outer + "#else") || line.hasPrefix(outer + "#elseif"))
        let indent = String(repeating: " ", count: 4 * state.depth)
        let stripped =
            closesBlock || continuesBlock
            ? String(line.dropFirst(outer.count))
            : line.hasPrefix(indent) ? String(line.dropFirst(indent.count)) : line
        state.result.append(stripped)
        state.depth += closesBlock ? -1 : stripped.hasPrefix("#if") ? 1 : 0
    }.result
}

/// A line of an attribute list: an attribute, or a continuation of multi-line attribute arguments.
func isAttributeLine(_ line: String) -> Bool {
    line.hasPrefix("@") || line.first?.isWhitespace == true || line.hasPrefix(")") || line.hasPrefix("]")
}

func declarations(in source: String) -> [Declaration] {
    let lines = topLevelLines(
        uncommentedLines(source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)))
    return lines.indices.compactMap { index in
        guard let first = lines[index].first, !first.isWhitespace else { return nil }
        let (inline, rest) = leadingAttributes(of: Array(lines[index]))
        guard let match = rest.prefixMatch(of: declarationPattern) else { return nil }
        // Attribute lines stacked above the declaration, e.g. `@API` then a multi-line `@Headers([...])`.
        let above = lines[..<index].reversed().prefix(while: isAttributeLine).filter { $0.hasPrefix("@") }
        return Declaration(
            kind: String(match.output.kind),
            name: String(match.output.name),
            attributes: above.flatMap { leadingAttributes(of: Array($0)).attributes } + inline
        )
    }
}

func isAllowed(basename: String, declarations: [Declaration]) -> Bool {
    declarations.isEmpty
        || basename.contains("+")
        || basename.hasSuffix("Registration")
        || declarations.contains { $0.name == basename }
        || declarations.contains { $0.isPapyrusAPI && basename == $0.name + "API" }
}

let root = CommandLine.arguments.dropFirst().first ?? "Sources"
guard let enumerator = FileManager.default.enumerator(atPath: root) else {
    print("lint-file-names: cannot read \(root)/ (run from the repository root)")
    exit(1)
}

let paths = (enumerator.allObjects as? [String] ?? [])
    .filter { path in
        let components = path.split(separator: "/")
        return path.hasSuffix(".swift") && !components.contains("Resources") && !components.contains { $0.hasPrefix(".") }
    }
    .sorted()
    .map { "\(root)/\($0)" }

let violations = paths.compactMap { path -> String? in
    guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { return "\(path): cannot be read as UTF-8" }
    let basename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    let found = declarations(in: source)
    guard !isAllowed(basename: basename, declarations: found) else { return nil }
    return "\(path): no top-level type named \(basename) (declares \(found.map(\.name).joined(separator: ", ")))"
}

guard violations.isEmpty else {
    print(violations.joined(separator: "\n"))
    print("lint-file-names: \(violations.count) of \(paths.count) files are not named after a type they declare (#372)")
    exit(1)
}

print("lint-file-names: \(paths.count) files OK")
