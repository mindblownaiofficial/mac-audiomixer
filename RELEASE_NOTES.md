## Audio Mixer 1.0.0

Per-app audio output routing for macOS. Send Spotify to your mixer, Discord to your headset, and everything else wherever the system default points — each app gets its own output device and its own volume.

### Highlights
- **Route any app to any output device** — built on Core Audio process taps, no kernel extension or virtual driver
- **Per-app volume and live level meters**
- **Remembers assignments** per app, so routed apps go back to their device every launch
- **Menu bar quick-switcher** — change an app's device without opening the window
- **Launch at login** with optional start-hidden mode
- Liquid Glass UI on macOS 26+, material fallback on macOS 15

### Install
1. Download `Audio-Mixer-1.0.0-arm64.zip` and unzip it
2. Drag **Audio Mixer.app** to `/Applications`
3. First launch: **right-click → Open** (the app is signed but not notarized, so macOS shows an "unidentified developer" warning once)
4. The first time you route an app, allow **System Audio Recording** when macOS asks (System Settings → Privacy & Security → Screen & System Audio Recording)

### Requirements
- macOS 15 Sequoia or later
- Apple Silicon

### Known limitations
- Not notarized — first launch needs right-click → Open
- Apps appear in the list once they've played audio since launching; use "Show silent apps" to assign one ahead of time

---

## Audio Mixer 1.0.0 for Windows

The same per-app routing, now on Windows, in the Cutroom look.

### Highlights
- **Route any app to any output device**, using Windows' own per-app output setting: no driver, no audio capture, no added latency
- **Per-app volume and live level meters**
- **Routes survive restarts**: Windows stores them, so they keep working even when Audio Mixer is closed
- **Tray quick-switcher**: right-click the tray icon to move an app or change the system default output
- **Launch at login** with optional start-hidden mode
- **Reset all routes** returns every app to the system default

### Install
- **Installer:** run `Audio-Mixer-Setup-1.0.0.exe`. It installs for the current user only and needs no administrator rights.
- **Portable:** unzip `Audio-Mixer-1.0.0-windows.zip` and run `AudioMixer.exe`.

Closing the window keeps Audio Mixer in the tray. Quit from the tray menu.

### Requirements
- Windows 10 version 1903 or later, or Windows 11

### Known limitations
- Apps appear once they have opened an audio stream; turn on "Silent apps" to assign one that is not playing
- Apps running as administrator cannot be moved unless Audio Mixer is also run as administrator
- "System sounds" has a volume but no device of its own; it always follows the system default
