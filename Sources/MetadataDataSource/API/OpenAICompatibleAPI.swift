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
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt(rawTitle: rawTitle, rawArtist: rawArtist)],
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

    private var systemPrompt: String {
        """
        You are a music metadata expert with comprehensive knowledge of songs, artists, \
        and albums worldwide. You know the official/canonical names of artists and song \
        titles in their original languages. When given raw metadata from a music player, \
        you identify the actual song and return its correct, canonical metadata — not just \
        cleaned-up text, but the real names as they appear on official releases.
        """
    }

    private func userPrompt(rawTitle: String, rawArtist: String) -> String {
        """
        Identify the song and artist from the raw metadata below, then return their \
        canonical names.

        Title: \(rawTitle)
        Artist: \(rawArtist)

        Both fields may contain noise. The artist field may be a YouTube channel name, \
        not the actual performer.

        Rules:
        1. Return the OFFICIAL song title as it appears on the original release.
        2. Return the PERFORMING artist's official name (not the YouTube channel/uploader).
        3. Use the artist field as a hint, but prefer information embedded in the title \
        if it names the real artist.
        4. Japanese brackets like 『...』「...」 often wrap the song title. \
        e.g. "Artist『SongTitle』" → title: "SongTitle", artist: "Artist".
        5. Anime/show names, episode markers (OP, ED, 主題歌) are NOT the song title — \
        extract the actual song name.
        6. If the text indicates a cover (e.g. "Cover", "歌ってみた"):
           - Use the performer as the artist
           - Keep the original song title (remove "Cover")
        7. Remove all noise such as:
           - "Official", "MV", "PV", "Lyrics", "HD", "4K", "THE FIRST TAKE"
           - 高音質, 高画質, 作業用BGM, 歌詞付き, Full, Full Ver., Short Ver., TV Size
           - HDリマスター, リマスター, Remastered
        8. Use the song's ORIGINAL LANGUAGE for both title and artist:
           - Japanese songs → Japanese title and artist (e.g. "大塚愛", not "Ai Otsuka")
           - Korean songs → Korean title and artist
           - If romanized and native forms coexist (e.g. "しゃぼん玉 - Shabondama"), \
        keep only the native-script form
        9. Normalize spacing and symbols.

        Output STRICT JSON only:
        {"title": "...", "artist": "..."}

        If artist cannot be determined, use an empty string.
        """
    }
}
