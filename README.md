# Sumra

A small, native macOS reader. Open a file, read it, close it.

**Engine integration in progress — not a release or a claim of tested SumatraPDF parity.**
The current source replaces the prototype's hand-written ZIP/EPUB/FB2 parsers and
Calibre/unar conversions with mature decoders and a small native shell.

## Reading

Open/Finder/drop/recent files; native macOS multi-window/tabs (including tab detach/merge); contents; automatic multilingual TXT novel chapter detection; search; page/line navigation;
zoom; actual/fit page/fit width; paged/continuous; two-page and right-to-left reading; GIF playback;
font family/size, line height and margins for text and MuPDF reflowable books; full screen;
one bookmark per document; persistent page/text position; native welcome, preferences and compact status views.
PDF uses PDFKit and plain text uses NSTextView. Reflowable books use MuPDF; WebKit/Foliate is retained only for CHM.
There is no Electron, Chromium distribution, Node runtime, library database,
account, cloud sync, updater, telemetry or general-purpose plug-in framework.

## Format routes

This table tracks the [SumatraPDF format list](https://www.sumatrapdfreader.org/docs/Supported-document-formats).
It documents **implemented dispatch/adapters**, not successful end-to-end fixtures
for every format. Rare formats need the full build's decoder libraries.

| Files | Engine/path |
| --- | --- |
| PDF, PDF-compatible AI | PDFKit; password prompt for encrypted PDF |
| EPUB, MOBI, AZW/AZW1/AZW3/KF8, PRC | MuPDF |
| FB2, FB2Z, FBZ, ZFB2, FB2.ZIP | MuPDF |
| AZW4/Print Replica | Palm record adapter → embedded PDF → PDFKit |
| Palm DOC/PDB | MuPDF first, Palm DOC fallback; TealDoc/Plucker are not falsely decoded as Palm DOC |
| TCR | small Sumatra-derived legacy adapter → NSTextView |
| TXT, JS, JSON, XML, LOG, NFO, FILE_ID.DIZ, READ.ME | NSTextView; UTF-8 / Foundation encoding detection; TXT chapter outline uses structural CJK/English/Japanese patterns plus line-shape/document-consistency filtering |
| Microsoft Reader LIT | ConvertLIT helper → standard OEB/EPUB directory → MuPDF; DRM5 remains unsupported |
| Markdown | MuPDF/cmark-gfm |
| HTML, HTM, XHTML | MuPDF |
| CBZ, CBR, CB7, CBT, ZIP, RAR, 7Z, TAR | system libarchive → ImageIO/native image decoder |
| ORA | its merged image; not the individual layer files |
| DjVu, DJV | DjVuLibre, page-at-a-time |
| CHM | CHMLib entry reads + WebKit; HHC contents and local links |
| XPS, OXPS, XOD, DWFX, SVG | selective MuPDF build |
| PNG, JPEG/JFIF, GIF, TIFF, BMP/DIB, TGA, WebP, JPEG 2000 | ImageIO first, MuPDF fallback |
| JPEG XR: JXR, HDP, WDP | MuPDF codec; requires real-file verification |
| JPEG XL | libjxl; current adapter decodes the first frame |
| AVIF, HEIF/HEIC | ImageIO; availability and variants depend on the macOS codec |
| PS, PS.GZ, EPS, PJL, PostScript AI | Ghostscript, **external and optional**, as in Sumatra |

Image folders can also be read as comics. TIFF frames are treated as pages;
standalone GIFs can play/pause. DRM is not removed. PDB is Palm DOC/MOBI rather
than arbitrary Palm databases. The Print Replica adapter currently handles
uncompressed/PalmDOC-compressed records, not every possible Kindle container.
Publication JavaScript, CHM active content and arbitrary network resources are
not executed. Fixed-layout EPUB and CHM still need sample testing.

## What makes it small

- Format routing is centralized: longest extension first, then a small Sumatra-derived magic sniffer for mislabeled files.
- Native libraries are loaded only when their format is opened and released with the document.
- The app does not unpack EPUB/comic archives into a temporary library.
- Comic images are decoded for the viewport and cached as at most three images. Sequential archive reads reuse one libarchive cursor instead of rescanning from the beginning for every page, with a 64 MiB cache target. A single oversized image can exceed that target;
  this is **not** a limit on total process memory. JPEG XL currently needs a full-frame decode.
- Reflowable document layout is supplied by MuPDF. WebKit/Foliate is isolated to CHM rendering.
- MuPDF is built for size without its duplicate PDF reader, JS,
  OCR, barcode and office export components. Required fonts/codecs are not blindly removed.
- No full-document PDF conversion for DjVu/XPS; only PS uses a temporary conversion.
- Solid RAR/7z archives still have their inherent seek/decompression cost.
- WebKit has its own process/memory cost. Measure it with the app, not just Sumra's main process.

## Build on macOS

A macOS SDK / Xcode command-line toolchain is required for the GUI.
The deployment target is 13.0; the oldest OS/WebKit combination is not yet tested.
No GitHub Actions jobs run automatically.

```sh
# Native decoder build dependencies; not required by users of a bundled app.
brew install pkgconf djvulibre chmlib jpeg-xl convertlit
./scripts/build-app.sh
open dist/Sumra.app
```

Foliate's eight CHM renderer/search modules are vendored at the pinned revision. The first full build only fetches/builds the pinned MuPDF source and bundles linked decoder dylibs. Homebrew decoder versions are development inputs and are not yet pinned for redistribution. The result is a local ad-hoc signed bundle. The build script runs portable tests, validates Info.plist and icon output, then performs a strict deep code-signature verification. It is **not a notarized or redistribution-audited release**. A public binary
release must also supply the corresponding dependency sources and license notices.

```sh
./scripts/build-app.sh --core  # omit MuPDF/DjVu/CHM/JXL; fewer formats, not full parity
./scripts/run-dev.sh           # build the app bundle and launch a fresh instance
swift test                    # portable core routing/archive/legacy/chapter checks; also works on Linux
```

Optional PostScript: `brew install ghostscript`.

## Verification in this change

- Portable XCTest coverage includes libarchive/ZIP64 reads and rewind, path safety, ZIP subtype routing, format/signature routing, Palm/TCR/Print Replica handling, and multilingual TXT chapter detection.
- C MuPDF bridge: compiled and executed on Linux against the available MuPDF
  1.26.12; SVG rasterization and extracted text checked.
- macOS-target Swift **syntax parsing only**, JavaScript syntax and shell/Python syntax checked.
- **Not run:** macOS SDK type-check/link, WKWebView interaction, pinned native
  decoder build, app signing/loading, the full format corpus, launch/RSS benchmarks.

Next acceptance work is running the full build on macOS, checking the resource
bridge and dylib loading, then testing representative files for every table row
(including solid RAR, JPEG XR/XL/AVIF, malformed books and complex EPUB layout).
Installed size, cold start, first page and total memory remain **unmeasured**. The code now avoids opening PDFs twice and defers PDF outline traversal until the contents sidebar is requested; real large-file latency still requires the first macOS corpus run.

## License

New Sumra code: **AGPL-3.0-or-later**. The full MuPDF build must not be represented
as MIT-only. Earlier Leaf MIT notices and the Sumatra BSD notice are retained;
upstream libraries keep their licenses. See [THIRD_PARTY.md](THIRD_PARTY.md).
