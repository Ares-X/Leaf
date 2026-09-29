#!/usr/bin/env bash
# Build-time downloads only. No npm install, Node runtime, CDN or updater in Leaf.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
FOLIATE=78914aef4466eb960965702401634c2cb348e9b1
checkout() {
    local repository="$1" revision="$2" directory="$3"
    if [ ! -d "$directory/.git" ]; then git init -q "$directory"; git -C "$directory" remote add origin "$repository"; fi
    if ! git -C "$directory" cat-file -e "$revision^{commit}" 2>/dev/null; then git -C "$directory" fetch --depth 1 origin "$revision"; fi
    git -C "$directory" checkout -q --detach "$revision"
}
mkdir -p build/deps Sources/Leaf/Resources/Reader/foliate
checkout https://github.com/johnfactotum/foliate-js.git "$FOLIATE" "$ROOT/build/deps/foliate"
DEST=Sources/Leaf/Resources/Reader
# CHM needs Foliate's view/renderer only; ebook parsers are handled by MuPDF.
for file in view.js paginator.js fixed-layout.js utils.js; do
    cp "build/deps/foliate/$file" "$DEST/foliate/$file"
done
cp build/deps/foliate/LICENSE "$DEST/foliate/LICENSE"
printf 'foliate=%s\n' "$FOLIATE" > "$DEST/versions.txt"
echo "Reader dependencies prepared. Subsequent builds reuse their local copies."
