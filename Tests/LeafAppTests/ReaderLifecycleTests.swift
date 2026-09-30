#if os(macOS)
import AppKit
import PDFKit
import XCTest
@testable import Leaf

final class ReaderLifecycleTests: XCTestCase {
    private func fixture(_ text: String, extension ext: String = "txt") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Leaf-test-" + UUID().uuidString + "." + ext)
        try Data(text.utf8).write(to: url)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
            for prefix in ["position:", "bookmark:"] {
                UserDefaults.standard.removeObject(forKey: prefix + url.standardizedFileURL.path)
            }
        }
        return url
    }

    @MainActor
    private func waitUntilIdle(_ state: ReaderState) async throws {
        let deadline = Date().addingTimeInterval(5)
        while state.busy, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(state.busy, "Document loading did not finish")
    }

    func testSameURLProducesNewDocumentIdentityAndContent() throws {
        let url = try fixture("old")
        let old = try ReadingDocument.open(url)
        try Data("new".utf8).write(to: url, options: .atomic)
        let new = try ReadingDocument.open(url)
        XCTAssertEqual(old.url, new.url)
        XCTAssertNotEqual(old.id, new.id)
        guard case .text(let content) = new.content else { return XCTFail("Expected text") }
        XCTAssertEqual(content, "new")
    }

    func testMalformedPDFIsRejectedBeforeReplacingTheReader() throws {
        let url = try fixture("%PDF-1.7\nnot a PDF document", extension: "pdf")
        XCTAssertThrowsError(try ReadingDocument.open(url))
    }

    @MainActor
    func testPDFContentContainsTheParsedDocument() throws {
        let url = try fixture("", extension: "pdf")
        let pdf = PDFDocument()
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 300, height: 400), for: .mediaBox)
        pdf.insert(page, at: 0)
        try XCTUnwrap(pdf.dataRepresentation()).write(to: url)
        let opened = try ReadingDocument.open(url)
        guard case .pdf(let parsed) = opened.content else { return XCTFail("Expected PDF") }
        XCTAssertEqual(parsed.pageCount, 1)
        XCTAssertFalse(parsed.isLocked)
    }

    @MainActor
    func testReloadReplacesContentButKeepsReadingSettings() async throws {
        let url = try fixture("one\ntwo\nthree")
        let state = ReaderState()
        defer { state.close() }
        state.open(url)
        try await waitUntilIdle(state)
        let old = try XCTUnwrap(state.document)
        state.page = 1
        state.zoom = 1.75
        state.fit = "custom"
        state.rotation = 90
        state.fontSize = 23
        try Data("one\nchanged\nthree".utf8).write(to: url, options: .atomic)
        state.reload()
        try await waitUntilIdle(state)
        let new = try XCTUnwrap(state.document)
        XCTAssertNotEqual(new.id, old.id)
        guard case .text(let content) = new.content else { return XCTFail("Expected text") }
        XCTAssertEqual(content, "one\nchanged\nthree")
        XCTAssertEqual(state.page, 1)
        XCTAssertEqual(state.zoom, 1.75)
        XCTAssertEqual(state.fit, "custom")
        XCTAssertEqual(state.rotation, 90)
        XCTAssertEqual(state.fontSize, 23)
    }

    @MainActor
    func testFailedReloadKeepsOldDocumentAndPosition() async throws {
        let url = try fixture("still readable")
        let state = ReaderState()
        defer { state.close() }
        state.open(url)
        try await waitUntilIdle(state)
        let old = try XCTUnwrap(state.document)
        state.page = 4
        try FileManager.default.removeItem(at: url)
        state.reload()
        try await waitUntilIdle(state)
        XCTAssertEqual(state.document?.id, old.id)
        XCTAssertEqual(state.page, 4)
        XCTAssertNotNil(state.error)
        state.close()
        XCTAssertNil(state.error)
        XCTAssertEqual(state.page, 0)
    }

    @MainActor
    func testPageCommandsRespectBothDocumentEdges() {
        let state = ReaderState()
        XCTAssertFalse(state.canGoBackward)
        XCTAssertFalse(state.canGoForward)
        state.count = 3
        XCTAssertFalse(state.canGoBackward)
        XCTAssertTrue(state.canGoForward)
        state.page = 2
        XCTAssertTrue(state.canGoBackward)
        XCTAssertFalse(state.canGoForward)
    }

    @MainActor
    func testCancelledSearchIgnoresQueuedResultsAndCompletion() {
        let state = ReaderState()
        let pdf = PDFDocument()
        state.document = ReadingDocument(url: URL(fileURLWithPath: "/search.pdf"), content: .pdf(pdf))
        let coordinator = PDFReader.Coordinator(state)
        let generation = coordinator.searchGeneration
        coordinator.cancelFind()
        state.status = "new status"
        let result = Notification(
            name: .PDFDocumentDidFindMatch, object: pdf,
            userInfo: ["PDFDocumentFoundSelection": PDFSelection(document: pdf)])
        coordinator.found(result, generation: generation)
        coordinator.finished(generation: generation)
        XCTAssertTrue(coordinator.results.isEmpty)
        XCTAssertEqual(state.status, "new status")
        XCTAssertTrue(coordinator.searchObservers.isEmpty)
    }

    @MainActor
    func testReplacedDocumentIgnoresOldReaderCallbacks() {
        let state = ReaderState()
        let url = URL(fileURLWithPath: "/same.pdf")
        state.document = ReadingDocument(url: url, content: .pdf(PDFDocument()))
        let coordinator = PDFReader.Coordinator(state)
        state.document = ReadingDocument(url: url, content: .pdf(PDFDocument()))
        state.status = "replacement"
        coordinator.finished(generation: coordinator.searchGeneration)
        XCTAssertFalse(coordinator.isCurrent)
        XCTAssertEqual(state.status, "replacement")
    }

    @MainActor
    func testPDFContentsPreserveHierarchyAndGoToActions() {
        let pdf = PDFDocument()
        let page = PDFPage()
        pdf.insert(page, at: 0)
        let root = PDFOutline()
        let part = PDFOutline()
        part.label = "Part"
        let chapter = PDFOutline()
        chapter.label = "Chapter"
        chapter.action = PDFActionGoTo(destination: PDFDestination(page: page, at: .zero))
        part.insertChild(chapter, at: 0)
        root.insertChild(part, at: 0)
        pdf.outlineRoot = root
        let contents = PDFReader.Coordinator.contents(pdf)
        XCTAssertEqual(contents.map(\.title), ["Chapter"])
        XCTAssertEqual(contents.map(\.target), ["0"])
        XCTAssertEqual(contents.map(\.depth), [1])
    }

    @MainActor
    func testTextReaderRestoresZoomAndClearsOldFindStatus() {
        _ = NSApplication.shared
        let state = ReaderState()
        state.zoom = 1.75
        state.font = "monospace"
        state.fontSize = 20
        let coordinator = TextReader.Coordinator(state)
        let view = NSTextView()
        view.string = "first second"
        coordinator.view = view
        coordinator.style()
        XCTAssertEqual(coordinator.zoom, 1.75)
        XCTAssertEqual(view.font?.pointSize, 35)
        coordinator.find("absent")
        XCTAssertEqual(state.status, "No matches")
        coordinator.find("second")
        XCTAssertEqual(state.status, "")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 6, length: 6))
    }
}
#endif
