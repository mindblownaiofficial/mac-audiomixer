import Foundation
import CoreAudio
import Darwin

/// One Core Audio "process object": a process that is a client of coreaudiod.
struct AudioProcess {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    let isRunningOutput: Bool
}

enum AudioProcesses {
    static func all() -> [AudioProcess] {
        let ids = (try? CA.getArray(kSystemObject, .init(kAudioHardwarePropertyProcessObjectList), as: AudioObjectID.self)) ?? []
        return ids.compactMap { id in
            guard let pid: pid_t = try? CA.get(id, .init(kAudioProcessPropertyPID)) else { return nil }
            let bundle = CA.getString(id, .init(kAudioProcessPropertyBundleID))
            let running: UInt32 = (try? CA.get(id, .init(kAudioProcessPropertyIsRunningOutput))) ?? 0
            return AudioProcess(objectID: id,
                                pid: pid,
                                bundleID: (bundle?.isEmpty ?? true) ? nil : bundle,
                                isRunningOutput: running != 0)
        }
    }

    static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}

/// A user-facing application: all audio processes that live inside the same outermost .app bundle
/// (Chrome, Discord, etc. play audio from helper processes, not the main binary).
struct AudioApp: Identifiable {
    let id: String          // bundle identifier of the outer app, or a path-based fallback
    let name: String
    let bundlePath: String?
    var processObjectIDs: [AudioObjectID]
    var pids: [pid_t]
    var isPlaying: Bool
}

enum AppGrouper {
    /// System daemons that play audio but have no app bundle.
    static let friendlyDaemonNames: [String: String] = [
        "systemsoundserverd": "System sounds",
        "coreaudiod": "Core Audio",
        "avconferenced": "FaceTime / Continuity",
        "VoiceOver": "VoiceOver",
    ]

    static func group(_ processes: [AudioProcess]) -> [AudioApp] {
        var apps: [String: AudioApp] = [:]
        let me = getpid()

        for process in processes where process.pid != me {
            let exePath = AudioProcesses.executablePath(process.pid)
            let appPath = exePath.flatMap(outerAppBundle)

            let key: String
            let name: String
            if let appPath {
                let bundle = Bundle(path: appPath)
                key = bundle?.bundleIdentifier ?? appPath
                name = displayName(bundle, fallbackPath: appPath)
            } else if let bundleID = process.bundleID {
                key = bundleID
                name = exePath.map { ($0 as NSString).lastPathComponent } ?? bundleID
            } else if let exePath {
                key = exePath
                name = friendlyDaemonNames[(exePath as NSString).lastPathComponent] ?? (exePath as NSString).lastPathComponent
            } else {
                key = "pid-\(process.pid)"
                name = "Process \(process.pid)"
            }

            if var existing = apps[key] {
                existing.processObjectIDs.append(process.objectID)
                existing.pids.append(process.pid)
                existing.isPlaying = existing.isPlaying || process.isRunningOutput
                apps[key] = existing
            } else {
                apps[key] = AudioApp(id: key, name: name, bundlePath: appPath,
                                     processObjectIDs: [process.objectID], pids: [process.pid],
                                     isPlaying: process.isRunningOutput)
            }
        }
        return apps.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// "/Applications/Foo.app/Contents/Frameworks/.../Helpers/Foo Helper.app/Contents/MacOS/Foo Helper" -> "/Applications/Foo.app"
    static func outerAppBundle(_ path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return "/" + components[...index].joined(separator: "/")
    }

    private static func displayName(_ bundle: Bundle?, fallbackPath: String) -> String {
        if let bundle {
            if let display = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !display.isEmpty { return display }
            if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty { return name }
        }
        return ((fallbackPath as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}
