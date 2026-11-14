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
./build.sh            # builds build/Audio Mixer.app
./build.sh --install  # …and installs it to /Applications, then launches it
```

To have it start automatically, open the gear menu (toolbar or menu bar item) and turn on
**Launch at login**. With **Start hidden in menu bar** on, a login launch keeps the window
closed and just restores your routes in the background.

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

## Windows

`Windows/` holds a native Windows version with the same features and the Cutroom look
(dark ink panels, indigo accent, the header doubling as the title bar).

It does not capture audio. Windows already has a per-app output device setting (Settings →
System → Sound → Volume mixer); Audio Mixer drives that same setting, plus each app's own
volume and level meter, from one window and a tray menu. Routes are therefore stored by
Windows and keep working when Audio Mixer is closed. **Reset all routes** in the gear or tray
menu sends every app back to the system default.

### Requirements

- Windows 10 version 1903 or later, or Windows 11
- Nothing to install to build it: it compiles with the C# compiler that ships with Windows

### Build

```powershell
cd Windows
.\build.ps1                          # unsigned: dist\windows\Audio-Mixer-<version>-windows.zip and Audio-Mixer-Setup-<version>.exe
.\build.ps1 -SignThumbprint <sha1>   # also signs the app, uninstaller and installer
```

The installer step needs NSIS (`makensis.exe`); without it the script still produces the zip.

| File | Role |
| --- | --- |
| `Windows/src/Interop.cs` | Core Audio COM interfaces and the undocumented per-app routing factory |
| `Windows/src/AudioEngine.cs` | Background thread: devices, sessions, routing, volumes, meters |
| `Windows/src/ViewModels.cs` | State the window binds to |
| `Windows/src/App.cs` | Window, tray icon and menus, startup, QA switches |
| `Windows/src/Theme.xaml`, `MainWindow.xaml` | Cutroom styling and layout |
| `Windows/src/Visuals.cs` | Level meter, app icon art, icons of other apps |
| `Windows/src/Settings.cs` | Preferences, launch at login |
| `Windows/installer.nsi` | Per-user installer, no administrator rights |

A log is written to `%LOCALAPPDATA%\AudioMixer\AudioMixer.log`. `AudioMixer.exe --selftest out.txt`
lists the devices and audio apps it can see.
