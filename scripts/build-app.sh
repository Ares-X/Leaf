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
APP="$PWD/dist/Sumra.app/Contents"
rm -rf "$PWD/dist/Sumra.app"
mkdir -p "$APP/MacOS" "$APP/Resources"

ICON_SOURCE="$PWD/Assets/AppIcon"
LIGHT_ICONSET="$PWD/build/Sumra-Light.iconset"
DARK_ICONSET="$PWD/build/Sumra-Dark.iconset"

make_iconset() {
    local source="$1"
    local output="$2"
    [ -f "$source" ] || { echo "Missing app icon source: $source" >&2; exit 1; }
    rm -rf "$output"
    mkdir -p "$output"
    sips -z 16 16 "$source" --out "$output/icon_16x16.png" >/dev/null
    sips -z 32 32 "$source" --out "$output/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$source" --out "$output/icon_32x32.png" >/dev/null
    sips -z 64 64 "$source" --out "$output/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$source" --out "$output/icon_128x128.png" >/dev/null
    sips -z 256 256 "$source" --out "$output/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$source" --out "$output/icon_256x256.png" >/dev/null
    sips -z 512 512 "$source" --out "$output/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$source" --out "$output/icon_512x512.png" >/dev/null
    cp "$source" "$output/icon_512x512@2x.png"
}

make_iconset "$ICON_SOURCE/Sumra-Light.png" "$LIGHT_ICONSET"
make_iconset "$ICON_SOURCE/Sumra-Dark.png" "$DARK_ICONSET"
iconutil -c icns "$LIGHT_ICONSET" -o "$APP/Resources/Sumra-Light.icns"
iconutil -c icns "$DARK_ICONSET" -o "$APP/Resources/Sumra-Dark.icns"

cp "$BIN/Leaf" "$APP/MacOS/Leaf"
strip -x "$APP/MacOS/Leaf"
# Keep one resource copy. CHMReader uses this path in an app, Bundle.module in swift run.
cp -R Sources/Leaf/Resources/Reader "$APP/Resources/Reader"
if [ "$CORE" != --core ]; then mkdir -p "$APP/Resources/Tools"; cp "$(command -v clit)" "$APP/Resources/Tools/clit"; chmod 755 "$APP/Resources/Tools/clit"; fi
python3 scripts/bundle.py "$APP" ${CORE:+"$CORE"}
codesign --force --sign - "$APP/.."
codesign --verify --deep --strict "$APP/.."
echo "Built dist/Sumra.app (ad-hoc signed local development build, not notarized)."
du -sh dist/Sumra.app
