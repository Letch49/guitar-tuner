#!/bin/bash
# Builds GuitarTuner.app into ./build
#
# Usage:
#   ./build.sh           build the .app
#   ./build.sh install   build and copy to /Applications
#   ./build.sh dmg       build and create a distributable build/GuitarTuner.dmg
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Compiling (release)..."
swift build -c release

APP="build/GuitarTuner.app"
echo "==> Assembling $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/GuitarTuner" "$APP/Contents/MacOS/GuitarTuner"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "Resources/MenuBarIcon@2x.png" "$APP/Contents/Resources/MenuBarIcon@2x.png"

echo "==> Signing (ad-hoc)..."
codesign --force --sign - "$APP"

for arg in "$@"; do
    case "$arg" in
        install)
            echo "==> Installing to /Applications ..."
            rm -rf "/Applications/GuitarTuner.app"
            cp -R "$APP" "/Applications/GuitarTuner.app"
            # Ad-hoc signature changes on every build, which makes macOS silently
            echo "Installed: /Applications/GuitarTuner.app (microphone permission reset)"
            ;;
        dmg)
            echo "==> Creating DMG ..."
            STAGE="build/dmg-stage"
            rm -rf "$STAGE" "build/GuitarTuner.dmg"
            mkdir -p "$STAGE"
            cp -R "$APP" "$STAGE/"
            ln -s /Applications "$STAGE/Applications"
            hdiutil create -volname "Guitar Tuner" -srcfolder "$STAGE" \
                -ov -format UDZO "build/GuitarTuner.dmg" -quiet
            rm -rf "$STAGE"
            echo "Created: build/GuitarTuner.dmg"
            ;;
    esac
done

echo ""
echo "Done! Run with:  open $APP"
