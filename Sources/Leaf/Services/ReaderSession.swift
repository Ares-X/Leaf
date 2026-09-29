#if os(macOS)
import AppKit
import LeafCore
@MainActor final class ReaderSession: ObservableObject {
    @Published private(set) var document: OpenDocument?
    func chooseFile() {
        let p = NSOpenPanel(); p.canChooseDirectories = false
        if p.runModal() == .OK, let url = p.url { open(url) }
    }
    func open(_ url: URL) {
        document = OpenDocument(url: url, kind: FormatDetector.detect(url: url))
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }
}
#endif
