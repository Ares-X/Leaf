#if os(macOS)
import Foundation
import SwiftUI
import WebKit
import UniformTypeIdentifiers
import LeafCore

actor CHMSource {
    let url: URL
    private let entries: [String]

    private let chm: NativeFile
    private let index: [String: Int]

    init(_ url: URL) throws {
        self.url = url

        let chm = try NativeFile(url, engine: .chm)
        self.chm = chm

        var index: [String: Int] = [:]
        var entries: [String] = []
        for i in 0..<chm.count {
            let path = String(try chm.path(i).drop(while: { $0 == "/" }))
            index[path.lowercased()] = i
            entries.append(path)
        }

        self.index = index
        self.entries = entries
    }

    func response(_ url: URL) throws -> Data {
        try Task.checkCancellation()

        if url.path == "/meta" {
            return try JSONSerialization.data(
                withJSONObject: [
                    "name": self.url.lastPathComponent,
                    "entries": entries.map { ["filename": $0] }
                ]
            )
        }

        guard url.path.hasPrefix("/entry/") else {
            throw ReadError("CHM resource not found")
        }

        let name = String(url.path.dropFirst("/entry/".count))
        guard let index = index[name.lowercased()] else {
            throw ReadError("CHM resource not found")
        }

        let data = try chm.data(index)
        let ext = (name as NSString).pathExtension.lowercased()
        if ["htm", "html", "hhc", "hhk", "css"].contains(ext) {
            return Data(ReadingDocument.decode(data).utf8)
        }
        return data
    }
}

@MainActor
struct CHMReader: NSViewRepresentable {
    @ObservedObject var state: ReaderState
    let source: CHMSource

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, source: source)
    }

    func makeNSView(context: Context) -> WKWebView {
        let coordinator = context.coordinator
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(coordinator, forURLScheme: "leaf")
        configuration.userContentController.add(coordinator, name: "leaf")

        let style = "\(state.font)|\(state.fontSize)|\(state.lineHeight)|\(state.margin)|\(state.theme)"
        let encoded = String(
            data: (try? JSONEncoder().encode(style)) ?? Data("\"\"".utf8),
            encoding: .utf8
        ) ?? "\"\""
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: "window.leafStyle=\(encoded);",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = coordinator
        view.load(URLRequest(url: URL(string: "leaf://reader/reader.html")!))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.command != state.command.revision else { return }

        coordinator.command = state.command.revision
        if case .print = state.command.action {
            view.printView(nil)
            return
        }

        if coordinator.ready {
            coordinator.deliver(state.command, to: view)
        } else {
            coordinator.pending = state.command
        }
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.requests.values.forEach { $0.cancel() }
        coordinator.requests.removeAll()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "leaf")
        view.navigationDelegate = nil
        view.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKURLSchemeHandler, WKScriptMessageHandler, WKNavigationDelegate {
        let state: ReaderState
        let source: CHMSource

        var command: Int?
        var ready = false
        var pending: ReaderCommand?
        var requests: [ObjectIdentifier: Task<Void, Never>] = [:]

        init(state: ReaderState, source: CHMSource) {
            self.state = state
            self.source = source
        }

        func deliver(_ command: ReaderCommand, to view: WKWebView) {
            let payload: [String: Any]
            switch command.action {
            case .next:
                payload = ["name": "next"]
            case .previous:
                payload = ["name": "prev"]
            case .href(let value):
                payload = ["name": "href", "text": value]
            case .zoom(let value):
                payload = ["name": "zoom", "number": value]
            case .style:
                payload = [
                    "name": "style",
                    "text": "\(state.font)|\(state.fontSize)|\(state.lineHeight)|\(state.margin)|\(state.theme)"
                ]
            case .toc:
                payload = ["name": "toc"]
            case .find(let value):
                payload = ["name": "find", "text": value]
            default:
                return
            }

            guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
            view.evaluateJavaScript("window.leafCommand?.(\(String(decoding: data, as: UTF8.self)))")
        }

        func webView(_ view: WKWebView, start task: WKURLSchemeTask) {
            let id = ObjectIdentifier(task)
            requests[id] = Task { @MainActor in
                defer { requests.removeValue(forKey: id) }
                do {
                    guard let url = task.request.url else {
                        throw ReadError("Missing resource URL")
                    }

                    let data: Data
                    if url.host == "reader" {
                        let appResource = Bundle.main.resourceURL?.appendingPathComponent("Reader")
                        let root = (
                            appResource.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                            ?? Bundle.module.url(forResource: "Reader", withExtension: nil)!
                        )
                        .standardizedFileURL
                        .resolvingSymlinksInPath()

                        let file = root
                            .appendingPathComponent(String(url.path.dropFirst()))
                            .standardizedFileURL
                            .resolvingSymlinksInPath()

                        guard file.path.hasPrefix(root.path + "/") else {
                            throw ReadError("Invalid reader resource path")
                        }

                        data = try await Task.detached {
                            try Data(contentsOf: file)
                        }.value
                    } else if url.host == "book" {
                        data = try await source.response(url)
                    } else {
                        throw ReadError("Unknown resource host")
                    }

                    guard !Task.isCancelled else { return }

                    let mime = [
                        "js": "text/javascript",
                        "hhc": "text/html",
                        "hhk": "text/html"
                    ][url.pathExtension.lowercased()]
                    ?? UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"

                    task.didReceive(
                        URLResponse(
                            url: url,
                            mimeType: mime,
                            expectedContentLength: -1,
                            textEncodingName: nil
                        )
                    )
                    task.didReceive(data)
                    task.didFinish()
                } catch {
                    if !Task.isCancelled {
                        task.didFailWithError(error)
                    }
                }
            }
        }

        func webView(_ view: WKWebView, stop task: WKURLSchemeTask) {
            let id = ObjectIdentifier(task)
            requests.removeValue(forKey: id)?.cancel()
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame,
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String
            else { return }

            switch type {
            case "toc", "results":
                if let items = body["items"],
                   let data = try? JSONSerialization.data(withJSONObject: items),
                   let decoded = try? JSONDecoder().decode([ContentsItem].self, from: data) {
                    state.outline = decoded
                }
                if type == "results" {
                    state.showContents = true
                }
            case "ready":
                ready = true
                if let pending, let view = message.webView {
                    deliver(pending, to: view)
                    self.pending = nil
                }
            case "status":
                state.status = body["message"] as? String ?? ""
            case "error":
                state.error = body["message"] as? String ?? "Unable to render book"
            case "external":
                if let href = body["href"] as? String,
                   let url = URL(string: href),
                   ["https", "http", "mailto"].contains(url.scheme) {
                    NSWorkspace.shared.open(url)
                }
            default:
                break
            }
        }

        func webView(
            _ view: WKWebView,
            decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let scheme = action.request.url?.scheme ?? ""
            decisionHandler(["leaf", "blob", "about", "data"].contains(scheme) ? .allow : .cancel)
        }
    }
}
#endif
