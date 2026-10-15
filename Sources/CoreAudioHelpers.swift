import Foundation
import CoreAudio

/// Error wrapper for OSStatus results from the Core Audio HAL.
struct CoreAudioError: LocalizedError {
    let status: OSStatus
    let operation: String

    var errorDescription: String? { "\(operation) failed: \(Self.describe(status))" }

    static func describe(_ status: OSStatus) -> String {
        let n = UInt32(bitPattern: status)
        let bytes = [UInt8((n >> 24) & 0xff), UInt8((n >> 16) & 0xff), UInt8((n >> 8) & 0xff), UInt8(n & 0xff)]
        if bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }) {
            return "'\(String(decoding: bytes, as: UTF8.self))' (\(status))"
        }
        return "\(status)"
    }
}

extension AudioObjectPropertyAddress {
    init(_ selector: AudioObjectPropertySelector,
         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
         element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) {
        self.init(mSelector: selector, mScope: scope, mElement: element)
    }
}

let kSystemObject = AudioObjectID(kAudioObjectSystemObject)

/// Thin typed wrappers around AudioObjectGet/SetPropertyData.
enum CA {
    static func check(_ status: OSStatus, _ operation: @autoclosure () -> String) throws {
        if status != noErr { throw CoreAudioError(status: status, operation: operation()) }
    }

    static func size(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) throws -> UInt32 {
        var a = address
        var s: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &a, 0, nil, &s), "GetPropertyDataSize \(describe(address))")
        return s
    }

    static func get<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, as type: T.Type = T.self) throws -> T {
        var a = address
        var s = UInt32(MemoryLayout<T>.size)
        let p = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { p.deallocate() }
        try check(AudioObjectGetPropertyData(object, &a, 0, nil, &s, p), "GetPropertyData \(describe(address))")
        // move() takes ownership of a +1 CF object without an extra retain.
        return p.move()
    }

    static func getArray<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, as type: T.Type = T.self) throws -> [T] {
        var a = address
        var s = try size(object, address)
        let capacity = Int(s) / MemoryLayout<T>.stride
        if capacity == 0 { return [] }
        let p = UnsafeMutablePointer<T>.allocate(capacity: capacity)
        defer { p.deallocate() }
        try check(AudioObjectGetPropertyData(object, &a, 0, nil, &s, p), "GetPropertyData \(describe(address))")
        return Array(UnsafeBufferPointer(start: p, count: Int(s) / MemoryLayout<T>.stride))
    }

    static func getString(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
        let cf: CFString? = try? get(object, address, as: CFString?.self)
        return cf.map { $0 as String }
    }

    static func set<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) throws {
        var a = address
        var v = value
        try withUnsafePointer(to: &v) { p in
            try check(AudioObjectSetPropertyData(object, &a, 0, nil, UInt32(MemoryLayout<T>.size), p), "SetPropertyData \(describe(address))")
        }
    }

    /// Total channel count across all streams in the given scope (input or output).
    static func channelCount(_ object: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        let address = AudioObjectPropertyAddress(kAudioDevicePropertyStreamConfiguration, scope: scope)
        guard let s = try? size(object, address), s > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(s), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        var a = address
        var sz = s
        guard AudioObjectGetPropertyData(object, &a, 0, nil, &sz, raw) == noErr else { return 0 }
        let abl = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return abl.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func describe(_ address: AudioObjectPropertyAddress) -> String {
        CoreAudioError.describe(OSStatus(bitPattern: address.mSelector))
    }
}
