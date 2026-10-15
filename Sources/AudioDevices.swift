import Foundation
import CoreAudio

struct AudioDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let outputChannels: Int
}

enum AudioDevices {
    /// UID prefix for the private aggregate devices this app creates, so they never show up as targets.
    static let aggregateUIDPrefix = "com.kingswood.audiomixer.aggregate."

    static func outputDevices() -> [AudioDevice] {
        let ids = (try? CA.getArray(kSystemObject, .init(kAudioHardwarePropertyDevices), as: AudioObjectID.self)) ?? []
        return ids.compactMap { id in
            let channels = CA.channelCount(id, scope: kAudioObjectPropertyScopeOutput)
            guard channels > 0 else { return nil }
            guard let uid = CA.getString(id, .init(kAudioDevicePropertyDeviceUID)),
                  !uid.hasPrefix(aggregateUIDPrefix) else { return nil }
            let name = CA.getString(id, .init(kAudioObjectPropertyName)) ?? "Device \(id)"
            return AudioDevice(id: id, uid: uid, name: name, outputChannels: channels)
        }
    }

    static func defaultOutputID() -> AudioObjectID {
        (try? CA.get(kSystemObject, .init(kAudioHardwarePropertyDefaultOutputDevice), as: AudioObjectID.self)) ?? 0
    }

    static func setDefaultOutput(_ id: AudioObjectID) throws {
        try CA.set(kSystemObject, .init(kAudioHardwarePropertyDefaultOutputDevice), id)
    }
}
