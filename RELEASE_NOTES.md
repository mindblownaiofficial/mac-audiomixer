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
