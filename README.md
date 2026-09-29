# Leaf

A small, native macOS reader. Open a file, read it, close it.

**Engine integration in progress — not a release or a claim of tested SumatraPDF parity.**
The current source replaces the prototype's hand-written ZIP/EPUB/FB2 parsers and
Calibre/unar conversions with mature decoders and a small native shell.

## Reading

Open/Finder/drop/recent files; contents; search; page or percentage navigation;
zoom; actual/fit page/fit width; paged/continuous; two-page and right-to-left reading; GIF playback;
font family/size, line height and margins for reflowable text; full screen;
one bookmark per document; persistent PDF page, text line and e-book CFI.
PDF uses PDFKit, text uses NSTextView, e-books use the system WebKit with Foliate.
There is no Electron, Chromium distribution, Node runtime, library database,
account, cloud sync, updater, telemetry or general-purpose plug-in framework.

## Format routes

This table tracks the [SumatraPDF format list](https://www.sumatrapdfreader.org/docs/Supported-document-formats).
It documents **implemented dispatch/adapters**, not successful end-to-end fixtures
for every format. Rare formats need the full build's decoder libraries.

| Files | Engine/path |
| --- | --- |
| PDF, PDF-compatible AI | PDFKit; password prompt for encrypted PDF |
| EPUB, MOBI, AZW/AZW1/AZW3/KF8, PRC | Foliate + WebKit; native slice/entry reads, no Calibre |
| FB2, FB2Z, FBZ, ZFB2, FB2.ZIP | Foliate + libarchive |
| AZW4/Print Replica | Palm record adapter → embedded PDF → PDFKit |
| Palm DOC/PDB (including TealDoc/Plucker creator sniffing), TCR | small legacy adapters → NSTextView |
| TXT, JS, JSON, XML, LOG, NFO, FILE_ID.DIZ, READ.ME | NSTextView; UTF-8 / Foundation encoding detection |
| Microsoft Reader LIT | ConvertLIT helper → OEB/EPUB → Foliate; DRM5 remains unsupported |
| Markdown | Marked (GFM) → Foliate; not a home-written Markdown parser |
| HTML, HTM, XHTML | WebKit/Foliate local-document adapter |
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
not executed. Fixed-layout EPUB/CHM compatibility still needs sample testing.

## What makes it small

- Format routing is centralized: longest extension first, then a small Sumatra-derived magic sniffer for mislabeled files.
- Native libraries are loaded only when their format is opened and released with the document.
- The app does not unpack EPUB/comic archives into a temporary library.
- Comic images are decoded for the viewport and cached as at most three images,
  with a 64 MiB cache target. A single oversized image can exceed that target;
  this is **not** a limit on total process memory. JPEG XL currently needs a full-frame decode.
- Reflow, CFI, nested FB2 markup, font deobfuscation and book search are supplied by Foliate.
- MuPDF is built for size without its duplicate PDF/comic/e-book readers, JS,
  OCR, barcode and office export components. Required fonts/codecs are not blindly removed.
- No full-document PDF conversion for DjVu/XPS; only PS uses a temporary conversion.
- Solid RAR/7z archives still have their inherent seek/decompression cost.
- WebKit has its own process/memory cost. Measure it with the app, not just Leaf's main process.

## Build on macOS

A macOS SDK / Xcode command-line toolchain is required for the GUI.
The deployment target is 13.0; the oldest OS/WebKit combination is not yet tested.
No GitHub Actions jobs run automatically.

```sh
# Native decoder build dependencies; not required by users of a bundled app.
brew install pkgconf djvulibre chmlib jpeg-xl
./scripts/build-app.sh
open dist/Leaf.app
```

The first build checks out pinned Foliate and MuPDF revisions, fetches Marked
15.0.12's published ESM, builds the selective MuPDF library, and bundles only
linked decoder dylibs. Later builds reuse downloads and incremental outputs.
Homebrew library versions/build receipts are recorded in the bundle; those
three dependencies are not fully pinned yet. The result is a local ad-hoc signed
bundle, **not a notarized or redistribution-audited release**. A public binary
release must also supply the corresponding dependency sources and license notices.

```sh
./scripts/build-app.sh --core  # omit MuPDF/DjVu/CHM/JXL; fewer formats, not full parity
./scripts/run-dev.sh           # prepare JS resources, then swift run
swift test                    # three focused portable core checks; also works on Linux
```

Optional PostScript: `brew install ghostscript`.

## Verification in this change

- Linux / Swift 6.2.1: portable build and three XCTest cases passed: actual
  Deflate/ZIP64 entry reads/natural ordering, Palm/TCR/Print Replica byte handling,
  and compound-extension routing.
- C MuPDF bridge: compiled and executed on Linux against the available MuPDF
  1.26.12; SVG rasterization and extracted text checked.
- macOS-target Swift **syntax parsing only**, JavaScript syntax and shell/Python syntax checked.
- **Not run:** macOS SDK type-check/link, WKWebView interaction, pinned native
  decoder build, app signing/loading, the full format corpus, launch/RSS benchmarks.

Next acceptance work is running the full build on macOS, checking the resource
bridge and dylib loading, then testing representative files for every table row
(including solid RAR, JPEG XR/XL/AVIF, malformed books and complex EPUB layout).
Installed size, cold start, first page and total memory remain **unmeasured**.

## License

New Leaf code: **AGPL-3.0-or-later**. The full MuPDF build must not be represented
as MIT-only. Earlier Leaf MIT notices and the Sumatra BSD notice are retained;
upstream libraries keep their licenses. See [THIRD_PARTY.md](THIRD_PARTY.md).
