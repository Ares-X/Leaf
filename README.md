# Leaf

Tiny native macOS reader. Open a file, read it, close it.

PDF · EPUB · TXT/LOG · Markdown · CBZ/ZIP · images

- SwiftUI/AppKit
- PDFKit for PDF
- WebKit for EPUB
- small in-tree ZIP reader + system zlib for EPUB/CBZ
- no Electron/Tauri, library database, account, sync, or telemetry

Leaf borrows SumatraPDF's useful idea of dispatching formats to small dedicated readers, but is a clean-room Swift implementation.

## Build

```bash
swift test
./scripts/build-app.sh
open dist/Leaf.app
```

macOS 13+.

## Next

MOBI/AZW3 · FB2 · DjVu · CBR

## License

MIT
