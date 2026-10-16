import Foundation
import AppKit
import UniformTypeIdentifiers

/// Owns device/process discovery, persisted per-app assignments, and the live routes.
/// All access happens on the main thread (timers on the main run loop).
final class MixerEngine: ObservableObject {
    static let shared = MixerEngine()

    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var defaultDeviceUID: String = ""
    @Published private(set) var assignments: [String: String]   // app key -> device UID
    @Published private(set) var volumes: [String: Float]         // app key -> 0...1
    @Published private(set) var levels: [String: Float] = [:]    // app key -> meter 0...1
    @Published private(set) var routeErrors: [String: String] = [:]
    @Published var showSilentApps = false

    private var routes: [String: AppRoute] = [:]
    private var pendingRoutes: Set<String> = []
    private var failedAt: [String: Date] = [:]
    /// Core Audio calls can stall for seconds (HAL timeouts); never make them on the main thread.
    private let routeQueue = DispatchQueue(label: "com.kingswood.audiomixer.routes", qos: .userInitiated)
    private var icons: [String: NSImage] = [:]
    private var refreshTimer: Timer?
    private var meterTimer: Timer?

    private let defaults = UserDefaults.standard
    private let assignmentsKey = "assignments"
    private let volumesKey = "volumes"

    private init() {
        assignments = defaults.dictionary(forKey: assignmentsKey) as? [String: String] ?? [:]
        volumes = (defaults.dictionary(forKey: volumesKey) as? [String: Double] ?? [:]).mapValues { Float($0) }
        // First refresh after launch finishes so the window appears immediately.
        DispatchQueue.main.async { [weak self] in self?.refresh() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.refresh() }
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.updateLevels() }
        DebugLog.write("launched; default output = \(defaultDeviceUID)")
    }

    // MARK: - Derived state for the UI

    var visibleApps: [AudioApp] {
        apps.filter { showSilentApps || $0.isPlaying || assignments[$0.id] != nil }
    }

    func icon(for app: AudioApp) -> NSImage {
        if let cached = icons[app.id] { return cached }
        let image: NSImage
        if let path = app.bundlePath {
            image = NSWorkspace.shared.icon(forFile: path)
        } else if app.name == "System sounds",
                  let symbol = NSImage(systemSymbolName: "bell.badge.waveform.fill", accessibilityDescription: nil) {
            image = symbol.withSymbolConfiguration(.init(pointSize: 28, weight: .regular)) ?? symbol
        } else {
            image = NSWorkspace.shared.icon(for: .unixExecutable)
        }
        icons[app.id] = image
        return image
    }

    func deviceUID(for app: AudioApp) -> String { assignments[app.id] ?? "" }
    func deviceName(for app: AudioApp) -> String {
        devices.first { $0.uid == assignments[app.id] }?.name ?? "System default"
    }
    func volume(for app: AudioApp) -> Float { volumes[app.id] ?? 1 }
    func isRouted(_ app: AudioApp) -> Bool { routes[app.id] != nil }

    // MARK: - Actions

    func assign(_ app: AudioApp, toDeviceUID uid: String) {
        if uid.isEmpty { assignments[app.id] = nil } else { assignments[app.id] = uid }
        failedAt[app.id] = nil
        routeErrors[app.id] = nil
        defaults.set(assignments, forKey: assignmentsKey)
        reconcile()
    }

    func setVolume(_ app: AudioApp, _ value: Float) {
        volumes[app.id] = value
        routes[app.id]?.volume = value
        defaults.set(volumes.mapValues { Double($0) }, forKey: volumesKey)
    }

    func setDefaultOutput(uid: String) {
        guard let device = devices.first(where: { $0.uid == uid }) else { return }
        try? AudioDevices.setDefaultOutput(device.id)
        refresh()
    }

    func shutdown() {
        let live = Array(routes.values)
        routes.removeAll()
        routeQueue.sync { live.forEach { $0.stop() } }
    }

    // MARK: - Discovery & reconciliation

    func refresh() {
        devices = AudioDevices.outputDevices()
        let defaultID = AudioDevices.defaultOutputID()
        defaultDeviceUID = devices.first { $0.id == defaultID }?.uid ?? ""
        apps = AppGrouper.group(AudioProcesses.all())
        reconcile()
    }

    private func reconcile() {
        var keep = Set<String>()
        for app in apps {
            guard let uid = assignments[app.id],
                  let device = devices.first(where: { $0.uid == uid }) else { continue }
            keep.insert(app.id)

            let ids = Set(app.processObjectIDs)
            if let route = routes[app.id], route.device == device, route.processObjectIDs == ids { continue }
            if pendingRoutes.contains(app.id) { continue }

            // Back off after a failure so a denied permission doesn't re-prompt every second.
            if let failed = failedAt[app.id], Date().timeIntervalSince(failed) < 10 { continue }

            let previous = routes.removeValue(forKey: app.id)
            pendingRoutes.insert(app.id)
            let key = app.id, name = app.name, processIDs = app.processObjectIDs, volume = volume(for: app)

            routeQueue.async { [weak self] in
                previous?.stop()
                let result = Result {
                    try AppRoute(appKey: key, appName: name, processObjectIDs: processIDs, device: device, volume: volume)
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.pendingRoutes.remove(key)
                    switch result {
                    case .success(let route):
                        // The assignment may have changed while the route was being built.
                        if self.assignments[key] == device.uid {
                            self.routes[key] = route
                            self.routeErrors[key] = nil
                            self.failedAt[key] = nil
                            DebugLog.write("route OK: \(name) objects=\(processIDs) -> \(device.name) [\(device.uid)] ch=\(device.outputChannels)")
                        } else {
                            self.routeQueue.async { route.stop() }
                        }
                    case .failure(let error):
                        self.routeErrors[key] = error.localizedDescription
                        self.failedAt[key] = Date()
                        DebugLog.write("route FAILED: \(name) -> \(device.name): \(error.localizedDescription)")
                    }
                }
            }
        }
        for (key, route) in routes where !keep.contains(key) {
            routes[key] = nil
            routeQueue.async { route.stop() }
        }
    }

    func diagnostics(for app: AudioApp) -> String? { routes[app.id]?.diagnostics }

    private func updateLevels() {
        guard !routes.isEmpty || !levels.isEmpty else { return }
        var next: [String: Float] = [:]
        for (key, route) in routes {
            let peak = min(route.takePeak(), 1)
            next[key] = max(peak, (levels[key] ?? 0) * 0.8)
        }
        levels = next
    }
}

/// Append-only debug log at ~/Library/Logs/AudioMixer.log.
enum DebugLog {
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/AudioMixer.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
