#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Leaf"
APP="dist/Leaf.app/Contents"; rm -rf dist/Leaf.app; mkdir -p "$APP/MacOS"
cp "$BIN" "$APP/MacOS/Leaf"; cp Packaging/Info.plist "$APP/Info.plist"
codesign --force --sign - "$APP/.." >/dev/null
echo "Built dist/Leaf.app"
