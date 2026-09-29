# Leaf

Tiny native macOS reader. Open a file, read it, close it.

**Built in:** PDF · EPUB · TXT/LOG · Markdown · FB2 · CBZ/ZIP · JPG/PNG/GIF/WebP/HEIC/TIFF/BMP

**Optional tiny backends:** MOBI/AZW/AZW3 via Calibre's `ebook-convert`, DjVu via `ddjvu`, CBR via `unar`.

- native SwiftUI/AppKit, PDFKit and WebKit
- tiny in-tree ZIP reader + system zlib
- remembers PDF pages and EPUB/CBZ positions
- keyboard arrows for EPUB/CBZ
- Finder document associations
- no Electron/Tauri, library database, account, sync, telemetry, plugin framework or settings maze

Leaf borrows SumatraPDF's useful idea of dispatching formats to small dedicated readers, but is a clean-room Swift implementation.

## Build

```bash
swift test
./scripts/build-app.sh
open dist/Leaf.app
```

macOS 13+.

Optional formats:

```bash
brew install --cask calibre
brew install djvulibre unar
```

## MVP scope

Reading first. Editing, annotation management, cloud libraries and DRM are deliberately out of scope.

## License

MIT
