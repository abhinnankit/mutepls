import CoreAudio
import Foundation

final class AudioMuteController {
    func toggleDefaultInputMute() throws -> Bool {
        let current = try defaultInputMuteState()
        let next = !current
        try setDefaultInputMuteState(next)
        NotificationCenter.default.post(name: .muteStateDidChange, object: nil)
        return next
    }

    func defaultInputMuteState() throws -> Bool {
        let deviceID = try defaultInputDeviceID()
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        guard status == noErr else {
            throw AudioMuteError.coreAudio("read mute state", status)
        }

        return muted != 0
    }

    func setDefaultInputMuteState(_ muted: Bool) throws {
        let deviceID = try defaultInputDeviceID()
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            throw AudioMuteError.muteUnsupported
        }

        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
        guard status == noErr else {
            throw AudioMuteError.coreAudio("set mute state", status)
        }
    }

    private func defaultInputDeviceID() throws -> AudioObjectID {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr else {
            throw AudioMuteError.coreAudio("get default input device", status)
        }

        guard deviceID != kAudioObjectUnknown else {
            throw AudioMuteError.noDefaultInputDevice
        }

        return deviceID
    }
}
