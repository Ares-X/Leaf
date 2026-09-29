#if os(macOS)
import Foundation
import LeafCore
struct OpenDocument: Identifiable, Equatable {
    let id = UUID(), url: URL, kind: DocumentKind
    var name: String { url.lastPathComponent }
}
#endif
