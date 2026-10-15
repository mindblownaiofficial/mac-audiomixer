import Foundation
import CoreAudio
import AudioToolbox

/// Routes one application's audio to a chosen output device.
///
/// Mechanism: a Core Audio process tap captures the app's output (and mutes it on its original
/// device), a private aggregate device bundles that tap with the target output device, and an
/// IOProc copies tap input -> device output with a volume scale applied.
final class AppRoute {
    let appKey: String
    let processObjectIDs: Set<AudioObjectID>
    let device: AudioDevice

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    /// Shared with the realtime IO thread:
    /// [0] volume, [1] peak since last read, [2] callback count,
    /// [3] tap channel count (the tap's channels are the LAST ones in the aggregate's input).
    private let shared: UnsafeMutablePointer<Float>

    var diagnostics: String {
        String(format: "%.0f callbacks · %.0f tap channels", shared[2], shared[3])
    }

    var volume: Float {
        get { shared[0] }
        set { shared[0] = newValue }
    }

    func takePeak() -> Float {
        let p = shared[1]
        shared[1] = 0
        return p
    }

    init(appKey: String, appName: String, processObjectIDs: [AudioObjectID], device: AudioDevice, volume: Float) throws {
        self.appKey = appKey
        self.processObjectIDs = Set(processObjectIDs)
        self.device = device
        shared = .allocate(capacity: 4)
        shared.initialize(repeating: 0, count: 4)
        shared[0] = volume
        do {
            try start(appName: appName)
        } catch {
            stop()
            shared.deallocate()
            throw error
        }
    }

    deinit {
        stop()
        shared.deallocate()
    }

