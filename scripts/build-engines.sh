#!/usr/bin/env bash
# macOS only. These are decoder libraries, never bundled command-line applications.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(uname -s)" = Darwin ] || { echo "Native macOS engines need the macOS SDK." >&2; exit 1; }
ROOT="$PWD"; OUT="$ROOT/build/engines"; MU="$ROOT/build/deps/mupdf"
REV=f030eda1e472268667805f438e38cee8f1da61f8
mkdir -p "$OUT" "$ROOT/build/deps"
if [ ! -d "$MU/.git" ]; then git init -q "$MU"; git -C "$MU" remote add origin https://github.com/ArtifexSoftware/mupdf.git; fi
if ! git -C "$MU" cat-file -e "$REV^{commit}" 2>/dev/null; then git -C "$MU" fetch --depth 1 origin "$REV"; fi
git -C "$MU" checkout -q --detach "$REV"
git -C "$MU" submodule update --init --recursive --depth 1
FLAGS=(-Os -fPIC -fvisibility=hidden -mmacosx-version-min=13.0)
# PDFKit handles PDF; Foliate handles flowing books; libarchive handles comics.
# Keep XPS, SVG and image codecs; omit duplicate readers, JS, OCR, office export and barcode code.
FEATURES='-DFZ_ENABLE_PDF=0 -DFZ_ENABLE_CBZ=0 -DFZ_ENABLE_OCR_OUTPUT=0 -DFZ_ENABLE_ODT_OUTPUT=0'
make -C "$MU" -j"$(sysctl -n hw.logicalcpu)" libs build=small OUT="$ROOT/build/mupdf" \
    html=no mujs=no extract=no tesseract=no barcode=no \
    XCFLAGS="${FLAGS[*]} $FEATURES"
cc "${FLAGS[@]}" -I"$MU/include" -c Native/MuPDF.c -o "$OUT/MuPDF.o"
c++ -dynamiclib -Wl,-dead_strip -mmacosx-version-min=13.0 "$OUT/MuPDF.o" \
    "$ROOT/build/mupdf/libmupdf.a" "$ROOT/build/mupdf/libmupdf-third.a" \
    -lm -lpthread -o "$OUT/MuPDF.dylib"
# Homebrew is a development dependency, not required on a reader's Mac after bundling.
# Install once: brew install pkgconf djvulibre chmlib jpeg-xl
command -v pkg-config >/dev/null || { echo "Install: brew install pkgconf djvulibre chmlib jpeg-xl" >&2; exit 1; }
DJVU="$(brew --prefix djvulibre)"; CHM="$(brew --prefix chmlib)"; JXL="$(brew --prefix jpeg-xl)"
export PKG_CONFIG_PATH="$DJVU/lib/pkgconfig:$JXL/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
cc "${FLAGS[@]}" -dynamiclib -Wl,-dead_strip Native/DjVu.c $(pkg-config --cflags --libs ddjvuapi) -o "$OUT/DjVu.dylib"
cc "${FLAGS[@]}" -dynamiclib -Wl,-dead_strip Native/CHM.c -I"$CHM/include" -L"$CHM/lib" -lchm -o "$OUT/CHM.dylib"
cc "${FLAGS[@]}" -dynamiclib -Wl,-dead_strip Native/JPEGXL.c $(pkg-config --cflags --libs libjxl) -o "$OUT/JPEGXL.dylib"
for name in MuPDF DjVu CHM JPEGXL; do
    install_name_tool -id "@rpath/$name.dylib" "$OUT/$name.dylib"
    strip -x "$OUT/$name.dylib"
done
brew info --json=v2 djvulibre chmlib jpeg-xl > "$ROOT/build/native-dependencies.json"
printf '%s\n' "$REV" > "$ROOT/build/mupdf-revision.txt"
echo "Built four on-demand engines. Run scripts/build-app.sh to make a self-contained bundle."
