#if os(macOS)
import SwiftUI

struct LeafCommands: Commands {
    @FocusedObject private var state: ReaderState?
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open…", action: openFiles)
                .keyboardShortcut("o")

            Menu("Open Recent") {
                ForEach(
                    NSDocumentController.shared.recentDocumentURLs
                        .filter { FileManager.default.fileExists(atPath: $0.path) },
                    id: \.self
                ) { url in
                    Button(url.lastPathComponent) {
                        if let state {
                            state.open(url)
                        } else {
                            openWindow(id: "reader", value: WindowPayload(path: url.path))
                        }
                    }
                }
                Divider()
                Button("Clear Menu") {
                    NSDocumentController.shared.clearRecentDocuments(nil)
                }
            }
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save a Copy…") { state?.saveCopy() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(state?.canSaveCopy != true)
            Button("Reload") { state?.reload() }
                .keyboardShortcut("r")
                .disabled(state?.document == nil || state?.busy == true)
            Button("Show in Finder") {
                if let url = state?.document?.url {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            .disabled(state?.document == nil)
            Button("Copy File Path") { state?.copyPath() }
                .disabled(state?.document == nil)
            Button("Close Document") { state?.close() }
                .disabled(state?.document == nil)
        }

        CommandGroup(replacing: .printItem) {
            Button(state?.printTitle ?? "Print…") { state?.printDocument() }
                .keyboardShortcut("p")
                .disabled(state?.document == nil)
        }

        CommandGroup(after: .toolbar) {
            Button("Toggle Contents") { state?.showContents.toggle() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(state?.hasDocument != true)
            Button("Enter Full Screen") {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .control])
        }

        CommandMenu("Reading") {
            Button("Find…") { state?.showFindPanel() }
                .keyboardShortcut("f")
                .disabled(state?.supportsSearch != true)

            Button("Previous Page") { state?.turn(-1) }
                .keyboardShortcut("[")
                .disabled(state?.canGoBackward != true)
            Button("Next Page") { state?.turn(1) }
                .keyboardShortcut("]")
                .disabled(state?.canGoForward != true)

            Button("Previous File") { state?.sibling(-1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(state?.hasDocument != true)
            Button("Next File") { state?.sibling(1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(state?.hasDocument != true)

            Divider()

            Button("Zoom In") {
                if let state { state.setZoom(state.zoom * 1.2) }
            }
            .keyboardShortcut("+")
            .disabled(state?.hasDocument != true)

            Button("Zoom Out") {
                if let state { state.setZoom(state.zoom / 1.2) }
            }
            .keyboardShortcut("-")
            .disabled(state?.hasDocument != true)

            Button("Actual Size") { state?.setFit("actual") }
                .keyboardShortcut("1")
                .disabled(state?.isFixed != true)
            Button("Fit Page") { state?.setFit("page") }
                .keyboardShortcut("0")
                .disabled(state?.isFixed != true)
            Button("Fit Width") { state?.setFit("width") }
                .keyboardShortcut("2")
                .disabled(state?.isFixed != true)

            Divider()

            Button("Paged") { state?.setFlow("paged") }
                .disabled(state?.isFixed != true)
            Button("Continuous") { state?.setFlow("continuous") }
                .disabled(state?.isFixed != true)
            Toggle(
                "Two Pages",
                isOn: Binding(
                    get: { state?.spread ?? false },
                    set: { state?.spread = $0 }
                )
            )
            .disabled(state?.isFixed != true)
            Toggle(
                "Right to Left",
                isOn: Binding(
                    get: { state?.rtl ?? false },
                    set: { state?.rtl = $0 }
                )
            )
            .disabled(state?.isFixed != true)

            Divider()

            Button("Bookmark This Position") { state?.bookmark() }
                .keyboardShortcut("d")
                .disabled(state?.hasDocument != true)
            Button("Go to Bookmark") { state?.restoreBookmark() }
                .disabled(state?.hasBookmark != true)
            Button("Contents") { state?.showContents.toggle() }
                .disabled(state?.hasDocument != true)

            Divider()

            Button("Rotate Left") { state?.rotate(-90) }
                .disabled(state?.isFixed != true)
            Button("Rotate Right") { state?.rotate(90) }
                .disabled(state?.isFixed != true)

            Divider()

            Button("Light") { state?.setTheme("light") }
            Button("Dark") { state?.setTheme("dark") }
            Button("System Theme") { state?.setTheme("system") }
        }
    }

    private func openFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.begin { result in
            guard result == .OK, let first = panel.urls.first else { return }

            if let state {
                state.open(first)
            } else {
                openWindow(id: "reader", value: WindowPayload(path: first.path))
            }

            for url in panel.urls.dropFirst() {
                openWindow(id: "reader", value: WindowPayload(path: url.path))
            }
        }
    }
}

#endif
