import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var engine: MixerEngine

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if engine.visibleApps.isEmpty {
                emptyState
            } else {
                List(engine.visibleApps) { app in
                    AppRow(app: app)
                        .listRowSeparator(.visible)
                }
                .listStyle(.inset)
            }
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 360)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.wave.2.fill").foregroundStyle(.secondary)
            Text("System default output").font(.headline)
            Picker("", selection: Binding(
                get: { engine.defaultDeviceUID },
                set: { engine.setDefaultOutput(uid: $0) }
            )) {
                ForEach(engine.devices) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 300)
            Spacer()
            Text("Apps set to “System default” follow this.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "waveform").font(.system(size: 36)).foregroundStyle(.tertiary)
            Text("No apps are playing audio right now.").foregroundStyle(.secondary)
            Text("Start playback somewhere, or turn on “Show silent apps” to assign an app ahead of time.")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Toggle("Show silent apps", isOn: $engine.showSilentApps)
                .toggleStyle(.switch).controlSize(.small)
            Spacer()
            Text("\(engine.visibleApps.filter(engine.isRouted).count) routed")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

struct AppRow: View {
    @EnvironmentObject private var engine: MixerEngine
    let app: AudioApp

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Image(nsImage: engine.icon(for: app))
                    .resizable().frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.body).lineLimit(1)
                    HStack(spacing: 4) {
                        Circle().fill(app.isPlaying ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 7, height: 7)
                        Text(app.isPlaying ? "Playing" : "Silent")
                        if engine.isRouted(app) {
                            Text("· routed").foregroundStyle(.blue)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .frame(width: 170, alignment: .leading)

                Picker("", selection: Binding(
                    get: { engine.deviceUID(for: app) },
                    set: { engine.assign(app, toDeviceUID: $0) }
                )) {
                    Text("System default").tag("")
                    Divider()
                    ForEach(engine.devices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .labelsHidden()
                .frame(width: 220)

                Slider(value: Binding(
                    get: { Double(engine.volume(for: app)) },
                    set: { engine.setVolume(app, Float($0)) }
                ), in: 0...1)
                .frame(minWidth: 90)
                .disabled(!engine.isRouted(app))
                .help(engine.isRouted(app) ? "Per-app volume" : "Volume is available once the app is routed to a device")

                LevelMeter(level: engine.levels[app.id] ?? 0)
                    .frame(width: 60, height: 8)
                    .help(engine.diagnostics(for: app) ?? "")
            }
            if let error = engine.routeErrors[app.id] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct LevelMeter: View {
    let level: Float   // linear peak 0...1

    private var fraction: CGFloat {
        guard level > 0 else { return 0 }
        let dB = 20 * log10(Double(level))
        return CGFloat(min(1, max(0, (dB + 60) / 60)))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(level > 0.9 ? Color.red : Color.green)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
    }
}
