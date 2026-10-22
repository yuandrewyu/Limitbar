#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Build Limitbar on a Mac with Xcode command line tools installed." >&2
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PROJECT_DIR/dist/Limitbar.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/Limitbar" "$APP_DIR/Contents/MacOS/Limitbar"
cp "$BIN_DIR/LimitbarBridge" "$APP_DIR/Contents/MacOS/LimitbarBridge"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod 755 "$APP_DIR/Contents/MacOS/Limitbar" "$APP_DIR/Contents/MacOS/LimitbarBridge"
/usr/bin/plutil -lint "$APP_DIR/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$APP_DIR/Contents/MacOS/LimitbarBridge"
/usr/bin/codesign --force --sign - "$APP_DIR"
/usr/bin/codesign --verify --strict "$APP_DIR"
echo "Built: $APP_DIR"
echo "Move it to /Applications before configuring the Claude bridge, so its path stays stable."
