#!/bin/bash
# Builds build/VoiceChanger.app. Set CODESIGN_IDENTITY to a signing identity to keep the
# microphone permission across rebuilds; the default ad-hoc signature re-prompts each time.
# Set VERSION to stamp the app version; otherwise the latest git tag is used if one exists.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP="build/VoiceChanger.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/VoiceChanger" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || true)}"
VERSION="${VERSION#v}"
if [ -n "$VERSION" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
codesign --force --sign "${CODESIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
