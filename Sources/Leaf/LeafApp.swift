#if os(macOS)
import SwiftUI
import LeafCore
import UniformTypeIdentifiers

struct ReaderCommand: Equatable {
    let id = UUID()
    var name = "", text = ""
    var number = 0.0
}
struct ContentsItem: Identifiable, Codable {
    var id: String { target }
    let title: String, target: String
    var depth = 0
}
struct ReadingPosition: Codable {
    var page = 0
    var cfi: String?
    var fraction = 0.0
}

@MainActor final class ReaderState: ObservableObject {
    @Published var document: ReadingDocument?
    @Published var busy = false
    @Published var error: String?
    @Published var status = ""
    @Published var page = 0
    @Published var count = 0
    @Published var zoom = 1.0
    @Published var fraction = 0.0
    @Published var outline: [ContentsItem] = []
    @Published var command = ReaderCommand()
    @Published var showContents = false
    @Published var showFind = false
    @Published var spread = false
    @Published var rtl = false
    @Published var fitWidth = false
    @Published var recents: [URL] = []
    var cfi: String?
    private var loading: Task<Void, Never>?
    init() { recents = NSDocumentController.shared.recentDocumentURLs }
    var isBook: Bool { guard let document else { return false }; if case .book = document.content { return true }; return false }
    var isText: Bool { guard let document else { return false }; if case .text = document.content { return true }; return false }
    func close() { persist(); loading?.cancel(); document = nil; busy = false; outline = []; count = 0; status = "" }
    var positionLabel: String { isBook ? "\(Int(fraction * 100))%" : "\(min(page + 1, count)) / \(count)" }
    func send(_ name: String, text: String = "", number: Double = 0) { command = .init(name: name, text: text, number: number) }
    func chooseFile() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true
        panel.begin { [weak self] result in if result == .OK, let url = panel.url { self?.open(url) } }
    }
    func open(_ url: URL) {
        persist(); loading?.cancel(); document = nil; busy = true; error = nil; status = ""; outline = []
        page = 0; count = 0; zoom = 1; fraction = 0; cfi = nil
        loading = Task {
            let worker = Task.detached(priority: .userInitiated) { try ReadingDocument.open(url) }
            do {
                let opened = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled else { return }
                if let data = UserDefaults.standard.data(forKey: "position:" + url.standardizedFileURL.path),
                   let saved = try? JSONDecoder().decode(ReadingPosition.self, from: data) {
                    page = max(0, saved.page); cfi = saved.cfi; fraction = saved.fraction
                }
                document = opened; busy = false
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
                recents = NSDocumentController.shared.recentDocumentURLs
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; busy = false } }
        }
    }
    func persist() {
        guard let url = document?.url, let data = try? JSONEncoder().encode(ReadingPosition(page: page, cfi: cfi, fraction: fraction)) else { return }
        UserDefaults.standard.set(data, forKey: "position:" + url.standardizedFileURL.path)
    }
    func turn(_ delta: Int) {
        if isBook { send(delta > 0 ? "next" : "prev") }
        else { page = max(0, min(max(0, count - 1), page + delta * (spread ? 2 : 1))); send("page", number: Double(page)); persist() }
    }
    func go(_ value: String) {
        guard let n = Double(value), n.isFinite else { return }
        if isBook { send("fraction", number: max(0, min(1, n / 100))) }
        else { page = Int(max(0, min(Double(max(0, count - 1)), n - 1))); send("page", number: Double(page)); persist() }
    }
    func setZoom(_ value: Double) { zoom = max(0.25, min(6, value)); send("zoom", number: zoom) }
    func bookmark() {
        guard let url = document?.url else { return }; persist()
        UserDefaults.standard.set(UserDefaults.standard.data(forKey: "position:" + url.standardizedFileURL.path), forKey: "bookmark:" + url.standardizedFileURL.path)
        status = "Bookmark saved"
    }
    func restoreBookmark() {
        guard let url = document?.url, let data = UserDefaults.standard.data(forKey: "bookmark:" + url.standardizedFileURL.path),
              let saved = try? JSONDecoder().decode(ReadingPosition.self, from: data) else { return }
        if isBook, let cfi = saved.cfi { send("href", text: cfi) }
        else { go(String(saved.page + 1)) }
    }
}

