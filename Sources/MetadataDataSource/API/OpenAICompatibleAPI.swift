import Domain
import Foundation

public struct OpenAICompatibleAPI: Sendable {
    let config: AIEndpoint

    public init(config: AIEndpoint) {
        self.config = config
    }
}

extension OpenAICompatibleAPI {
    public func chatCompletion(rawTitle: String, rawArtist: String) throws -> URLRequest {
        let endpoint = normalizedEndpoint
        guard let url = URL(string: endpoint + "/chat/completions") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "user", "content": prompt(rawTitle: rawTitle, rawArtist: rawArtist)]
            ],
            "temperature": 0,
            "response_format": ["type": "json_object"],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    var normalizedEndpoint: String {
        config.endpoint.hasSuffix("/")
            ? String(config.endpoint.dropLast())
            : config.endpoint
    }
}

extension OpenAICompatibleAPI {
    fileprivate func prompt(rawTitle: String, rawArtist: String) -> String {
        """
        Extract the canonical song title and the performing artist from the metadata below.

        Title: \(rawTitle)
        Artist: \(rawArtist)

        Both fields may contain noise. The artist field may be a YouTube channel name, not the actual performer.

        Rules:
        1. Extract ONLY the actual song title (clean, canonical form).
        2. Extract the PERFORMING artist (not the YouTube channel/uploader).
        3. Use the artist field as a hint, but prefer information embedded in the title if it names the real artist.
        4. Japanese brackets like 『...』「...」 often wrap the song title. e.g. "Artist『SongTitle』" → title: "SongTitle", artist: "Artist".
        5. Anime/show names, episode markers (OP, ED, 主題歌) are NOT the song title — extract the actual song name.
        6. If the text indicates a cover (e.g. "Cover", "歌ってみた"):
           - Use the performer as the artist
           - Keep the original song title (remove "Cover")
        7. Remove all noise such as:
           - "Official", "MV", "PV", "Lyrics", "HD", "4K", "THE FIRST TAKE"
           - 高音質, 高画質, 作業用BGM, 歌詞付き, Full, Full Ver., Short Ver., TV Size
           - HDリマスター, リマスター, Remastered
        8. Normalize spacing and symbols.
        9. Preserve original language (do not translate).

        Output STRICT JSON only:
        {"title": "...", "artist": "..."}

        If artist cannot be determined, use an empty string.
        """
    }
}
