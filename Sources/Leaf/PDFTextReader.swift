#if os(macOS)
import SwiftUI
import PDFKit

@MainActor struct PDFReader: NSViewRepresentable {
    @ObservedObject var state: ReaderState
    let url: URL
    let data: Data?
    func makeCoordinator() -> Coordinator { Coordinator(state) }
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous
        view.document = data.flatMap(PDFDocument.init(data:)) ?? PDFDocument(url: url)
        let coordinator = context.coordinator; coordinator.view = view
        NotificationCenter.default.addObserver(coordinator, selector: #selector(Coordinator.changed), name: .PDFViewPageChanged, object: view)
        coordinator.observers = [
            NotificationCenter.default.addObserver(forName: .PDFDocumentDidFindMatch, object: view.document, queue: .main) { [weak coordinator] note in
                Task { @MainActor in coordinator?.found(note) }
            },
            NotificationCenter.default.addObserver(forName: .PDFDocumentDidEndFind, object: view.document, queue: .main) { [weak coordinator] note in
                Task { @MainActor in coordinator?.finished(note) }
            }
        ]
        DispatchQueue.main.async {
            guard coordinator.active else { return }
            guard let doc = view.document else { state.error = "Cannot read PDF"; return }
            if doc.isLocked {
                let alert = NSAlert(); alert.messageText = "PDF password"
                let password = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
                alert.accessoryView = password; alert.addButton(withTitle: "Open"); alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn, doc.unlock(withPassword: password.stringValue) else {
                    state.error = "PDF is locked or the password was incorrect"; return
                }
            }
            state.count = doc.pageCount
            state.outline = coordinator.contents(doc.outlineRoot, document: doc)
            if let page = doc.page(at: min(state.page, max(0, doc.pageCount - 1))) { view.go(to: page) }
        }
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        let mode: PDFDisplayMode = state.spread ? .twoUpContinuous : .singlePageContinuous
        if view.displayMode != mode { view.displayMode = mode }
        if view.displaysRTL != state.rtl { view.displaysRTL = state.rtl }
        let c = context.coordinator
        guard c.command != state.command.id else { return }; c.command = state.command.id
        switch state.command.name {
        case "page", "href":
            let index = state.command.name == "href" ? Int(state.command.text) ?? 0 : Int(state.command.number)
            if let page = view.document?.page(at: index) { view.go(to: page) }
        case "zoom": view.autoScales = false; view.scaleFactor = view.scaleFactorForSizeToFit * CGFloat(state.command.number)
        case "fit", "flow":
            if state.fitWidth, let page = view.currentPage {
                view.autoScales = false; view.scaleFactor = max(1, view.bounds.width - 12) / page.bounds(for: .cropBox).width / (state.spread ? 2 : 1)
            } else { view.autoScales = true }
        case "find": c.find(state.command.text)
        default: break
        }
    }
    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        coordinator.active = false; view.document?.cancelFindString()
        coordinator.observers.forEach { NotificationCenter.default.removeObserver($0) }
        coordinator.observers.removeAll(); NotificationCenter.default.removeObserver(coordinator)
    }
    @MainActor final class Coordinator: NSObject {
        let state: ReaderState
        weak var view: PDFView?
        var observers: [NSObjectProtocol] = [], active = true
        var command: UUID?, query = "", results: [PDFSelection] = [], hit = -1
        init(_ state: ReaderState) { self.state = state }
        @objc func changed(_ notification: Notification) {
            guard active, let view, let doc = view.document, let page = view.currentPage else { return }
            state.page = doc.index(for: page); state.persist()
        }
        @objc func found(_ notification: Notification) {
            guard active, let selection = notification.userInfo?["PDFDocumentFoundSelection"] as? PDFSelection else { return }
            results.append(selection); state.status = "\(results.count) matches"
            if hit < 0 { select(0) }
        }
        @objc func finished(_ notification: Notification) { guard active else { return }; state.status = results.isEmpty ? "No matches" : "\(results.count) matches" }
        func find(_ text: String) {
            guard !text.isEmpty, let document = view?.document else { return }
            if query == text, !results.isEmpty { select((hit + 1) % results.count); return }
            document.cancelFindString(); query = text; results = []; hit = -1; state.status = "Searching…"
            document.beginFindString(text, withOptions: .caseInsensitive)
        }
        func select(_ index: Int) {
            hit = index; view?.setCurrentSelection(results[index], animate: true); view?.go(to: results[index])
        }
        func contents(_ node: PDFOutline?, document: PDFDocument, depth: Int = 0) -> [ContentsItem] {
            guard let node else { return [] }
            return (0..<node.numberOfChildren).flatMap { i -> [ContentsItem] in
                guard let child = node.child(at: i) else { return [] }
                var items: [ContentsItem] = []
                if let page = child.destination?.page {
                    items.append(.init(title: child.label ?? "Untitled", target: String(document.index(for: page)), depth: depth))
                }
                return items + contents(child, document: document, depth: depth + 1)
            }
        }
    }
}

