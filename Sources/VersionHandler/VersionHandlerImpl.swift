import Domain
import Foundation

public struct VersionHandlerImpl: VersionHandler {
    public init() {}

    public var version: String {
        guard let url = Bundle.module.url(forResource: "version", withExtension: "txt"),
            let content = try? String(contentsOf: url, encoding: .utf8)
        else { return "unknown" }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
