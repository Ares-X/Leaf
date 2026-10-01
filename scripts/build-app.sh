#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(uname -s)" = Darwin ] || { echo "The .app requires the macOS SDK; swift test works on Linux." >&2; exit 1; }
CORE="${1:-}"
[ -z "$CORE" ] || [ "$CORE" = --core ] || { echo "Usage: $0 [--core]" >&2; exit 1; }
# Full builds compile native engines; CHM renderer modules are vendored in Resources.
if [ "$CORE" != --core ]; then
    command -v clit >/dev/null || { echo "Install build dependency: brew install convertlit" >&2; exit 1; }
    ./scripts/build-engines.sh
fi
swift test
swift build -c release -Xswiftc -Osize -Xlinker -dead_strip
BIN="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/Leaf.app/Contents"
rm -rf "$PWD/dist/Leaf.app"
mkdir -p "$APP/MacOS" "$APP/Resources"

LIGHT_ICONSET="$PWD/build/Surma-Light.iconset"
DARK_ICONSET="$PWD/build/Surma-Dark.iconset"
swift scripts/make-icon.swift "$LIGHT_ICONSET" light
swift scripts/make-icon.swift "$DARK_ICONSET" dark
iconutil -c icns "$LIGHT_ICONSET" -o "$APP/Resources/Surma-Light.icns"
iconutil -c icns "$DARK_ICONSET" -o "$APP/Resources/Surma-Dark.icns"

cp "$BIN/Leaf" "$APP/MacOS/Leaf"
strip -x "$APP/MacOS/Leaf"
# Keep one resource copy. CHMReader uses this path in an app, Bundle.module in swift run.
cp -R Sources/Leaf/Resources/Reader "$APP/Resources/Reader"
if [ "$CORE" != --core ]; then mkdir -p "$APP/Resources/Tools"; cp "$(command -v clit)" "$APP/Resources/Tools/clit"; chmod 755 "$APP/Resources/Tools/clit"; fi
python3 scripts/bundle.py "$APP" ${CORE:+"$CORE"}
codesign --force --sign - "$APP/.."
codesign --verify --deep --strict "$APP/.."
echo "Built dist/Leaf.app (ad-hoc signed local development build, not notarized)."
du -sh dist/Leaf.app
