import SwiftUI

// MARK: - Main window

struct ContentView: View {
    @EnvironmentObject private var engine: MixerEngine
    @EnvironmentObject private var settings: AppSettings

    private var playing: [AudioApp] { engine.visibleApps.filter(\.isPlaying) }
    private var silent: [AudioApp] { engine.visibleApps.filter { !$0.isPlaying } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DefaultOutputCard()

                if let message = settings.statusMessage {
                    Label(message, systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                if engine.visibleApps.isEmpty {
                    emptyState
                } else {
                    if !playing.isEmpty {
                        AppSection(title: "Now playing", apps: playing)
                    }
                    if !silent.isEmpty {
                        AppSection(title: "Silent", apps: silent)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(WindowAccessor { window in
            // Launched as a login item with "start hidden": stay in the menu bar.
            if settings.shouldHideWindowOnce {
                settings.markWindowHidden()
                window.orderOut(nil)
            }
        })
        .modernWindowChrome()
        .frame(minWidth: 680, minHeight: 460)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $engine.showSilentApps) {
                    Label("Show silent apps", systemImage: engine.showSilentApps ? "eye" : "eye.slash")
                }
                .help("Also list apps that aren't playing audio right now")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    SettingsMenuItems()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Launch at login and install options")
            }
        }
        .navigationTitle("Audio Mixer")
        .navigationSubtitle(subtitle)
    }

    private var subtitle: String {
        let routed = engine.visibleApps.filter(engine.isRouted).count
        return routed == 0 ? "Nothing routed" : "\(routed) routed"
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No apps playing audio", systemImage: "waveform.slash")
        } description: {
            Text("Start playback somewhere, or show silent apps to assign one ahead of time.")
        } actions: {
            Button("Show silent apps") { engine.showSilentApps = true }
                .modernButton()
        }
        .padding(.top, 40)
    }
}

// MARK: - Default output

struct DefaultOutputCard: View {
    @EnvironmentObject private var engine: MixerEngine

    var body: some View {
        HStack(spacing: 14) {
            DeviceGlyph(name: engine.devices.first { $0.uid == engine.defaultDeviceUID }?.name ?? "", size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("System default output").font(.headline)
                Text("Apps set to “System default” follow this device.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)

            DevicePicker(
                selection: Binding(get: { engine.defaultDeviceUID }, set: { engine.setDefaultOutput(uid: $0) }),
                devices: engine.devices,
                includeSystemDefault: false
            )
        }
        .padding(16)
        .cardBackground(prominent: true)
    }
}

// MARK: - App list

struct AppSection: View {
    let title: String
    let apps: [AudioApp]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
                .padding(.leading, 4)
            VStack(spacing: 10) {
                ForEach(apps) { app in AppCard(app: app) }
            }
        }
    }
}

struct AppCard: View {
    @EnvironmentObject private var engine: MixerEngine
    let app: AudioApp

    private var routed: Bool { engine.isRouted(app) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(nsImage: engine.icon(for: app))
                    .resizable()
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.headline).lineLimit(1)
                    HStack(spacing: 6) {
                        StatusDot(active: app.isPlaying)
                        Text(app.isPlaying ? "Playing" : "Silent")
                        if routed {
                            Text("·")
                            Label("Routed", systemImage: "arrow.triangle.branch")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.tint)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .frame(minWidth: 140, alignment: .leading)

                Spacer(minLength: 12)

                DevicePicker(
                    selection: Binding(get: { engine.deviceUID(for: app) }, set: { engine.assign(app, toDeviceUID: $0) }),
                    devices: engine.devices,
                    includeSystemDefault: true
                )
            }

            if routed {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary).font(.caption)
                    VStack(spacing: 4) {
                        Slider(value: Binding(
                            get: { Double(engine.volume(for: app)) },
                            set: { engine.setVolume(app, Float($0)) }
                        ), in: 0...1)
                        .controlSize(.small)
                        LevelMeter(level: engine.levels[app.id] ?? 0)
                            .frame(height: 4)
                            .padding(.horizontal, 2)
                    }
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary).font(.caption)
                    Text("\(Int((engine.volume(for: app) * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                .padding(.leading, 54)
            }

            if let error = engine.routeErrors[app.id] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .lineLimit(3)
                    .padding(.leading, 54)
            }
        }
        .padding(14)
        .cardBackground(prominent: false)
    }
}

