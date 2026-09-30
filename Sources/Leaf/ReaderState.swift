#if os(macOS)
import Darwin
import LeafCore
import SwiftUI

enum ReaderAction: Equatable {
    case none, next, previous, print, style, toc
    case page(Int), href(String), zoom(Double), fit(String), find(String), rotate(Int)
}

struct ReaderCommand: Equatable {
    var revision = 0
    var action: ReaderAction = .none
}

struct ContentsItem: Identifiable, Codable {
    var id: String { target }
    let title: String
    let target: String
    var depth = 0
}

struct ReadingPosition: Codable {
    var page = 0
}

@MainActor
final class ReaderState: ObservableObject {
    @Published var document: ReadingDocument?
    @Published var busy = false
    @Published var error: String?
    @Published var status = ""
    @Published var page = 0
    @Published var count = 0
    @Published var zoom = 1.0
    @Published var outline: [ContentsItem] = []
    @Published var outlineBusy = false
    @Published var command = ReaderCommand()
    @Published var showContents = false
    @Published var showFind = false
    @Published var spread = false
    @Published var rtl = false
    @Published var fit = "page"
    @Published var flow = "paged"
    @Published var font = "system"
    @Published var fontSize = 17.0
    @Published var lineHeight = 1.6
    @Published var margin = 32.0
    @Published var theme = "system"
    @Published var rotation = 0
    @Published var reflowable = false
    @Published var searchable = false
    @Published var renderRevision = 0

    private var loading: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var watch: DispatchSourceFileSystemObject?
    private(set) var generation = 0

    init() {
        readPreferences()
    }
}

extension ReaderState {
    var isText: Bool {
        if case .text = document?.content { return true }
        return false
    }

    var isPDF: Bool {
        if case .pdf = document?.content { return true }
        return false
    }

    var isFixed: Bool {
        guard let document else { return false }
        switch document.content {
        case .pdf, .pages: return true
        default: return false
        }
    }

    var isCHM: Bool {
        if case .chm = document?.content { return true }
        return false
    }

    var supportsSearch: Bool { isPDF || isText || isCHM || searchable }
    var hasDocument: Bool { document != nil }
    var canTurn: Bool { isCHM ? hasDocument : count > 1 }
    var canGoBackward: Bool { isCHM ? hasDocument : page > 0 && count > 0 }
    var canGoForward: Bool { isCHM ? hasDocument : page < count - 1 }
    var canSaveCopy: Bool { document?.url.hasDirectoryPath == false }

    var printsCurrentPageOnly: Bool {
        if case .pages = document?.content { return count > 1 }
        return false
    }

    var printTitle: String {
        printsCurrentPageOnly ? "Print Current Page…" : "Print…"
    }

    var hasBookmark: Bool {
        guard let url = document?.url else { return false }
        return UserDefaults.standard.data(forKey: "bookmark:" + url.standardizedFileURL.path) != nil
    }

    var positionLabel: String {
        count > 0 ? "\(min(page + 1, count)) / \(count)" : "— / —"
    }

    var resolvedTheme: String {
        guard theme == "system" else { return theme }
        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
    }

    var zoomLabel: String {
        if isText || isCHM || fit == "custom" { return "\(Int(zoom * 100))%" }
        if fit == "width" { return "Fit Width" }
        if fit == "actual" { return "100%" }
        return "Fit Page"
    }
}

extension ReaderState {
    func send(_ action: ReaderAction) {
        command = .init(revision: command.revision &+ 1, action: action)
    }

    func showFindPanel() {
        showFind = true
    }

    func closeFind() {
        showFind = false
        status = ""
        send(.toc)
    }

    func turn(_ delta: Int) {
        if isCHM {
            send(delta > 0 ? .next : .previous)
            return
        }
        let step = (spread && isFixed) ? 2 : 1
        page = max(0, min(max(0, count - 1), page + delta * step))
        send(.page(page))
        persist()
    }

