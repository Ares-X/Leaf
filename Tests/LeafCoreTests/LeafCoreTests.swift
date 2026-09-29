import Foundation
import XCTest
@testable import LeafCore
final class LeafCoreTests: XCTestCase {
    func testFormats() {
        XCTAssertEqual(FormatDetector.detect(fileName: "book.pdf"), .pdf)
        XCTAssertEqual(FormatDetector.detect(fileName: "book.epub"), .epub)
        XCTAssertEqual(FormatDetector.detect(fileName: "comic.cbz"), .comicZip)
    }
}
