#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(uname -s)" = Darwin ] || { echo "The .app requires the macOS SDK; swift test works on Linux." >&2; exit 1; }
CORE="${1:-}"
[ -z "$CORE" ] || [ "$CORE" = --core ] || { echo "Usage: $0 [--core]" >&2; exit 1; }
# Full builds prepare the CHM renderer and native engines; --core stays dependency-light.
if [ "$CORE" != --core ]; then
    ./scripts/bootstrap.sh
    command -v clit >/dev/null || { echo "Install build dependency: brew install convertlit" >&2; exit 1; }
    ./scripts/build-engines.sh
fi
swift build -c release -Xswiftc -Osize -Xlinker -dead_strip
BIN="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/Leaf.app/Contents"
rm -rf "$PWD/dist/Leaf.app"
mkdir -p "$APP/MacOS" "$APP/Resources"
ICONSET="$PWD/build/Leaf.iconset"
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Resources/Leaf.icns"
cp "$BIN/Leaf" "$APP/MacOS/Leaf"
strip -x "$APP/MacOS/Leaf"
# Keep one resource copy. CHMReader uses this path in an app, Bundle.module in swift run.
cp -R Sources/Leaf/Resources/Reader "$APP/Resources/Reader"
if [ "$CORE" != --core ]; then mkdir -p "$APP/Resources/Tools"; cp "$(command -v clit)" "$APP/Resources/Tools/clit"; chmod 755 "$APP/Resources/Tools/clit"; fi
python3 scripts/bundle.py "$APP" ${CORE:+"$CORE"}
codesign --force --sign - "$APP/.."
echo "Built dist/Leaf.app (ad-hoc signed local development build, not notarized)."
du -sh dist/Leaf.app
