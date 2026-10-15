import Foundation
import AppKit
import ServiceManagement

/// Login-item and launch behaviour settings.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private let wantsLaunchAtLoginKey = "wantsLaunchAtLogin"
    private let hideWindowAtLoginKey = "hideWindowAtLogin"

    /// Mirrors SMAppService's status; toggling registers/unregisters the login item.
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            defaults.set(launchAtLogin, forKey: wantsLaunchAtLoginKey)
            apply(launchAtLogin)
        }
    }

    /// When launched as a login item, keep the window closed and live in the menu bar.
    @Published var hideWindowAtLogin: Bool {
        didSet { defaults.set(hideWindowAtLogin, forKey: hideWindowAtLoginKey) }
    }

    @Published var statusMessage: String?

    /// Set during launch if macOS started us as a login item.
    private(set) var launchedAtLogin = false
    /// True once, until the window has been hidden on a login launch.
    var shouldHideWindowOnce: Bool { launchedAtLogin && hideWindowAtLogin && !didHideOnce }
    private var didHideOnce = false

    var isInApplicationsFolder: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    private init() {
        if defaults.object(forKey: hideWindowAtLoginKey) == nil { defaults.set(true, forKey: hideWindowAtLoginKey) }
        hideWindowAtLogin = defaults.bool(forKey: hideWindowAtLoginKey)
        launchAtLogin = SMAppService.mainApp.status == .enabled

        // Self-heal: if the user wanted launch-at-login but the registration was lost
        // (e.g. the bundle moved to /Applications), register again from the new location.
        if defaults.bool(forKey: wantsLaunchAtLoginKey), SMAppService.mainApp.status != .enabled {
            apply(true)
        }
    }

    // MARK: - Launch detection

    /// Call from applicationWillFinishLaunching, while the launch Apple Event is current.
    func detectLoginLaunch() {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == kCoreEventClass, event.eventID == kAEOpenApplication,
              let prop = event.paramDescriptor(forKeyword: keyAEPropData) else { return }
        launchedAtLogin = prop.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func markWindowHidden() { didHideOnce = true }

    // MARK: - SMAppService

    private func apply(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            statusMessage = nil
            DebugLog.write("SMAppService \(enabled ? "registered" : "unregistered") login item; status=\(SMAppService.mainApp.status.rawValue)")
        } catch {
            statusMessage = "Login item: \(error.localizedDescription)"
            DebugLog.write("SMAppService \(enabled ? "register" : "unregister") failed: \(error)")
        }
        let status = SMAppService.mainApp.status
        if status == .requiresApproval {
            statusMessage = "Approve Audio Mixer in System Settings → General → Login Items."
        }
        let actual = status == .enabled
        if actual != launchAtLogin { launchAtLogin = actual }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Install

    /// Copies the bundle to /Applications and relaunches from there.
    func moveToApplications() {
        let source = Bundle.main.bundleURL
        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(source.lastPathComponent)
        guard source != destination else { return }
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: source, to: destination)
        } catch {
            statusMessage = "Couldn't move to Applications: \(error.localizedDescription)"
            return
        }
        if launchAtLogin { try? SMAppService.mainApp.unregister() }   // the new copy re-registers itself
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        relaunch.arguments = ["-n", destination.path]
        try? relaunch.run()
        NSApp.terminate(nil)
    }
}
