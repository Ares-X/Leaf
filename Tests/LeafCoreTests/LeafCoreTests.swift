import XCTest
@testable import LeafCore
final class LeafCoreTests:XCTestCase{
    func testFormats(){
        for (f,k):(String,DocumentKind) in [("a.pdf",.pdf),("a.epub",.epub),("a.fb2",.fb2),("a.cbz",.comicZip),("a.cbr",.comicRar),("a.mobi",.mobi),("a.azw3",.azw3),("a.djvu",.djvu)]{XCTAssertEqual(FormatDetector.detect(fileName:f),k)}
    }
}
