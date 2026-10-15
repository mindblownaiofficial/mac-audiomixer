#!/bin/zsh
# Builds Audio Mixer into build/Audio Mixer.app using only the command line tools (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Audio Mixer.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 \
  -target arm64-apple-macos15.0 \
  -parse-as-library \
  -module-name AudioMixer \
  -framework CoreAudio -framework AudioToolbox -framework AppKit -framework SwiftUI \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/AudioMixer"

cp Info.plist "$APP/Contents/Info.plist"

# App icon (rendered from Tools/make-icon.swift, cached in Resources/)
if [ ! -f Resources/AppIcon.icns ]; then
  mkdir -p Resources
  swiftc -O Tools/make-icon.swift -o build/make-icon
  build/make-icon build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "Built: $PWD/$APP"

# ./build.sh --install  → copy into /Applications and (re)launch from there
if [[ "${1:-}" == "--install" ]]; then
  pkill -x AudioMixer 2>/dev/null || true
  sleep 0.5
  rm -rf "/Applications/Audio Mixer.app"
  cp -R "$APP" "/Applications/Audio Mixer.app"
  open "/Applications/Audio Mixer.app"
  echo "Installed: /Applications/Audio Mixer.app"
fi
