import Dependencies
import Domain
import Testing

@testable import MetadataDataSource

@Suite("LLMMetadataDataSourceImpl")
struct LLMMetadataDataSourceImplTests {
    @Test("Returns empty when AI is not configured")
    func unconfiguredReturnsEmpty() async {
        let dataSource = withDependencies {
            $0.appStyle = AppStyle(ai: nil)
        } operation: {
            LLMMetadataDataSourceImpl()
        }

        let result = await dataSource.resolve(track: Track(title: "Some Song", artist: "Some Artist"))
        #expect(result.isEmpty)
    }
}
