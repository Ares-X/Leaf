#if os(macOS)
import SwiftUI

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
                        .disabled(query.isEmpty)
                    Button { state.closeFind() } label: {
                        Image(systemName: "xmark")
                    }
                    .help("Close Find")
                    .accessibilityLabel("Close Find")
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
        .background(DocumentProxy(url: state.document?.url))
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
            .disabled(!state.canGoBackward)
            .help("Previous Page")

            if state.hasDocument {
                Text(state.positionLabel).monospacedDigit()
            }

            Button { state.turn(1) } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!state.canGoForward)
            .help("Next Page")

            TextField(state.isText ? "Line" : "Page", text: $destination)
                .frame(width: 55)
                .disabled(state.count == 0 || state.isCHM)
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
            Button("Previous") { state.turn(-1) }.disabled(!state.canGoBackward)
            Button("Next") { state.turn(1) }.disabled(!state.canGoForward)
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
                content(document).id(document.id)
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
        case .pdf(let pdf):
            PDFReader(state: state, document: pdf)
        case .text(let text):
            TextReader(state: state, text: text)
        case .chm(let source):
            CHMReader(state: state, source: source)
        case .pages(let pages):
            RasterReader(state: state, pages: pages)
                .task {
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

private struct DocumentProxy: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> HostView { HostView() }

    func updateNSView(_ view: HostView, context: Context) {
        view.url = url
        view.window?.representedURL = url
    }

    final class HostView: NSView {
        var url: URL?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.representedURL = url
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
#endif
