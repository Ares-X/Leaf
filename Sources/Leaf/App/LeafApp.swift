#if os(macOS)
import SwiftUI
@main struct LeafApp: App {
    @StateObject private var session = ReaderSession()
    var body: some Scene {
        WindowGroup { ReaderRootView(session: session).frame(minWidth: 700, minHeight: 500).onOpenURL { session.open($0) } }
            .commands { CommandGroup(replacing: .newItem) { Button("Open…") { session.chooseFile() }.keyboardShortcut("o") } }
    }
}
#else
@main enum LeafStub { static func main() { print("Leaf is a macOS app.") } }
#endif
