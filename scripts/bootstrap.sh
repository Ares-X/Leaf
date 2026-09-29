#!/usr/bin/env bash
# Build-time downloads only. No npm install, Node runtime, CDN or updater in Leaf.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
FOLIATE=78914aef4466eb960965702401634c2cb348e9b1
MARKED=15.0.12
checkout() {
    local repository="$1" revision="$2" directory="$3"
    if [ ! -d "$directory/.git" ]; then git init -q "$directory"; git -C "$directory" remote add origin "$repository"; fi
    if ! git -C "$directory" cat-file -e "$revision^{commit}" 2>/dev/null; then git -C "$directory" fetch --depth 1 origin "$revision"; fi
    git -C "$directory" checkout -q --detach "$revision"
}
mkdir -p build/deps Sources/Leaf/Resources/Reader/foliate/vendor
checkout https://github.com/johnfactotum/foliate-js.git "$FOLIATE" "$ROOT/build/deps/foliate"
DEST=Sources/Leaf/Resources/Reader
# Only the rendering library. Exclude demo UI, PDF.js and zip.js (native adapters supply those).
for file in build/deps/foliate/*.js; do
    case "$(basename "$file")" in reader.js|pdf.js|rollup*|eslint*) continue;; esac
    cp "$file" "$DEST/foliate/"
done
cp build/deps/foliate/vendor/fflate.js "$DEST/foliate/vendor/"
cp build/deps/foliate/LICENSE "$DEST/foliate/LICENSE"
# npm's versioned published tarball includes the compiled, dependency-free ES module.
TARBALL="build/deps/marked-$MARKED.tgz"
if [ ! -s "$TARBALL" ]; then curl -fL --retry 3 "https://registry.npmjs.org/marked/-/marked-$MARKED.tgz" -o "$TARBALL.tmp"; mv "$TARBALL.tmp" "$TARBALL"; fi
mkdir -p build/deps/marked
tar -xzf "$TARBALL" -C build/deps/marked
cp build/deps/marked/package/lib/marked.esm.js "$DEST/marked.js"
cp build/deps/marked/package/LICENSE.md "$DEST/Marked-LICENSE.md"
printf 'foliate=%s\nmarked=%s\n' "$FOLIATE" "$MARKED" > "$DEST/versions.txt"
echo "Reader dependencies prepared. Subsequent builds reuse their local copies."
