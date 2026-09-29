import Foundation
import XCTest
@testable import LeafCore

final class ReaderTests: XCTestCase {
    func testArchiveReadsDeflateZip64WithoutExtraction() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".cbz")
        try Data(base64Encoded: "UEsDBC0AAAAIAAAAIQAjyjke//////////8GABQAMTAucG5nAQAQAAMAAAAAAAAABQAAAAAAAAArSc0DAFBLAwQtAAAACAAAACEAZorKEf//////////BQAUADIucG5nAQAQAAMAAAAAAAAABQAAAAAAAAArKc8HAFBLAwQtAAAACAAAACEA8YZsev//////////BQAUADEucG5nAQAQAAMAAAAAAAAABQAAAAAAAADLz0sFAFBLAwQtAAAACAAAACEAGi8NXv//////////DQAUAC4uL2VzY2FwZS50eHQBABAAFgAAAAAAAAAYAAAAAAAAAEvNKymq1FHISy1LLVJIrSgpSkwuSU0BAFBLAwQtAAAACAAAACEAveldiP//////////FAAUAF9fTUFDT1NYL2lnbm9yZWQucG5nAQAQAAYAAAAAAAAACAAAAAAAAADLyExJSc0DAFBLAQItAy0AAAAIAAAAIQAjyjkeBQAAAAMAAAAGAAAAAAAAAAAAAACAAQAAAAAxMC5wbmdQSwECLQMtAAAACAAAACEAZorKEQUAAAADAAAABQAAAAAAAAAAAAAAgAE9AAAAMi5wbmdQSwECLQMtAAAACAAAACEA8YZsegUAAAADAAAABQAAAAAAAAAAAAAAgAF5AAAAMS5wbmdQSwECLQMtAAAACAAAACEAGi8NXhgAAAAWAAAADQAAAAAAAAAAAAAAgAG1AAAALi4vZXNjYXBlLnR4dFBLAQItAy0AAAAIAAAAIQC96V2ICAAAAAYAAAAUAAAAAAAAAAAAAACAAQwBAABfX01BQ09TWC9pZ25vcmVkLnBuZ1BLBQYAAAAABQAFABcBAABaAQAAAAA=")!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try Archive(url)
        XCTAssertEqual(archive.images, ["1.png", "2.png", "10.png"])
        XCTAssertEqual(try archive.data("2.png"), Data("two".utf8))
        XCTAssertEqual(try archive.data("../escape.txt"), Data("entry, never extracted".utf8))
        XCTAssertThrowsError(try archive.data("missing"))
    }
    func testLegacyTextAndPrintReplicaPreserveContent() throws {
        var tcr = Data("!!8-Bit!!".utf8)
        for i in 0..<256 { tcr.append(1); tcr.append(UInt8(i)) }
        tcr.append(Data("Hello, 世界".utf8))
        XCTAssertEqual(try LegacyText.tcr(tcr), Data("Hello, 世界".utf8))
        XCTAssertThrowsError(try LegacyText.tcr(tcr.prefix(15)))
        // Three literal bytes then a length-three, distance-three back-reference.
        XCTAssertEqual(try LegacyText.unpackPalm([97, 98, 99, 128, 24]), Array("abcabc".utf8))
        XCTAssertThrowsError(try LegacyText.unpackPalm([128]))
        func palm(_ payload: Data) -> Data {
            var b = Data(repeating: 0, count: 110)
            func put(_ n: Int, at: Int, bytes: Int) { for i in 0..<bytes { b[at+i] = UInt8(truncatingIfNeeded: n >> (8 * (bytes-i-1))) } }
            b.replaceSubrange(60..<68, with: Data("BOOKMOBI".utf8))
            put(2, at: 76, bytes: 2); put(94, at: 78, bytes: 4); put(110, at: 86, bytes: 4)
            put(1, at: 94, bytes: 2); put(payload.count, at: 98, bytes: 4); put(1, at: 102, bytes: 2)
            b.append(payload); return b
        }
        XCTAssertEqual(try LegacyText.palm(palm(Data("read me".utf8))), Data("read me".utf8))
        let pdf = Data("%PDF-1.4\nkeep exact bytes\n%%EOF".utf8)
        XCTAssertEqual(try LegacyText.palm(palm(Data("%MOP".utf8) + Data(repeating: 0, count: 16) + pdf), replica: true), pdf)
    }
    func testFormatRoutingDoesNotLoseCompoundExtensions() {
        XCTAssertEqual(Format.detect("BOOK.FB2.ZIP"), .book)
        XCTAssertEqual(Format.detect("comic.zip"), .comic)
        for ext in Format.extensions { XCTAssertNotEqual(Format.detect("sample." + ext), .unknown, ext) }
        XCTAssertEqual(Format.detect("not-a-document.exe"), .unknown)
    }
}
