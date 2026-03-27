import Foundation

extension URL {
    var isYouTube: Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "youtube.com" || host.hasSuffix(".youtube.com")
            || host == "youtu.be"
    }
}
