import SwiftUI
import AppKit

@main
struct AudioMixerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var engine = MixerEngine.shared

    var body: some Scene {
        WindowGroup("Audio Mixer") {
            ContentView().environmentObject(engine)
        }
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Keep routing alive when the window is closed; click the Dock icon to bring it back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Tear down taps on quit so apps' audio returns to their original device.
    func applicationWillTerminate(_ notification: Notification) {
        MixerEngine.shared.shutdown()
    }
}
