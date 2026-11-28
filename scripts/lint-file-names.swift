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
// Paths with a `Resources` component are skipped.
import Foundation

struct Declaration {
    let kind: String
    let name: String
    let attributes: [String]

    var isPapyrusAPI: Bool { kind == "protocol" && attributes.contains("@API") }
}

/// A top-level declaration: column 0, optional inline attributes and modifiers, then the kind and name.
let declarationPattern =
    #/(?<attributes>(?:@\w+(?:\([^)]*\))?\s+)*)(?:(?:public|internal|private|fileprivate|package|open|final|indirect|nonisolated)\s+)*(?<kind>class|struct|enum|protocol|actor|typealias)\s+(?<name>\w+)/#

/// Attribute names (`@API`, `@MainActor`, …) with their arguments stripped.
func attributeNames(in text: String) -> [String] {
    text.split(whereSeparator: \.isWhitespace)
        .filter { $0.hasPrefix("@") }
        .map { String($0.prefix { $0 != "(" }) }
}

func declarations(in source: String) -> [Declaration] {
    let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    return lines.indices.compactMap { index in
        guard let match = lines[index].prefixMatch(of: declarationPattern) else { return nil }
        // Attribute lines stacked directly above the declaration (e.g. `@API` then `@Headers(...)`).
        let attributeLines = lines[..<index].reversed().prefix { $0.hasPrefix("@") }
        return Declaration(
            kind: String(match.output.kind),
            name: String(match.output.name),
            attributes: (attributeLines + [String(match.output.attributes)]).flatMap(attributeNames(in:))
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
    .filter { $0.hasSuffix(".swift") && !$0.split(separator: "/").contains("Resources") }
    .sorted()
    .map { "\(root)/\($0)" }

let violations = try paths.compactMap { path -> String? in
    let basename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    let found = declarations(in: try String(contentsOfFile: path, encoding: .utf8))
    guard !isAllowed(basename: basename, declarations: found) else { return nil }
    return "\(path): no top-level type named \(basename) (declares \(found.map(\.name).joined(separator: ", ")))"
}

guard violations.isEmpty else {
    print(violations.joined(separator: "\n"))
    print("lint-file-names: \(violations.count) of \(paths.count) files are not named after a type they declare (#372)")
    exit(1)
}

print("lint-file-names: \(paths.count) files OK")
