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

import Dependencies
import Domain
import Foundation

public struct LLMMetadataDataSourceImpl {
    @Dependency(\.configDataSource) private var configDataSource

    public init() {}
}

extension LLMMetadataDataSourceImpl: MetadataDataSource {
    public func resolve(track: Track) async -> [Track] {
        guard let ai = configDataSource.load()?.config.ai else { return [] }
        let aiConfig = AIEndpoint(endpoint: ai.endpoint, model: ai.model, apiKey: ai.apiKey)

        guard let metadata = await callAPI(config: aiConfig, rawTitle: track.title, rawArtist: track.artist),
            !metadata.title.isEmpty
        else { return [] }
        return [Track(title: metadata.title, artist: metadata.artist)]
    }
}

extension LLMMetadataDataSourceImpl {
    fileprivate func callAPI(config: AIEndpoint, rawTitle: String, rawArtist: String) async -> ExtractedMetadata? {
        let api = OpenAICompatibleAPI(config: config)
        guard let request = try? api.chatCompletion(rawTitle: rawTitle, rawArtist: rawArtist) else { return nil }

        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await URLSession.shared.data(for: request)
        } catch {
            fputs("lyra: AI extraction failed: \(error)\n", stderr)
            return nil
        }

        guard let httpResponse = urlResponse as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            let code = (urlResponse as? HTTPURLResponse)?.statusCode ?? -1
            fputs("lyra: AI extraction failed with HTTP \(code)\n", stderr)
            return nil
        }

        guard let response = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data),
            let content = response.choices.first?.message.content,
            let contentData = content.data(using: .utf8)
        else { return nil }

        return try? JSONDecoder().decode(ExtractedMetadata.self, from: contentData)
    }
}