    func go(_ value: String) {
        guard let value = Double(value), value.isFinite else { return }
        page = Int(max(0, min(Double(max(0, count - 1)), value - 1)))
        send(.page(page))
        persist()
    }

    func printDocument() { send(.print) }

    func setZoom(_ value: Double) {
        zoom = max(0.25, min(6, value))
        fit = "custom"
        send(.zoom(zoom))
    }

    func setFit(_ value: String) {
        fit = value
        zoom = 1
        UserDefaults.standard.set(value, forKey: "fit")
        send(.fit(value))
    }

    func setFlow(_ value: String) {
        flow = value
        UserDefaults.standard.set(value, forKey: "flow")
    }

    func applyTypography() {
        let defaults = UserDefaults.standard
        defaults.set(font, forKey: "font")
        defaults.set(fontSize, forKey: "fontSize")
        defaults.set(lineHeight, forKey: "lineHeight")
        defaults.set(margin, forKey: "margin")
        send(.style)
    }

    func setTheme(_ value: String) {
        theme = value
        UserDefaults.standard.set(value, forKey: "theme")
        if isText || isCHM || reflowable { send(.style) }
    }

    func rotate(_ degrees: Int) {
        rotation = (rotation + degrees + 360) % 360
        send(.rotate(degrees))
    }
}

