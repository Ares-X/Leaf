import Foundation
import XCTest
@testable import LeafCore

final class ProductRegressionTests: XCTestCase {
    private let novel = "卷一\n\n第一章卷宗疑云\n\n正文。\n\n第二章 新的开始\n"

    func testWindowsChapterLineNumbers() {
        let text = "第一章 起点\n\n正文。\n\n第二章 终点\n"
        let expected = ChapterDetector.detect(text)
        XCTAssertEqual(expected.map(\.line), [0, 4])
        XCTAssertEqual(ChapterDetector.detect(text.replacingOccurrences(of: "\n", with: "\r\n")), expected)
    }

    func testClassicMacChapterLineNumbers() {
        let text = "第一章 起点\n\n正文。\n\n第二章 终点\n"
        XCTAssertEqual(ChapterDetector.detect(text.replacingOccurrences(of: "\n", with: "\r")), ChapterDetector.detect(text))
    }

    func testVolumeWordsInChapterTitleDoNotChangeHierarchy() {
        XCTAssertEqual(ChapterDetector.detect(novel).map(\.depth), [0, 1, 1])
    }


    func testBOMDoesNotHideFirstChapter() {
        let text = "第一章 起点\n\n正文。\n\n第二章 终点\n"
        XCTAssertEqual(ChapterDetector.detect("\u{feff}" + text), ChapterDetector.detect(text))
    }

    func testDuplicateComicNamesAppearOnce() throws {
        let url = try duplicateArchive()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try Archive(url).images, ["1.png"])
    }


    func testSniffSupportsNonzeroBasedDataSlice() {
        var bytes = Data(repeating: 0xaa, count: 32)
        bytes.append(contentsOf: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        let slice = bytes.dropFirst(32)
        XCTAssertEqual(slice.startIndex, 32)
        XCTAssertEqual(Format.sniff(slice), .image)
    }

    func testLineOffsetsUseUTF16AndAllSupportedNewlines() {
        for newline in ["\n", "\r\n", "\r", "\u{0085}", "\u{2028}", "\u{2029}"] {
            let text = "😀" + newline + "第二行" + newline
            let n = newline.utf16.count
            XCTAssertEqual(ChapterDetector.lineOffsets(text), [0, 2 + n, 5 + 2 * n], "newline: \(Array(newline.utf16))")
        }
    }

    func testControlWhitespaceDoesNotCreatePhantomLine() {
        for control in ["\u{000b}", "\u{000c}"] {
            let text = "正文" + control + "第一章 标题\n\n正文\n\n第二章 标题\n"
            XCTAssertEqual(ChapterDetector.detect(text).map(\.line), [4])
            XCTAssertEqual(ChapterDetector.lineOffsets("a" + control + "b" + control), [0])
        }
    }

    func testEmptyAndTerminalLines() {
        XCTAssertEqual(ChapterDetector.lineOffsets(""), [0])
        XCTAssertEqual(ChapterDetector.lineOffsets("正文"), [0])
        XCTAssertEqual(ChapterDetector.lineOffsets("\r\n"), [0, 2])
        XCTAssertEqual(ChapterDetector.lineOffsets("\n\n"), [0, 1, 2])
    }

    func testCancelledArchiveReadDoesNotPoisonNextRead() async throws {
        let url = try duplicateArchive()
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try Archive(url)
        let read = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try archive.data("1.png")
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }
        let cancelled = await read.value
        XCTAssertTrue(cancelled)
        XCTAssertEqual(try archive.data("1.png"), Data("first".utf8))
    }

    private func duplicateArchive() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".cbz")
        let fixture = "UEsDBBQAAAAAAOJ9PV1X7nGSBQAAAAUAAAAFAAAAMS5wbmdmaXJzdFBLAwQUAAAAAADifT1daREftgYAAAAGAAAABQAAADEucG5nc2Vjb25kUEsBAhQDFAAAAAAA4n09XVfucZIFAAAABQAAAAUAAAAAAAAAAAAAAIABAAAAADEucG5nUEsBAhQDFAAAAAAA4n09XWkRH7YGAAAABgAAAAUAAAAAAAAAAAAAAIABKAAAADEucG5nUEsFBgAAAAACAAIAZgAAAFEAAAAAAA=="
        try XCTUnwrap(Data(base64Encoded: fixture)).write(to: url)
        return url
    }
}
