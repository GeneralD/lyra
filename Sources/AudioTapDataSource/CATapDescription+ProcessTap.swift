import CoreAudio
import Foundation

/// Builds a private, unmuted stereo-mixdown tap descriptor and the aggregate
/// device that would host it. Both are plain data construction — no hardware
/// is touched — so they live as `CATapDescription` extensions rather than
/// free-floating static helpers.
@available(macOS 14.4, *)
extension CATapDescription {
    /// The tap is private (invisible in Audio MIDI Setup) and keeps the
    /// tapped app audible — the analyzer observes, never mutes.
    convenience init(privateStereoMixdownOf processObjects: [AudioObjectID]) {
        self.init(stereoMixdownOfProcesses: processObjects)
        isPrivate = true
        muteBehavior = .unmuted
    }

    /// The private, auto-starting aggregate-device descriptor that would host
    /// this tap as its sole, drift-compensated sub-tap.
    var aggregateDeviceDescription: [String: Any] {
        [
            kAudioAggregateDeviceNameKey: "lyra-spectrum-tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]
    }
}