extension ReaderState {
    func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.begin { [weak self] result in
            if result == .OK, let url = panel.url { self?.open(url) }
        }
    }

    func open(_ url: URL) {
        load(url.standardizedFileURL, reloading: false)
    }

    func close() {
        generation += 1
        persist()
        loading?.cancel()
        loading = nil
        stopWatch()
        document = nil
        busy = false
        error = nil
        page = 0
        command = ReaderCommand()
        outline = []
        outlineBusy = false
        showFind = false
        count = 0
        status = ""
        reflowable = false
        searchable = false
        renderRevision = 0
    }

    func reload() {
        guard !busy, let url = document?.url else { return }
        load(url, reloading: true)
    }

    func persist() {
        guard let url = document?.url,
              let data = try? JSONEncoder().encode(ReadingPosition(page: page))
        else { return }
        UserDefaults.standard.set(data, forKey: "position:" + url.standardizedFileURL.path)
    }

    func sibling(_ delta: Int) {
        guard let url = document?.url,
              let files = try? FileManager.default.contentsOfDirectory(
                at: url.deletingLastPathComponent(),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              )
        else { return }

        let list = files
            .filter { Format.detect($0.lastPathComponent) != .unknown }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard let index = list.firstIndex(of: url), list.indices.contains(index + delta) else { return }
        open(list[index + delta])
    }

    func saveCopy() {
        guard let sourceURL = document?.url, !sourceURL.hasDirectoryPath else {
            error = "Save a Copy is only available for files."
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.begin { result in
            guard result == .OK, let destinationURL = panel.url else { return }
            do {
                let fileManager = FileManager.default
                let source = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
                let destination = destinationURL.standardizedFileURL.resolvingSymlinksInPath()
                guard source != destination else {
                    throw ReadError("Choose a different location for Save a Copy.")
                }

                let temporary = destinationURL.deletingLastPathComponent()
                    .appendingPathComponent(".Leaf-copy-" + UUID().uuidString)
                defer { try? fileManager.removeItem(at: temporary) }

                try fileManager.copyItem(at: sourceURL, to: temporary)
                if fileManager.fileExists(atPath: destinationURL.path) {
                    _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporary)
                } else {
                    try fileManager.moveItem(at: temporary, to: destinationURL)
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func copyPath() {
        guard let path = document?.url.path else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    func bookmark() {
        guard let url = document?.url else { return }
        persist()
        let defaults = UserDefaults.standard
        defaults.set(
            defaults.data(forKey: "position:" + url.standardizedFileURL.path),
            forKey: "bookmark:" + url.standardizedFileURL.path
        )
        status = "Bookmark saved"
    }

    func restoreBookmark() {
        guard let url = document?.url,
              let data = UserDefaults.standard.data(forKey: "bookmark:" + url.standardizedFileURL.path),
              let position = try? JSONDecoder().decode(ReadingPosition.self, from: data)
        else { return }
        go(String(position.page + 1))
    }

    func windowClosed() {
        persist()
        generation += 1
        loading?.cancel()
        loading = nil
        stopWatch()
    }
}

private extension ReaderState {
    func load(_ url: URL, reloading: Bool) {
        persist()
        generation &+= 1
        let currentGeneration = generation
        loading?.cancel()
        reloadTask?.cancel()
        reloadTask = nil
        busy = true
        error = nil
        status = reloading ? "Reloading…" : "Opening \(url.lastPathComponent)…"

        loading = Task {
            let worker = Task.detached(priority: .userInitiated) {
                let opened = try ReadingDocument.open(url)
                try Task.checkCancellation()
                return opened
            }
            do {
                let opened = try await withTaskCancellationHandler(
                    operation: { try await worker.value },
                    onCancel: { worker.cancel() }
                )
                guard !Task.isCancelled, currentGeneration == generation else { return }

                // The old document stays readable while loading. Save its latest position.
                persist()
                if !reloading {
                    readPreferences()
                    zoom = 1
                    rotation = 0
                    page = 0
                    if let data = UserDefaults.standard.data(forKey: "position:" + opened.url.path),
                       let position = try? JSONDecoder().decode(ReadingPosition.self, from: data) {
                        page = max(0, position.page)
                    }
                }
                command = ReaderCommand()
                outline = []
                outlineBusy = false
                showFind = false
                count = 0
                reflowable = false
                searchable = false
                renderRevision = 0
                document = opened
                busy = false
                status = ""
                loading = nil
                watchFile(opened.url)
                if !reloading {
                    NSDocumentController.shared.noteNewRecentDocumentURL(opened.url)
                }
            } catch {
                guard !Task.isCancelled, currentGeneration == generation else { return }
                busy = false
                status = ""
                self.error = error.localizedDescription
                loading = nil
                // Atomic replacement may have invalidated the previous file descriptor.
                if let url = document?.url { watchFile(url) }
            }
        }
    }

    func readPreferences() {
        let defaults = UserDefaults.standard
        fit = defaults.string(forKey: "fit") ?? "page"
        flow = defaults.string(forKey: "flow") ?? "paged"
        spread = defaults.bool(forKey: "spread")
        rtl = defaults.bool(forKey: "rtl")
        font = defaults.string(forKey: "font") ?? "system"
        theme = defaults.string(forKey: "theme") ?? "system"
        fontSize = defaults.object(forKey: "fontSize") == nil ? 17 : defaults.double(forKey: "fontSize")
        lineHeight = defaults.object(forKey: "lineHeight") == nil ? 1.6 : defaults.double(forKey: "lineHeight")
        margin = defaults.object(forKey: "margin") == nil ? 32 : defaults.double(forKey: "margin")
    }

    func watchFile(_ url: URL) {
        stopWatch()
        guard !url.hasDirectoryPath else { return }
        let fileDescriptor = Darwin.open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        watch = source
        source.setEventHandler { [weak self] in
            guard let self,
                  !self.busy,
                  let source = self.watch,
                  self.document?.url == url
            else { return }

            let event = source.data
            self.status = "File changed on disk"
            self.reloadTask?.cancel()
            self.reloadTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, !self.busy, self.document?.url == url else { return }
                if event.contains(.delete) || event.contains(.rename) {
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        self.status = "File moved or deleted"
                        self.stopWatch()
                        return
                    }
                }
                self.reload()
            }
        }
        source.setCancelHandler { Darwin.close(fileDescriptor) }
        source.resume()
    }

    func stopWatch() {
        reloadTask?.cancel()
        reloadTask = nil
        watch?.cancel()
        watch = nil
    }
}

#endif
