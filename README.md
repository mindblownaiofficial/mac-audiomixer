# Audio Mixer

Per-app audio output routing for macOS. Send Spotify to your mixer, Discord to your headset,
and everything else to wherever the system default points — each app gets its own output
device and its own volume.

No kernel extension, no virtual audio driver. It uses the Core Audio *process tap* API
(macOS 14.2+): the app's audio is captured, muted on its original device, and replayed on the
device you choose through a private aggregate device.

## Requirements

- macOS 15 or later (Apple Silicon build)
- Xcode Command Line Tools (`xcode-select --install`) — full Xcode is not needed

## Build & run

```bash
./build.sh
open "build/Audio Mixer.app"
```

The first time you route an app, macOS asks for **System Audio Recording** permission
(System Settings → Privacy & Security → Screen & System Audio Recording). Allow it.

## How it works

| File | Role |
| --- | --- |
| `Sources/AppRoute.swift` | One route = process tap + aggregate device + realtime IOProc copying tap → device with volume |
| `Sources/AudioProcesses.swift` | Enumerates Core Audio process objects and groups helper processes under their parent app |
| `Sources/AudioDevices.swift` | Output device enumeration, system default get/set |
| `Sources/MixerEngine.swift` | State, persistence (UserDefaults), reconciliation loop |
| `Sources/ContentView.swift` | SwiftUI window (glass cards, device pickers, meters) |
| `Sources/AudioMixerApp.swift` | App entry, menu bar extra, lifecycle |
| `Tools/make-icon.swift` | Renders `Resources/AppIcon.icns` at build time |

A menu bar item (sliders icon) lets you switch any app's device without opening the window.
The window uses Liquid Glass on macOS 26+ and falls back to materials on macOS 15.

Assignments are remembered per app bundle, so a routed app goes back to its device the next
time it launches. Quitting Audio Mixer releases all taps and audio returns to normal.

A log of route events is written to `~/Library/Logs/AudioMixer.log`.