@main @MainActor struct LeafApp: App {
    @StateObject private var state = ReaderState()
    var body: some Scene {
        Window("Leaf", id: "reader") {
            ReaderView(state: state).frame(minWidth: 560, minHeight: 400)
                .onOpenURL { state.open($0) }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in state.persist() }
        }.defaultSize(width: 900, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…", action: state.chooseFile).keyboardShortcut("o")
                Button("Close Document", action: state.close).keyboardShortcut("w", modifiers: [.command, .shift])
                Menu("Open Recent") { ForEach(state.recents, id: \.self) { url in Button(url.lastPathComponent) { state.open(url) } } }
            }
            CommandMenu("Reading") {
                Button("Find…") { state.showFind.toggle() }.keyboardShortcut("f")
                Button("Previous") { state.turn(-1) }.keyboardShortcut("[")
                Button("Next") { state.turn(1) }.keyboardShortcut("]")
                Divider()
                Button("Zoom In") { state.setZoom(state.zoom * 1.2) }.keyboardShortcut("+")
                Button("Zoom Out") { state.setZoom(state.zoom / 1.2) }.keyboardShortcut("-")
                Button("Fit Page") { state.fitWidth = false; state.zoom = 1; state.send("fit") }.keyboardShortcut("0")
                Toggle("Fit Width", isOn: $state.fitWidth)
                Toggle("Two Pages", isOn: $state.spread)
                Toggle("Right to Left", isOn: $state.rtl)
                Divider()
                Button("Bookmark This Position", action: state.bookmark).keyboardShortcut("d")
                Button("Go to Bookmark", action: state.restoreBookmark)
                Button("Contents") { state.showContents.toggle() }.keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor struct ReaderView: View {
    @ObservedObject var state: ReaderState
    @State private var query = ""
    @State private var destination = ""
    @FocusState private var finding: Bool
    var body: some View {
        VStack(spacing: 0) {
            if state.showFind {
                HStack {
                    TextField("Find in document", text: $query).focused($finding).onSubmit { state.send("find", text: query) }
                    Button("Find Next") { state.send("find", text: query) }
                    Button { state.showFind = false } label: { Image(systemName: "xmark") }
                }.padding(8).onAppear { finding = true }
                Divider()
            }
            HStack(spacing: 0) {
                if state.showContents {
                    List(Array(state.outline.enumerated()), id: \.offset) { _, item in
                        Button { state.send("href", text: item.target) } label: {
                            Text(item.title).lineLimit(2).padding(.leading, CGFloat(item.depth * 10))
                        }.buttonStyle(.plain)
                    }.frame(width: 210)
                    Divider()
                }
                Group {
                    if let doc = state.document { content(doc).id(doc.url) }
                    else if state.busy { ProgressView("Opening…") }
                    else { Button("Open a document…", action: state.chooseFile) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !state.status.isEmpty { Divider(); Text(state.status).font(.caption).foregroundStyle(.secondary).padding(5) }
        }
        .navigationTitle(state.document?.url.lastPathComponent ?? "Leaf")
        .onDisappear { state.close() }
        .onChange(of: state.spread) { state.send("spread", number: $0 ? 2 : 1) }
        .onChange(of: state.fitWidth) { state.send("flow", text: $0 ? "scrolled" : "paginated") }
        .toolbar {
            Button(action: state.chooseFile) { Image(systemName: "folder") }.help("Open")
            Button { state.showContents.toggle() } label: { Image(systemName: "sidebar.left") }.help("Contents")
            Button { state.turn(-1) } label: { Image(systemName: "chevron.left") }.disabled(!state.isBook && state.page == 0)
            Text(state.positionLabel).monospacedDigit()
            Button { state.turn(1) } label: { Image(systemName: "chevron.right") }.disabled(!state.isBook && state.page + 1 >= state.count)
            TextField(state.isBook ? "Go to %" : state.isText ? "Line" : "Page", text: $destination).frame(width: 55).onSubmit { state.go(destination); destination = "" }
            Button { state.setZoom(state.zoom / 1.2) } label: { Image(systemName: "minus.magnifyingglass") }
            Button { state.setZoom(state.zoom * 1.2) } label: { Image(systemName: "plus.magnifyingglass") }
            Button { state.showFind.toggle() } label: { Image(systemName: "magnifyingglass") }
        }
        .alert("Unable to read document", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
            Button("OK") { state.error = nil }
        } message: { Text(state.error ?? "") }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let first = providers.first else { return false }
            _ = first.loadObject(ofClass: URL.self) { url, _ in if let url { Task { @MainActor in state.open(url) } } }
            return true
        }
    }
    @ViewBuilder private func content(_ document: ReadingDocument) -> some View {
        switch document.content {
        case .pdf(let url, let data): PDFReader(state: state, url: url, data: data)
        case .text(let text): TextReader(state: state, text: text)
        case .book(let source): BookReader(state: state, source: source)
        case .pages(let pages): RasterReader(state: state, pages: pages).task {
            let count = await pages.count
            guard !Task.isCancelled else { return }
            state.count = count; state.page = max(0, min(state.page, count - 1))
        }
        }
    }
}
#else
@main enum LeafCLI { static func main() { print("Leaf's UI requires macOS. Run swift test for portable core checks.") } }
#endif
