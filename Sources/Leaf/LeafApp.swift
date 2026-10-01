#if os(macOS)
import SwiftUI

struct WindowPayload: Codable, Hashable {
    var id = UUID()
    var path: String?

    init(path: String? = nil) {
        self.path = path
    }
}

@MainActor
private struct ReaderWindow: View {
    @Binding var payload: WindowPayload
    @StateObject private var state = ReaderState()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ReaderView(state: state)
            .frame(minWidth: 560, minHeight: 400)
            .background(WindowTabs(state: state))
            .focusedSceneObject(state)
            .task(id: payload.path) {
                guard !state.busy,
                      state.document == nil,
                      let path = payload.path,
                      FileManager.default.fileExists(atPath: path)
                else { return }
                state.open(URL(fileURLWithPath: path))
            }
            .onChange(of: state.document?.url.path) { payload.path = $0 }
            .onOpenURL { url in
                if state.document == nil && !state.busy {
                    state.open(url)
                } else {
                    openWindow(id: "reader", value: WindowPayload(path: url.path))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                state.persist()
            }
    }
}

private struct WindowTabs: NSViewRepresentable {
    let state: ReaderState

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.state = state
        return view
    }

    func updateNSView(_ view: HostView, context: Context) {
        view.state = state
    }

    @MainActor
    final class HostView: NSView {
        weak var state: ReaderState?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
            guard let window else { return }

            window.tabbingIdentifier = "LeafReader"
            window.tabbingMode = .preferred
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(closing),
                name: NSWindow.willCloseNotification,
                object: window
            )
        }

        @objc private func closing(_ notification: Notification) {
            state?.windowClosed()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

@main
@MainActor
struct LeafApp: App {
    init() {
        NSWindow.allowsAutomaticWindowTabbing = true
        AppIcon.apply(UserDefaults.standard.string(forKey: "appIcon") ?? "light")
    }

    var body: some Scene {
        WindowGroup("Sumra", id: "reader", for: WindowPayload.self) { $payload in
            ReaderWindow(payload: $payload)
        } defaultValue: {
            WindowPayload()
        }
        .defaultSize(width: 900, height: 740)
        .commands { LeafCommands() }

        Settings {
            SettingsView()
        }
    }
}

#else
@main
enum LeafCLI {
    static func main() {
        print("Sumra's UI requires macOS. Run swift test for portable core checks.")
    }
}
#endif
