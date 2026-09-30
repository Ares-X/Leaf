#!/usr/bin/env bash
# Local checks only. No download, GitHub Actions, signing or publishing.
set -euo pipefail
cd "$(dirname "$0")/.."

# Linux can parse macOS-only branches too; this is NOT macOS SDK type checking.
for source in Sources/Leaf/*.swift; do
    swiftc -frontend -parse -target arm64-apple-macosx13.0 "$source"
done
swift test
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests/BuildTests -v
if command -v node >/dev/null; then
    node --input-type=module --check < Sources/Leaf/Resources/Reader/reader.js
    node --test Tests/ReaderTests/*.test.mjs
else
    echo "SKIPPED: CHM adapter tests require Node (test-time only)." >&2
fi
