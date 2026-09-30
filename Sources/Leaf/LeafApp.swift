#if os(macOS)
import SwiftUI

struct WindowPayload: Codable, Hashable {
    var id = UUID()
    var path: String?

    init(path: String? = nil) {
        self.path = path
    }
}

private struct ReaderStateKey: FocusedValueKey {
    typealias Value = ReaderState
}

private extension FocusedValues {
    var readerState: ReaderState? {
        get { self[ReaderStateKey.self] }
        set { self[ReaderStateKey.self] = newValue }
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
            .focusedSceneValue(\.readerState, state)
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

private struct LeafCommands: Commands {
    @FocusedValue(\.readerState) private var state
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
                .disabled(state?.document == nil)
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
                .disabled(state?.canTurn != true)
            Button("Next Page") { state?.turn(1) }
                .keyboardShortcut("]")
                .disabled(state?.canTurn != true)

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

@main
@MainActor
struct LeafApp: App {
    init() {
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    var body: some Scene {
        WindowGroup("Leaf", id: "reader", for: WindowPayload.self) { $payload in
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

@MainActor
struct ReaderView: View {
    @ObservedObject var state: ReaderState
    @State private var query = ""
    @State private var destination = ""
    @FocusState private var finding: Bool
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            if state.showFind {
                HStack {
                    TextField("Find in document", text: $query)
                        .focused($finding)
                        .onSubmit { state.send(.find(query)) }
                        .onExitCommand { state.closeFind() }
                    Button("Find Next") { state.send(.find(query)) }
                    Button { state.closeFind() } label: {
                        Image(systemName: "xmark")
                    }
                }
                .padding(8)
                .onAppear { finding = true }
                Divider()
            }

            mainArea

            if state.document != nil {
                Divider()
                HStack {
                    Text(state.status.isEmpty ? (state.document?.url.lastPathComponent ?? "") : state.status)
                        .lineLimit(1)
                    Spacer()
                    if state.count > 0 {
                        Text(state.positionLabel).monospacedDigit()
                    }
                    Text(state.zoomLabel).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(state.document?.url.lastPathComponent ?? "Leaf")
        .modifier(DocumentProxy(url: state.document?.url))
        .preferredColorScheme(state.theme == "dark" ? .dark : state.theme == "light" ? .light : nil)
        .onChange(of: colorScheme) { _ in
            if state.theme == "system", state.isText || state.isCHM || state.reflowable {
                state.send(.style)
            }
        }
        .onChange(of: state.spread) {
            UserDefaults.standard.set($0, forKey: "spread")
        }
        .onChange(of: state.rtl) {
            UserDefaults.standard.set($0, forKey: "rtl")
        }
        .toolbar { toolbar }
        .contextMenu { contextMenu }
        .dropDestination(for: URL.self) { urls, _ in
            guard let first = urls.first else { return false }
            state.open(first)
            for url in urls.dropFirst() {
                openWindow(id: "reader", value: WindowPayload(path: url.path))
            }
            return true
        }
        .alert(
            "Unable to read document",
            isPresented: Binding(
                get: { state.error != nil },
                set: { if !$0 { state.error = nil } }
            )
        ) {
            Button("OK") { state.error = nil }
        } message: {
            Text(state.error ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button(action: state.chooseFile) {
                Image(systemName: "folder")
            }
            .help("Open Document")

            Button { state.showContents.toggle() } label: {
                Image(systemName: "sidebar.left")
            }
            .disabled(!state.hasDocument)
            .help("Toggle Contents")

            Button { state.turn(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!state.canTurn)
            .help("Previous Page")

            if state.hasDocument {
                Text(state.positionLabel).monospacedDigit()
            }

            Button { state.turn(1) } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!state.canTurn)
            .help("Next Page")

            TextField(state.isText ? "Line" : "Page", text: $destination)
                .frame(width: 55)
                .disabled(!state.hasDocument || state.isCHM)
                .onSubmit {
                    state.go(destination)
                    destination = ""
                }

            readingOptions

            Button { state.setZoom(state.zoom / 1.2) } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(!state.hasDocument)
            .help("Zoom Out")

            Button { state.setZoom(state.zoom * 1.2) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(!state.hasDocument)
            .help("Zoom In")

            Button { state.showFindPanel() } label: {
                Image(systemName: "magnifyingglass")
            }
            .disabled(!state.supportsSearch)
            .help("Find")
        }
    }

    private var readingOptions: some View {
        Menu {
            if state.isFixed {
                Button("Fit Page") { state.setFit("page") }
                Button("Fit Width") { state.setFit("width") }
                Button("Actual Size") { state.setFit("actual") }
                Divider()

                Button("Paged") { state.setFlow("paged") }
                Button("Continuous") { state.setFlow("continuous") }
                Toggle("Two Pages", isOn: $state.spread)
                Toggle("Right to Left", isOn: $state.rtl)
                Divider()
            }

            if state.isText || state.isCHM || state.reflowable {
                TypographyMenu(state: state)
                Divider()
            }

            if state.isFixed {
                Button("Rotate Left") { state.rotate(-90) }
                Button("Rotate Right") { state.rotate(90) }
                Divider()
            }

            Button("Light") { state.setTheme("light") }
            Button("Dark") { state.setTheme("dark") }
            Button("System Theme") { state.setTheme("system") }
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .help("Reading Options")
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Open…", action: state.chooseFile)
        if state.document != nil {
            Button("Show in Finder") {
                if let url = state.document?.url {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Button("Copy File Path", action: state.copyPath)
            Divider()
            Button("Previous") { state.turn(-1) }.disabled(!state.canTurn)
            Button("Next") { state.turn(1) }.disabled(!state.canTurn)
            if state.isFixed {
                Button("Fit Page") { state.setFit("page") }
                Button("Fit Width") { state.setFit("width") }
            }
        }
    }

    @ViewBuilder
    private var mainArea: some View {
        HSplitView {
            if state.showContents {
                contentsSidebar.frame(minWidth: 180, idealWidth: 220, maxWidth: 360)
            }
            documentArea
        }
    }

    @ViewBuilder
    private var contentsSidebar: some View {
        if state.outlineBusy {
            VStack {
                Spacer()
                ProgressView()
                Text("Detecting chapters…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else if state.outline.isEmpty {
            VStack {
                Spacer()
                Text("No contents")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            List(Array(state.outline.enumerated()), id: \.offset) { _, item in
                Button {
                    state.send(.href(item.target))
                } label: {
                    Text(item.title)
                        .lineLimit(2)
                        .padding(.leading, CGFloat(item.depth * 10))
                }
                .buttonStyle(.plain)
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private var documentArea: some View {
        Group {
            if let document = state.document {
                content(document).id(document.url)
            } else if state.busy {
                ProgressView("Opening…")
            } else {
                WelcomeView(open: state.chooseFile)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(_ document: ReadingDocument) -> some View {
        switch document.content {
        case .pdf(let url, let data):
            PDFReader(state: state, url: url, data: data)
        case .text(let text):
            TextReader(state: state, text: text)
        case .chm(let source):
            CHMReader(state: state, source: source)
        case .pages(let pages):
            RasterReader(state: state, pages: pages)
                .task {
                    let generation = state.generation
                    let searchable = await pages.hasText
                    let reflowCount = await pages.relayout(
                        fontSize: state.fontSize,
                        lineHeight: state.lineHeight,
                        margin: state.margin,
                        font: state.font,
                        theme: state.resolvedTheme
                    )
                    let count = await pages.count

                    guard !Task.isCancelled,
                          generation == state.generation,
                          case .pages(let current)? = state.document?.content,
                          current === pages
                    else { return }

                    state.searchable = searchable
                    state.reflowable = reflowCount != nil
                    state.count = count
                    state.page = max(0, min(state.page, max(0, count - 1)))
                    state.renderRevision += 1
                }
        }
    }
}

private struct DocumentProxy: ViewModifier {
    let url: URL?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let url {
            content.navigationDocument(url)
        } else {
            content
        }
    }
}

private struct WelcomeView: View {
    let open: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
            Text("Leaf")
                .font(.largeTitle.weight(.semibold))
            Text("A fast, focused document reader for macOS")
                .foregroundStyle(.secondary)
            Button("Open Document…", action: open)
                .keyboardShortcut("o")
            Text("Drop a document here, or use File → Open")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
    }
}

struct TypographyMenu: View {
    @ObservedObject var state: ReaderState

    var body: some View {
        Group {
            Picker("Font", selection: $state.font) {
                Text("System").tag("system")
                Text("Serif").tag("serif")
                Text("Sans Serif").tag("sans-serif")
                Text("Monospace").tag("monospace")
            }
            .onChange(of: state.font) { _ in state.applyTypography() }

            Stepper("Font \(Int(state.fontSize)) pt", value: $state.fontSize, in: 10...36, step: 1)
                .onChange(of: state.fontSize) { _ in state.applyTypography() }

            Stepper("Line \(state.lineHeight, specifier: "%.1f")", value: $state.lineHeight, in: 1...2.4, step: 0.1)
                .onChange(of: state.lineHeight) { _ in state.applyTypography() }

            Stepper("Margin \(Int(state.margin))", value: $state.margin, in: 0...96, step: 8)
                .onChange(of: state.margin) { _ in state.applyTypography() }
        }
    }
}
#else
@main
enum LeafCLI {
    static func main() {
        print("Leaf's UI requires macOS. Run swift test for portable core checks.")
    }
}
#endif
