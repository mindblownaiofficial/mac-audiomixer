import SwiftUI
import AppKit

@main
struct AudioMixerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var engine = MixerEngine.shared

    var body: some Scene {
        Window("Audio Mixer", id: "main") {
            ContentView().environmentObject(engine)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 560)

        MenuBarExtra("Audio Mixer", systemImage: "slider.horizontal.3") {
            MenuBarContent().environmentObject(engine)
        }
    }
}

/// Quick-switch menu in the menu bar: every visible app with a device submenu.
struct MenuBarContent: View {
    @EnvironmentObject private var engine: MixerEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if engine.visibleApps.isEmpty {
            Text("No apps playing audio")
        }
        ForEach(engine.visibleApps) { app in
            Menu {
                Button {
                    engine.assign(app, toDeviceUID: "")
                } label: {
                    Label("System default", systemImage: engine.deviceUID(for: app).isEmpty ? "checkmark" : "")
                }
                Divider()
                ForEach(engine.devices) { device in
                    Button {
                        engine.assign(app, toDeviceUID: device.uid)
                    } label: {
                        Label(device.name, systemImage: engine.deviceUID(for: app) == device.uid ? "checkmark" : "")
                    }
                }
            } label: {
                Text(app.name + (engine.isRouted(app) ? "  →  \(engine.deviceName(for: app))" : ""))
            }
        }
        Divider()
        Menu("System default output") {
            ForEach(engine.devices) { device in
                Button {
                    engine.setDefaultOutput(uid: device.uid)
                } label: {
                    Label(device.name, systemImage: engine.defaultDeviceUID == device.uid ? "checkmark" : "")
                }
            }
        }
        Divider()
        Button("Open Audio Mixer…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("o")
        Button("Quit Audio Mixer") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Keep routing alive when the window is closed; the menu bar item or Dock icon brings it back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil) }
        return true
    }

    /// Tear down taps on quit so apps' audio returns to their original device.
    func applicationWillTerminate(_ notification: Notification) {
        MixerEngine.shared.shutdown()
    }
}