// MARK: - Shared controls

/// Menu-style device chooser rendered as a glass/bordered pill.
struct DevicePicker: View {
    @Binding var selection: String
    let devices: [AudioDevice]
    let includeSystemDefault: Bool

    private var currentName: String {
        if selection.isEmpty { return includeSystemDefault ? "System default" : "—" }
        return devices.first { $0.uid == selection }?.name ?? "Unavailable device"
    }

    var body: some View {
        Menu {
            if includeSystemDefault {
                Button {
                    selection = ""
                } label: {
                    Label("System default", systemImage: selection.isEmpty ? "checkmark" : "")
                }
                Divider()
            }
            ForEach(devices) { device in
                Button {
                    selection = device.uid
                } label: {
                    Label(device.name, systemImage: selection == device.uid ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 6) {
                DeviceGlyph(name: selection.isEmpty ? "" : currentName, size: 14, plain: true)
                Text(currentName).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 240)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .modernButton()
    }
}

/// Picks an SF Symbol for a device based on its name.
struct DeviceGlyph: View {
    let name: String
    var size: CGFloat
    var plain = false

    private var symbol: String {
        let n = name.lowercased()
        if n.isEmpty { return "circle.dotted" }
        if ["headphone", "headset", "hyperx", "airpods", "buds", "beats"].contains(where: n.contains) { return "headphones" }
        if ["display", "hdmi", "monitor", "arzopa", "lg ", "dell", "samsung"].contains(where: n.contains) { return "display" }
        if ["mixer", "maono", "focusrite", "scarlett", "interface", "rode", "elgato"].contains(where: n.contains) { return "slider.vertical.3" }
        if n.contains("teams") || n.contains("zoom") || n.contains("virtual") { return "waveform.circle" }
        return "hifispeaker.fill"
    }

    var body: some View {
        if plain {
            Image(systemName: symbol).font(.system(size: size, weight: .medium))
        } else {
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(
                    LinearGradient(colors: [.accentColor, .accentColor.opacity(0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                )
        }
    }
}

struct StatusDot: View {
    let active: Bool
    var body: some View {
        Circle()
            .fill(active ? Color.green : Color.secondary.opacity(0.35))
            .frame(width: 7, height: 7)
            .shadow(color: active ? .green.opacity(0.6) : .clear, radius: 3)
    }
}

/// dB-scaled peak meter: -60 dBFS … 0 dBFS → empty … full.
struct LevelMeter: View {
    let level: Float

    private var fraction: CGFloat {
        guard level > 0 else { return 0 }
        let dB = 20 * log10(Double(level))
        return CGFloat(min(1, max(0, (dB + 60) / 60)))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [.green, .green, .yellow, .red],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width)
                    .mask(alignment: .leading) {
                        Capsule().frame(width: max(0, geo.size.width * fraction))
                    }
            }
        }
    }
}

// MARK: - Liquid Glass with graceful fallback

extension View {
    /// Card surface: Liquid Glass on macOS 26+, material elsewhere.
    @ViewBuilder
    func cardBackground(prominent: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if #available(macOS 26, *) {
            // Glass goes on an empty background layer: content rendered *inside* a glassEffect
            // (sliders, animated meters, tinted labels) comes out mirrored or as magenta tiles.
            self.background {
                Color.clear
                    .glassEffect(prominent ? .regular.tint(.accentColor.opacity(0.12)) : .regular, in: shape)
            }
        } else {
            self
                .background(prominent ? AnyShapeStyle(.thickMaterial) : AnyShapeStyle(.regularMaterial), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.08)))
        }
    }

    @ViewBuilder
    func modernButton() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Translucent window with the toolbar floating over content.
    func modernWindowChrome() -> some View {
        self
            .containerBackground(.thinMaterial, for: .window)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

/// Hands the hosting NSWindow to a callback once the view is in a window.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
