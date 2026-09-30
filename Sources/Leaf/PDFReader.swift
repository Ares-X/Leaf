#if os(macOS)
import SwiftUI
import PDFKit

@MainActor
struct PDFReader: NSViewRepresentable {
    @ObservedObject var state: ReaderState
    let document: PDFDocument

    func makeCoordinator() -> Coordinator { Coordinator(state) }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = document
        view.postsFrameChangedNotifications = true
        let coordinator = context.coordinator
        coordinator.view = view
        let center = NotificationCenter.default
        center.addObserver(
            coordinator, selector: #selector(Coordinator.changed), name: .PDFViewPageChanged,
            object: view)
        center.addObserver(
            coordinator, selector: #selector(Coordinator.visiblePagesChanged),
            name: .PDFViewVisiblePagesChanged, object: view)
        center.addObserver(
            coordinator, selector: #selector(Coordinator.scaleChanged), name: .PDFViewScaleChanged,
            object: view)
        center.addObserver(
            coordinator, selector: #selector(Coordinator.resized),
            name: NSView.frameDidChangeNotification, object: view)
        DispatchQueue.main.async { coordinator.prepare() }
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.isCurrent else { return }
        coordinator.layout()
        coordinator.loadContents()
        guard coordinator.command != state.command.revision else { return }
        coordinator.command = state.command.revision
        switch state.command.action {
        case .page(let index):
            if let page = document.page(at: index) { view.go(to: page) }
        case .href(let target):
            if let index = Int(target), let page = document.page(at: index) { view.go(to: page) }
        case .zoom(let factor): coordinator.setZoom(factor)
        case .fit(let mode): coordinator.fit(mode)
        case .find(let query): coordinator.find(query)
        case .toc: coordinator.cancelFind()
        case .rotate:
            coordinator.applyRotation()
            coordinator.layout()
        case .print:
            document.printOperation(
                for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true)?.run()
        default: break
        }
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        coordinator.active = false
        coordinator.cancelFind()
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject {
        let state: ReaderState
        let documentID: UUID?
        let initialPage: Int
        weak var view: PDFView?
        var active = true
        var ready = false
        var command: Int?
        var outlineLoaded = false
        var ignoreScale = true
        var baseRotation: [Int: Int] = [:]
        private var lastLayout: Layout?
        private var layingOut = false
        var searchGeneration = 0
        var searchObservers: [NSObjectProtocol] = []
        var query = ""
        var results: [PDFSelection] = []
        var hit = -1
        var truncated = false

        private struct Layout: Equatable {
            let size: CGSize
            let mode: PDFDisplayMode
            let rtl: Bool
            let fit: String
            let page: Int
            let rotation: Int
        }

        init(_ state: ReaderState) {
            self.state = state
            documentID = state.document?.id
            initialPage = state.page
        }

        var isCurrent: Bool { active && state.document?.id == documentID }

        func prepare() {
            guard isCurrent, let view, let document = view.document else { return }
            var incorrectPassword = false
            while document.isLocked {
                let alert = NSAlert()
                alert.messageText = "PDF password"
                alert.informativeText =
                    incorrectPassword
                    ? "Incorrect password. Try again." : "Enter the password to open this document."
                let password = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
                alert.accessoryView = password
                alert.addButton(withTitle: "Open")
                alert.addButton(withTitle: "Cancel")
                alert.window.initialFirstResponder = password
                let response = alert.runModal()
                guard isCurrent else { return }
                guard response == .alertFirstButtonReturn else {
                    state.status = "PDF is locked — use Reload to try again"
                    return
                }
                incorrectPassword = !document.unlock(withPassword: password.stringValue)
            }
            guard document.pageCount > 0 else {
                state.error = "This PDF has no readable pages."
                return
            }
            state.count = document.pageCount
            state.page = min(initialPage, document.pageCount - 1)
            ready = true
            if let page = document.page(at: state.page) { view.go(to: page) }
            if state.fit == "custom" { setZoom(state.zoom) }
            layout()
            loadContents()
        }

        func layout() {
            guard isCurrent, ready, !layingOut, let view else { return }
            view.backgroundColor =
                state.resolvedTheme == "dark" ? NSColor(white: 0.06, alpha: 1) : .windowBackgroundColor
            let mode: PDFDisplayMode =
                state.flow == "continuous"
                ? (state.spread ? .twoUpContinuous : .singlePageContinuous)
                : (state.spread ? .twoUp : .singlePage)
            let key = Layout(
                size: view.bounds.size, mode: mode, rtl: state.rtl, fit: state.fit, page: state.page,
                rotation: state.rotation)
            guard key != lastLayout else { return }
            lastLayout = key
            layingOut = true
            defer { layingOut = false }
            if view.displayMode != mode { view.displayMode = mode }
            view.displayDirection = .vertical
            view.displaysRTL = state.rtl
            applyRotation()
            if state.fit != "custom" { fit(state.fit) }
        }

        func fit(_ mode: String) {
            guard isCurrent, ready, let view else { return }
            ignoreScale = true
            switch mode {
            case "actual":
                view.autoScales = false
                view.scaleFactor = 1
            case "width":
                if let document = view.document, let page = view.currentPage {
                    let index = document.index(for: page)
                    let first = state.spread ? index - index % 2 : index
                    let indices = first..<min(document.pageCount, first + (state.spread ? 2 : 1))
                    let width = indices.reduce(CGFloat.zero) { total, index in
                        guard let page = document.page(at: index) else { return total }
                        let box = page.bounds(for: view.displayBox)
                        let rotation = ((baseRotation[index] ?? page.rotation) + state.rotation) % 180
                        return total + (rotation == 0 ? box.width : box.height)
                    }
                    if width > 0, view.bounds.width > 12 {
                        view.autoScales = false
                        view.scaleFactor = (view.bounds.width - 12) / width
                    }
                }
            default:
                view.autoScales = true
            }
            finishScaleChange()
        }

        func setZoom(_ factor: Double) {
            guard isCurrent, let view else { return }
            ignoreScale = true
            view.autoScales = false
            view.scaleFactor = CGFloat(factor)
            finishScaleChange()
        }

        private func finishScaleChange() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrent, let view = self.view else { return }
                self.state.zoom = Double(view.scaleFactor)
                self.ignoreScale = false
            }
        }

        @objc func scaleChanged() {
            guard isCurrent, ready, !ignoreScale, let view else { return }
            state.zoom = Double(view.scaleFactor)
            if !view.autoScales { state.fit = "custom" }
        }

        @objc func resized() {
            DispatchQueue.main.async { [weak self] in self?.layout() }
        }

        @objc func visiblePagesChanged() { applyRotation() }

        func applyRotation() {
            guard isCurrent, let view, let document = view.document,
                state.rotation != 0 || !baseRotation.isEmpty
            else { return }
            for page in view.visiblePages {
                let index = document.index(for: page)
                let base = baseRotation[index] ?? page.rotation
                baseRotation[index] = base
                let rotation = (base + state.rotation + 360) % 360
                if page.rotation != rotation { page.rotation = rotation }
            }
        }

        @objc func changed() {
            guard isCurrent, ready, let view, let document = view.document, let page = view.currentPage
            else { return }
            state.page = document.index(for: page)
            state.persist()
            layout()
        }

        func loadContents() {
            guard isCurrent, ready, state.showContents, !outlineLoaded else { return }
            outlineLoaded = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrent, let document = self.view?.document else { return }
                self.state.outline = Self.contents(document)
            }
        }

        static func contents(_ document: PDFDocument) -> [ContentsItem] {
            guard let root = document.outlineRoot else { return [] }
            var stack: [(PDFOutline, Int)] = [(root, -1)]
            var items: [ContentsItem] = []
            while let (node, depth) = stack.popLast() {
                if depth >= 0,
                    let page = (node.destination ?? (node.action as? PDFActionGoTo)?.destination)?.page
                {
                    let index = document.index(for: page)
                    if index != NSNotFound {
                        items.append(
                            .init(title: node.label ?? "Untitled", target: String(index), depth: depth))
                    }
                }
                for index in (0..<node.numberOfChildren).reversed() {
                    if let child = node.child(at: index) { stack.append((child, depth + 1)) }
                }
            }
            return items
        }

        func cancelFind() {
            searchGeneration &+= 1
            searchObservers.forEach { NotificationCenter.default.removeObserver($0) }
            searchObservers.removeAll()
            view?.document?.cancelFindString()
            query = ""
            results.removeAll()
            hit = -1
            truncated = false
        }

        func find(_ text: String) {
            guard isCurrent, ready, let document = view?.document else { return }
            if !text.isEmpty, query == text, !results.isEmpty {
                select((hit + 1) % results.count)
                return
            }
            cancelFind()
            guard !text.isEmpty else {
                state.status = ""
                return
            }
            query = text
            let generation = searchGeneration
            let center = NotificationCenter.default
            searchObservers = [
                center.addObserver(forName: .PDFDocumentDidFindMatch, object: document, queue: .main) {
                    [weak self] notification in
                    Task { @MainActor in self?.found(notification, generation: generation) }
                },
                center.addObserver(forName: .PDFDocumentDidEndFind, object: document, queue: .main) {
                    [weak self] _ in
                    Task { @MainActor in self?.finished(generation: generation) }
                },
            ]
            state.status = "Searching…"
            document.beginFindString(text, withOptions: .caseInsensitive)
        }

        func found(_ notification: Notification, generation: Int) {
            guard isCurrent, generation == searchGeneration,
                let selection = notification.userInfo?["PDFDocumentFoundSelection"] as? PDFSelection
            else { return }
            if results.count >= 1000 {
                truncated = true
                view?.document?.cancelFindString()
                state.status = "1000+ matches"
                return
            }
            results.append(selection)
            state.status = "\(results.count) matches"
            if hit < 0 { select(0) }
        }

        func finished(generation: Int) {
            guard isCurrent, generation == searchGeneration else { return }
            state.status =
                truncated ? "1000+ matches" : results.isEmpty ? "No matches" : "\(results.count) matches"
        }

        private func select(_ index: Int) {
            hit = index
            view?.setCurrentSelection(results[index], animate: true)
            view?.go(to: results[index])
        }
    }
}
#endif