@MainActor struct TextReader: NSViewRepresentable {
    @ObservedObject var state: ReaderState
    let text: String
    func makeCoordinator() -> Coordinator { Coordinator(state) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView(), view = scroll.documentView as! NSTextView
        view.isEditable = false; view.isSelectable = true; view.usesFindBar = true
        view.textContainerInset = NSSize(width: 28, height: 24)
        view.font = .systemFont(ofSize: 17); view.textColor = .labelColor; view.backgroundColor = .textBackgroundColor
        view.string = text
        let c = context.coordinator; c.view = view
        for (index, code) in text.utf16.enumerated() where code == 10 { c.lines.append(index + 1) }
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(c, selector: #selector(Coordinator.scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        DispatchQueue.main.async { guard c.active else { return }; state.count = c.lines.count; c.go(state.page) }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        guard c.command != state.command.id else { return }; c.command = state.command.id
        switch state.command.name {
        case "zoom": c.view?.font = .systemFont(ofSize: 17 * CGFloat(state.command.number))
        case "fit": c.view?.font = .systemFont(ofSize: 17)
        case "page": c.go(Int(state.command.number))
        case "find":
            guard let view = c.view, !state.command.text.isEmpty else { return }
            let text = view.string as NSString, start = NSMaxRange(view.selectedRange())
            var range = text.range(of: state.command.text, options: .caseInsensitive, range: NSRange(location: min(start, text.length), length: max(0, text.length - start)))
            if range.location == NSNotFound { range = text.range(of: state.command.text, options: .caseInsensitive) }
            if range.location != NSNotFound { view.setSelectedRange(range); view.scrollRangeToVisible(range) }
            else { state.status = "No matches" }
        default: break
        }
    }
    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) { coordinator.active = false; NotificationCenter.default.removeObserver(coordinator) }
    @MainActor final class Coordinator: NSObject {
        let state: ReaderState
        weak var view: NSTextView?
        var active = true
        var lines = [0], command: UUID?
        init(_ state: ReaderState) { self.state = state }
        func go(_ line: Int) {
            let range = NSRange(location: lines[max(0, min(line, lines.count - 1))], length: 0)
            view?.scrollRangeToVisible(range)
        }
        @objc func scrolled(_ notification: Notification) {
            guard active, let view, let manager = view.layoutManager, let container = view.textContainer, manager.numberOfGlyphs > 0 else { return }
            let origin = NSPoint(x: 0, y: max(0, view.visibleRect.minY - view.textContainerInset.height))
            let glyph = manager.glyphIndex(for: origin, in: container), char = manager.characterIndexForGlyph(at: min(glyph, manager.numberOfGlyphs - 1))
            var lo = 0, hi = lines.count
            while lo < hi { let mid = (lo + hi) / 2; if lines[mid] <= char { lo = mid + 1 } else { hi = mid } }
            state.page = max(0, lo - 1); state.persist()
        }
    }
}
#endif