    private func start(appName: String) throws {
        let description = CATapDescription(stereoMixdownOfProcesses: Array(processObjectIDs))
        description.name = "Audio Mixer – \(appName)"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior.mutedWhenTapped

        var tap = AudioObjectID(kAudioObjectUnknown)
        try CA.check(AudioHardwareCreateProcessTap(description, &tap),
                     "Creating audio tap for \(appName) (check System Settings → Privacy & Security → Screen & System Audio Recording)")
        tapID = tap

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Audio Mixer – \(appName) → \(device.name)",
            kAudioAggregateDeviceUIDKey: AudioDevices.aggregateUIDPrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: device.uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: device.uid]
            ],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: description.uuid.uuidString,
                 kAudioSubTapDriftCompensationKey: true]
            ],
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        try CA.check(AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate),
                     "Creating aggregate device for \(device.name)")
        aggregateID = aggregate
        DebugLog.write(describeStreams(of: aggregate))

        let tapFormat: AudioStreamBasicDescription? = try? CA.get(tapID, .init(kAudioTapPropertyFormat))
        let tapChannels = Int(tapFormat?.mChannelsPerFrame ?? 2)
        shared[3] = Float(tapChannels)

        let shared = self.shared
        var proc: AudioDeviceIOProcID?
        try CA.check(AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { _, input, _, output, _ in
            AppRoute.render(input: input, output: output, shared: shared)
        }, "Creating IO proc")
        ioProcID = proc
        if let proc { disableNonTapInputStreams(device: aggregate, proc: proc, tapChannels: tapChannels) }
        try CA.check(AudioDeviceStart(aggregate, proc), "Starting audio for \(device.name)")
    }

    /// The aggregate exposes the target device's *input* streams (its mic) ahead of the tap's.
    /// Turn those off for our IOProc so only the tap is delivered. Best effort: the render
    /// code still maps from the trailing tap channels if this fails.
    private func disableNonTapInputStreams(device: AudioObjectID, proc: AudioDeviceIOProcID, tapChannels: Int) {
        let streams = (try? CA.getArray(device, .init(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput), as: AudioObjectID.self)) ?? []
        guard streams.count > 1 else { return }
        let channelCounts = streams.map { st -> Int in
            let fmt: AudioStreamBasicDescription? = try? CA.get(st, .init(kAudioStreamPropertyVirtualFormat))
            return Int(fmt?.mChannelsPerFrame ?? 0)
        }
        // Walk from the end: streams that make up the tap's channels stay on.
        var isOn = [Bool](repeating: false, count: streams.count)
        var remaining = tapChannels
        for i in stride(from: streams.count - 1, through: 0, by: -1) where remaining > 0 {
            isOn[i] = true
            remaining -= channelCounts[i]
        }

        let address = AudioObjectPropertyAddress(kAudioDevicePropertyIOProcStreamUsage, scope: kAudioObjectPropertyScopeInput)
        guard let size = try? CA.size(device, address) else { return }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 8)
        defer { raw.deallocate() }
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: Int(size))
        let usage = raw.assumingMemoryBound(to: AudioHardwareIOProcStreamUsage.self)
        usage.pointee.mIOProc = unsafeBitCast(proc, to: UnsafeMutableRawPointer.self)
        var a = address
        var sz = size
        guard AudioObjectGetPropertyData(device, &a, 0, nil, &sz, raw) == noErr else {
            DebugLog.write("stream usage: get failed"); return
        }
        let count = min(Int(usage.pointee.mNumberStreams), isOn.count)
        let flags = withUnsafeMutablePointer(to: &usage.pointee.mStreamIsOn) {
            UnsafeMutableRawPointer($0).assumingMemoryBound(to: UInt32.self)
        }
        for i in 0..<count { flags[i] = isOn[i] ? 1 : 0 }
        let status = AudioObjectSetPropertyData(device, &a, 0, nil, sz, raw)
        DebugLog.write("stream usage set -> \(isOn) status=\(status)")
    }

    private func describeStreams(of device: AudioObjectID) -> String {
        var out = "aggregate \(device) streams:"
        for (scopeName, scope) in [("in", kAudioObjectPropertyScopeInput), ("out", kAudioObjectPropertyScopeOutput)] {
            let streams = (try? CA.getArray(device, .init(kAudioDevicePropertyStreams, scope: scope), as: AudioObjectID.self)) ?? []
            for st in streams {
                let start: UInt32 = (try? CA.get(st, .init(kAudioStreamPropertyStartingChannel))) ?? 0
                let term: UInt32 = (try? CA.get(st, .init(kAudioStreamPropertyTerminalType))) ?? 0
                let fmt: AudioStreamBasicDescription? = try? CA.get(st, .init(kAudioStreamPropertyVirtualFormat))
                let name = CA.getString(st, .init(kAudioObjectPropertyName)) ?? "-"
                let owner: AudioObjectID = (try? CA.get(st, .init(kAudioObjectPropertyOwner))) ?? 0
                out += String(format: "\n  %@ stream %u name=%@ owner=%u startCh=%u term=0x%x ch=%u rate=%.0f fmtID=%@",
                              scopeName, st, name, owner, start, term, fmt?.mChannelsPerFrame ?? 0, fmt?.mSampleRate ?? 0,
                              CoreAudioError.describe(OSStatus(bitPattern: fmt?.mFormatID ?? 0)))
            }
        }
        if let tapFmt: AudioStreamBasicDescription = try? CA.get(tapID, .init(kAudioTapPropertyFormat)) {
            out += String(format: "\n  tap %u format ch=%u rate=%.0f flags=0x%x", tapID, tapFmt.mChannelsPerFrame, tapFmt.mSampleRate, tapFmt.mFormatFlags)
        }
        let running: UInt32 = (try? CA.get(device, .init(kAudioDevicePropertyDeviceIsRunning))) ?? 99
        out += "\n  running=\(running)"
        return out
    }

    func stop() {
        if let proc = ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
        }
        ioProcID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    /// Realtime render: copy tap channels onto device channels (wrapping if counts differ),
    /// scale by volume and track peak. Float32 on both sides (the HAL's canonical format).
    private static func render(input: UnsafePointer<AudioBufferList>,
                               output: UnsafeMutablePointer<AudioBufferList>,
                               shared: UnsafeMutablePointer<Float>) {
        let inABL = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outABL = UnsafeMutableAudioBufferListPointer(output)

        var totalInputChannels = 0
        for buffer in inABL { totalInputChannels += Int(buffer.mNumberChannels) }
        shared[2] += 1

        let volume = shared[0]
        var peak = shared[1]
        var globalOutputChannel = 0
        let tapChannels = max(1, min(Int(shared[3]), totalInputChannels))
        let tapFirstChannel = totalInputChannels - tapChannels

        for outBuffer in outABL {
            let outChannels = Int(outBuffer.mNumberChannels)
            guard outChannels > 0, let outData = outBuffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let outFrames = Int(outBuffer.mDataByteSize) / (MemoryLayout<Float>.size * outChannels)

            for outChannel in 0..<outChannels {
                defer { globalOutputChannel += 1 }

                // Locate the matching input channel inside the (possibly multi-buffer) input list.
                var inData: UnsafeMutablePointer<Float>?
                var inChannels = 0
                var inFrames = 0
                var inOffset = tapFirstChannel + (globalOutputChannel % tapChannels)
                if totalInputChannels > 0 {
                    for inBuffer in inABL {
                        let c = Int(inBuffer.mNumberChannels)
                        if inOffset < c {
                            inData = inBuffer.mData?.assumingMemoryBound(to: Float.self)
                            inChannels = c
                            inFrames = Int(inBuffer.mDataByteSize) / (MemoryLayout<Float>.size * c)
                            break
                        }
                        inOffset -= c
                    }
                }

                var frame = 0
                if let src = inData, inChannels > 0 {
                    let n = min(outFrames, inFrames)
                    while frame < n {
                        let sample = src[frame * inChannels + inOffset] * volume
                        outData[frame * outChannels + outChannel] = sample
                        let magnitude = abs(sample)
                        if magnitude > peak { peak = magnitude }
                        frame += 1
                    }
                }
                while frame < outFrames {
                    outData[frame * outChannels + outChannel] = 0
                    frame += 1
                }
            }
        }
        shared[1] = peak
    }
}
