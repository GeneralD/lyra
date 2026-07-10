import CoreAudio
import Testing

@testable import AudioTapDataSource

@Suite("CATapDescription(privateStereoMixdownOf:)")
struct ProcessTapDescriptionTests {
    @Test("the descriptor is private and never mutes the tapped process")
    func isPrivateAndUnmuted() {
        guard #available(macOS 14.4, *) else { return }
        let description = CATapDescription(privateStereoMixdownOf: [42])
        #expect(description.isPrivate)
        #expect(description.muteBehavior == .unmuted)
    }
}

@Suite("CATapDescription.aggregateDeviceDescription")
struct AggregateDeviceDescriptionTests {
    @Test("lists itself as the sole, drift-compensated sub-tap")
    func listsItselfAsSubTap() {
        guard #available(macOS 14.4, *) else { return }
        let description = CATapDescription(privateStereoMixdownOf: [42])
        let descriptor = description.aggregateDeviceDescription
        #expect(descriptor[kAudioAggregateDeviceNameKey] as? String == "lyra-spectrum-tap")
        #expect(descriptor[kAudioAggregateDeviceIsPrivateKey] as? Bool == true)
        #expect(descriptor[kAudioAggregateDeviceTapAutoStartKey] as? Bool == true)
        let tapList = descriptor[kAudioAggregateDeviceTapListKey] as? [[String: Any]]
        #expect(tapList?.count == 1)
        #expect(tapList?.first?[kAudioSubTapUIDKey] as? String == description.uuid.uuidString)
        #expect(tapList?.first?[kAudioSubTapDriftCompensationKey] as? Bool == true)
    }
}
