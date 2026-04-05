import Foundation
import Testing

@testable import MetadataDataSource

@Suite("OpenAI Compatible Models")
struct OpenAIModelsTests {
    @Test("decodes ChatCompletionResponse")
    func decodeChatCompletion() throws {
        let json = """
            {
                "choices": [
                    {"message": {"content": "{\\"title\\":\\"Song\\",\\"artist\\":\\"Artist\\"}"}}
                ]
            }
            """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: json)
        #expect(response.choices.count == 1)
        #expect(response.choices[0].message.content.contains("Song"))
    }

    @Test("decodes ExtractedMetadata from content string")
    func decodeExtractedMetadata() throws {
        let json = """
            {"title": "Brave Shine", "artist": "Aimer"}
            """.data(using: .utf8)!

        let metadata = try JSONDecoder().decode(ExtractedMetadata.self, from: json)
        #expect(metadata.title == "Brave Shine")
        #expect(metadata.artist == "Aimer")
    }

    @Test("decodes empty choices array")
    func emptyChoices() throws {
        let json = """
            {"choices": []}
            """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: json)
        #expect(response.choices.isEmpty)
    }
}
