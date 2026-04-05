import Domain
import Foundation

public struct VersionHandlerImpl {
    public init() {}
}

extension VersionHandlerImpl: VersionHandler {
    public var version: String {
        guard let url = Bundle.module.url(forResource: "version", withExtension: "txt"),
            let content = try? String(contentsOf: url, encoding: .utf8)
        else { return "unknown" }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
