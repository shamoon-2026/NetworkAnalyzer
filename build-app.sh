#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Network Analyzer"
EXECUTABLE_NAME="NetworkAnalyzer"
BUILD_DIR=".build/release"
APP_BUNDLE="dist/${APP_NAME}.app"

echo "Building release binary..."
swift build -c release

echo "Assembling app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# SwiftPM resource bundle for NetworkAnalyzerCore (bundled OUI CSV) lands next to the executable.
RESOURCE_BUNDLE="$BUILD_DIR/NetworkAnalyzer_NetworkAnalyzerCore.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
fi

echo "Ad-hoc code signing..."
codesign --force --deep --sign - --entitlements NetworkAnalyzer.entitlements "$APP_BUNDLE"

echo "Done: $APP_BUNDLE"
