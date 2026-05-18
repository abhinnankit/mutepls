import CoreAudio
import Foundation

enum AudioMuteError: LocalizedError, CustomStringConvertible {
    case noDefaultInputDevice
    case muteUnsupported
    case coreAudio(String, OSStatus)

    var description: String {
        switch self {
        case .noDefaultInputDevice:
            return "No default input device is selected."
        case .muteUnsupported:
            return "The default input device does not expose a Core Audio mute control."
        case let .coreAudio(operation, status):
            return "Core Audio failed to \(operation). OSStatus: \(status)"
        }
    }

    var errorDescription: String? {
        description
    }
}
