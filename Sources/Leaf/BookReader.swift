#if os(macOS)
import SwiftUI
import WebKit
import CryptoKit
import UniformTypeIdentifiers
import LeafCore

actor BookSource {
    let url: URL
    let format: Format
    private let archive: Archive?
    private let chm: NativeFile?
    private let chmIndex: [String: Int]
    private let entries: [Archive.Entry]
    private let file: FileHandle
    private let size: UInt64
    init(_ url: URL, format: Format) throws {
        self.url = url; self.format = format
        file = try FileHandle(forReadingFrom: url); size = try file.seekToEnd()
        let ext = url.pathExtension.lowercased()
        if format == .book && ["epub", "fb2z", "fbz", "zfb2", "zip"].contains(ext) {
            let a = try Archive(url); archive = a; entries = a.entries; chm = nil; chmIndex = [:]
        } else if format == .chm {
            let c = try NativeFile(url, engine: "CHM"); chm = c; archive = nil
            var map: [String: Int] = [:], paths: [Archive.Entry] = []
            for i in 0..<c.count {
                let path = String(try c.path(i).drop(while: { $0 == "/" }))
                map[path.lowercased()] = i; paths.append(.init(name: path, size: 0))
            }
            chmIndex = map; entries = paths
        } else { archive = nil; chm = nil; chmIndex = [:]; entries = [] }
    }
    deinit { try? file.close() }
    func response(_ request: URL) throws -> Data {
        try Task.checkCancellation()
        let parameters = URLComponents(url: request, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func param(_ name: String) -> String? { parameters.first { $0.name == name }?.value }
        if request.path == "/meta" {
            return try JSONSerialization.data(withJSONObject: ["name": url.lastPathComponent, "size": size,
                "format": format.rawValue, "entries": entries.map { ["filename": $0.name, "size": $0.size] }])
        }
        if request.path == "/sha1" { return Data(Insecure.SHA1.hash(data: Data((param("text") ?? "").utf8))) }
        if request.path == "/raw" {
            let start = min(size, UInt64(param("start") ?? "0") ?? 0)
            let end = min(size, UInt64(param("end") ?? String(size)) ?? size)
            guard end >= start else { throw ReadError("Invalid book slice") }
            try file.seek(toOffset: start)
            return try file.read(upToCount: Int(end - start)) ?? Data()
        }
        let name = String(request.path.dropFirst("/entry/".count))
        if request.path.hasPrefix("/entry/") {
            if let archive { return try archive.data(name) }
            if let chm, let index = chmIndex[name.lowercased()] {
                let data = try chm.data(index)
                return ["htm", "html", "hhc", "hhk", "css"].contains((name as NSString).pathExtension.lowercased()) ? Data(ReadingDocument.decode(data).utf8) : data
            }
        }
        if request.path.hasPrefix("/files/"), [.html, .markdown].contains(format) {
            let root = url.deletingLastPathComponent().resolvingSymlinksInPath()
            let file = root.appendingPathComponent(String(request.path.dropFirst(7))).standardizedFileURL.resolvingSymlinksInPath()
            guard file.path.hasPrefix(root.path + "/") else { throw ReadError("Resource is outside the document folder") }
            return try Data(contentsOf: file)
        }
        throw ReadError("Book resource not found")
    }
}

@MainActor struct BookReader: NSViewRepresentable {
    @ObservedObject var state: ReaderState
    let source: BookSource
    func makeCoordinator() -> Coordinator { Coordinator(state: state, source: source) }
    func makeNSView(context: Context) -> WKWebView {
        let coordinator = context.coordinator, config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(coordinator, forURLScheme: "leaf")
        config.userContentController.add(coordinator, name: "leaf")
        let location = (try? JSONSerialization.data(withJSONObject: [state.cfi ?? ""])) ?? Data("[\"\"]".utf8)
        let script = "window.leafLocation = \(String(decoding: location, as: UTF8.self))[0]; window.leafSpread = \(state.spread ? 2 : 1); window.leafFlow = \(state.fitWidth ? "\"scrolled\"" : "\"paginated\"");"
        config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: config); view.navigationDelegate = coordinator
        view.load(URLRequest(url: URL(string: "leaf://reader/reader.html")!))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.command != state.command.id else { return }
        context.coordinator.command = state.command.id
        let message: [String: Any] = ["name": state.command.name, "text": state.command.text, "number": state.command.number]
        if let data = try? JSONSerialization.data(withJSONObject: message) {
            view.evaluateJavaScript("window.leafCommand?.(\(String(decoding: data, as: UTF8.self)))", completionHandler: nil)
        }
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.requests.values.forEach { $0.cancel() }; coordinator.requests.removeAll()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "leaf")
        view.navigationDelegate = nil; view.stopLoading()
    }
    @MainActor final class Coordinator: NSObject, WKURLSchemeHandler, WKScriptMessageHandler, WKNavigationDelegate {
        let state: ReaderState, source: BookSource
        var command: UUID?
        var requests: [ObjectIdentifier: Task<Void, Never>] = [:]
        init(state: ReaderState, source: BookSource) { self.state = state; self.source = source }
        func webView(_ view: WKWebView, start schemeTask: WKURLSchemeTask) {
            let id = ObjectIdentifier(schemeTask)
            requests[id] = Task { @MainActor in
                do {
                    guard let url = schemeTask.request.url else { throw ReadError("Missing resource URL") }
                    let data: Data
                    if url.host == "reader" {
                        let packaged = Bundle.main.resourceURL?.appendingPathComponent("Reader")
                        let root = packaged.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } ?? Bundle.module.url(forResource: "Reader", withExtension: nil)!
                        let file = root.appendingPathComponent(String(url.path.dropFirst())).standardizedFileURL.resolvingSymlinksInPath()
                        guard file.path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { throw ReadError("Missing reader resource") }
                        data = try await Task.detached { try Data(contentsOf: file) }.value
                    } else if url.host == "book" { data = try await source.response(url) }
                    else { throw ReadError("Unknown resource host") }
                    guard !Task.isCancelled, requests[id] != nil else { return }
                    let mime = ["js": "text/javascript", "hhc": "text/html", "hhk": "text/html"][url.pathExtension] ?? UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                        "Content-Type": mime, "Content-Length": String(data.count), "Access-Control-Allow-Origin": "*"
                    ])!
                    schemeTask.didReceive(response); schemeTask.didReceive(data); schemeTask.didFinish()
                } catch { if !Task.isCancelled, requests[id] != nil { schemeTask.didFailWithError(error) } }
                requests.removeValue(forKey: id)
            }
        }
        func webView(_ view: WKWebView, stop schemeTask: WKURLSchemeTask) { requests.removeValue(forKey: ObjectIdentifier(schemeTask))?.cancel() }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "location":
                state.cfi = body["cfi"] as? String; state.fraction = body["fraction"] as? Double ?? 0; state.persist()
            case "toc", "results":
                if let items = body["items"], let data = try? JSONSerialization.data(withJSONObject: items),
                   let toc = try? JSONDecoder().decode([ContentsItem].self, from: data) { state.outline = toc }
                if type == "results" { state.showContents = true }
            case "status": state.status = body["message"] as? String ?? ""
            case "error": state.error = body["message"] as? String ?? "Unable to render book"
            case "external":
                if let href = body["href"] as? String, let url = URL(string: href), ["https", "http", "mailto"].contains(url.scheme) { NSWorkspace.shared.open(url) }
            default: break
            }
        }
        func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let scheme = action.request.url?.scheme ?? ""
            decisionHandler(["leaf", "blob", "about", "data"].contains(scheme) ? .allow : .cancel)
        }
    }
}
#endif
