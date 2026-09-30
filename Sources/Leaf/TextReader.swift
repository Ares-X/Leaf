#if os(macOS)
import SwiftUI
import LeafCore

@MainActor struct TextReader: NSViewRepresentable {
    @ObservedObject var state: ReaderState
    let text: String
    func makeCoordinator() -> Coordinator { Coordinator(state) }
    func makeNSView(context: Context) -> NSScrollView {
        let content = text
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        let c = context.coordinator
        view.isEditable = false
        view.isSelectable = true
        view.usesFindBar = true
        view.string = content
        c.view = view
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            c, selector: #selector(Coordinator.scrolled), name: NSView.boundsDidChangeNotification,
            object: scroll.contentView)
        c.style(force: true)
        let scan = Task.detached(priority: .utility) {
            let lines = ChapterDetector.lineOffsets(content)
            guard !Task.isCancelled else { return ([Int](), [DetectedChapter]()) }
            return (lines, ChapterDetector.detect(content))
        }
        c.scanTask = scan
        Task { @MainActor in
            guard c.isCurrent else { return }
            state.outlineBusy = true
            let result = await scan.value
            guard c.isCurrent, !scan.isCancelled, !result.0.isEmpty else { return }
            c.lines = result.0
            c.indexed = true
            state.count = result.0.count
            state.page = min(state.page, result.0.count - 1)
            c.go(state.page)
            state.outline = result.1.map {
                .init(title: $0.title, target: String($0.line), depth: $0.depth)
            }
            state.outlineBusy = false
        }
        return scroll
    }
    func updateNSView(_ s: NSScrollView, context: Context) {
        let c = context.coordinator
        guard c.isCurrent else { return }
        c.style()
        guard c.command != state.command.revision else { return }
        c.command = state.command.revision
        switch state.command.action {
        case .zoom(let value):
            c.zoom = value
            c.style()
        case .fit(_):
            c.zoom = 1
            c.style()
        case .style: c.style(force: true)
        case .page(let page): c.go(page)
        case .href(let target): c.go(Int(target) ?? 0)
        case .find(let query): c.find(query)
        case .print: if let v = c.view { NSPrintOperation(view: v).run() }
        default: break
        }
    }
    static func dismantleNSView(_ v: NSScrollView, coordinator: Coordinator) {
        coordinator.active = false
        coordinator.scanTask?.cancel()
        NotificationCenter.default.removeObserver(coordinator)
    }
    @MainActor final class Coordinator: NSObject {
        let state: ReaderState
        let documentID: UUID?
        weak var view: NSTextView?
        var active = true, indexed = false, lines = [0], command: Int?, zoom = 1.0, styleKey = ""
        var scanTask: Task<([Int], [DetectedChapter]), Never>?
        init(_ s: ReaderState) {
            state = s
            documentID = s.document?.id
            zoom = s.zoom
        }
        var isCurrent: Bool { active && state.document?.id == documentID }
        func style(force: Bool = false) {
            guard let v = view else { return }
            let key =
                "\(state.font)|\(state.fontSize)|\(state.lineHeight)|\(state.margin)|\(state.resolvedTheme)|\(zoom)"
            if !force, key == styleKey { return }
            styleKey = key
            let size = state.fontSize * zoom
            let base = NSFont.systemFont(ofSize: size)
            switch state.font {
            case "monospace": v.font = .monospacedSystemFont(ofSize: size, weight: .regular)
            case "serif":
                v.font =
                    base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) }
                    ?? base
            default: v.font = base
            }
            v.textContainerInset = NSSize(width: state.margin, height: max(16, state.margin / 2))
            let p = NSMutableParagraphStyle()
            p.lineHeightMultiple = state.lineHeight
            v.defaultParagraphStyle = p
            v.typingAttributes[.paragraphStyle] = p
            if v.string.utf16.count > 0 {
                v.textStorage?.addAttribute(
                    .paragraphStyle, value: p, range: NSRange(location: 0, length: v.string.utf16.count))
            }
            let dark =
                state.theme == "dark"
                || (state.theme == "system"
                    && NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            v.textColor = dark ? NSColor(white: 0.86, alpha: 1) : .textColor
            v.backgroundColor = dark ? NSColor(white: 0.07, alpha: 1) : .textBackgroundColor
        }
        func go(_ n: Int) {
            view?.scrollRangeToVisible(
                NSRange(location: lines[max(0, min(n, lines.count - 1))], length: 0))
        }
        func find(_ q: String) {
            guard let v = view, !q.isEmpty else { return }
            let t = v.string as NSString
            let start = NSMaxRange(v.selectedRange())
            var r = t.range(
                of: q, options: .caseInsensitive,
                range: NSRange(location: min(start, t.length), length: max(0, t.length - start)))
            if r.location == NSNotFound { r = t.range(of: q, options: .caseInsensitive) }
            if r.location != NSNotFound {
                state.status = ""
                v.setSelectedRange(r)
                v.scrollRangeToVisible(r)
            } else {
                state.status = "No matches"
            }
        }
        @objc func scrolled() {
            guard isCurrent, indexed, let v = view, let m = v.layoutManager, let c = v.textContainer,
                m.numberOfGlyphs > 0
            else { return }
            let g = m.glyphIndex(
                for: NSPoint(x: 0, y: max(0, v.visibleRect.minY - v.textContainerInset.height)), in: c)
            let ch = m.characterIndexForGlyph(at: min(g, m.numberOfGlyphs - 1))
            var lo = 0
            var hi = lines.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if lines[mid] <= ch { lo = mid + 1 } else { hi = mid }
            }
            state.page = max(0, lo - 1)
            state.persist()
        }
    }
}
#endif
