#!/usr/bin/env bash
# Local checks only. No download, GitHub Actions, signing or publishing.
set -euo pipefail
cd "$(dirname "$0")/.."

# Linux can parse macOS-only branches too; this is NOT macOS SDK type checking.
for source in Sources/Leaf/*.swift; do
    swiftc -frontend -parse -target arm64-apple-macosx13.0 "$source"
done
swift test

# Optional syntax check only; CHM behavior belongs to the macOS integration pass.
if command -v node >/dev/null; then
    node --input-type=module --check < Sources/Leaf/Resources/Reader/reader.js
fi
