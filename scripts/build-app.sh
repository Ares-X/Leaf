#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(uname -s)" = Darwin ] || { echo "The .app requires the macOS SDK; swift test works on Linux." >&2; exit 1; }
CORE="${1:-}"
[ -z "$CORE" ] || [ "$CORE" = --core ] || { echo "Usage: $0 [--core]" >&2; exit 1; }
./scripts/bootstrap.sh
if [ "$CORE" != --core ]; then ./scripts/build-engines.sh; fi
swift build -c release -Xswiftc -Osize -Xlinker -dead_strip
BIN="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/Leaf.app/Contents"
rm -rf "$PWD/dist/Leaf.app"
mkdir -p "$APP/MacOS" "$APP/Resources"
cp "$BIN/Leaf" "$APP/MacOS/Leaf"
strip -x "$APP/MacOS/Leaf"
# Keep one resource copy. BookReader uses this path in an app, Bundle.module in swift run.
cp -R Sources/Leaf/Resources/Reader "$APP/Resources/Reader"
python3 scripts/bundle.py "$APP" ${CORE:+"$CORE"}
codesign --force --sign - "$APP/.."
echo "Built dist/Leaf.app (ad-hoc signed local development build, not notarized)."
du -sh dist/Leaf.app
