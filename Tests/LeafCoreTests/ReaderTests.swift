import Foundation
import XCTest
@testable import LeafCore

final class ReaderTests:XCTestCase{
    func testArchiveReadsDeflateZip64WithoutExtraction()throws{
        let u=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".cbz")
        try Data(base64Encoded:"UEsDBC0AAAAIAAAAIQAjyjke//////////8GABQAMTAucG5nAQAQAAMAAAAAAAAABQAAAAAAAAArSc0DAFBLAwQtAAAACAAAACEAZorKEf//////////BQAUADIucG5nAQAQAAMAAAAAAAAABQAAAAAAAAArKc8HAFBLAwQtAAAACAAAACEA8YZsev//////////BQAUADEucG5nAQAQAAMAAAAAAAAABQAAAAAAAADLz0sFAFBLAwQtAAAACAAAACEAGi8NXv//////////DQAUAC4uL2VzY2FwZS50eHQBABAAFgAAAAAAAAAYAAAAAAAAAEvNKymq1FHISy1LLVJIrSgpSkwuSU0BAFBLAwQtAAAACAAAACEAveldiP//////////FAAUAF9fTUFDT1NYL2lnbm9yZWQucG5nAQAQAAYAAAAAAAAACAAAAAAAAADLyExJSc0DAFBLAQItAy0AAAAIAAAAIQAjyjkeBQAAAAMAAAAGAAAAAAAAAAAAAACAAQAAAAAxMC5wbmdQSwECLQMtAAAACAAAACEAZorKEQUAAAADAAAABQAAAAAAAAAAAAAAgAE9AAAAMi5wbmdQSwECLQMtAAAACAAAACEA8YZsegUAAAADAAAABQAAAAAAAAAAAAAAgAF5AAAAMS5wbmdQSwECLQMtAAAACAAAACEAGi8NXhgAAAAWAAAADQAAAAAAAAAAAAAAgAG1AAAALi4vZXNjYXBlLnR4dFBLAQItAy0AAAAIAAAAIQC96V2ICAAAAAYAAAAUAAAAAAAAAAAAAACAAQwBAABfX01BQ09TWC9pZ25vcmVkLnBuZ1BLBQYAAAAABQAFABcBAABaAQAAAAA=")!.write(to:u);defer{try? FileManager.default.removeItem(at:u)}
        let a=try Archive(u);XCTAssertEqual(a.images,["1.png","2.png","10.png"]);XCTAssertEqual(try a.data("2.png"),Data("two".utf8));XCTAssertThrowsError(try a.data("missing"))
    }
    func testLegacyTextAndPrintReplica()throws{
        var t=Data("!!8-Bit!!".utf8);for i in 0..<256{t.append(1);t.append(UInt8(i))};t.append(Data("Hello".utf8));XCTAssertEqual(try LegacyText.tcr(t),Data("Hello".utf8))
        XCTAssertEqual(try LegacyText.unpackPalm([97,98,99,128,24]),Array("abcabc".utf8))
        func palm(_ payload:Data)->Data{var b=Data(repeating:0,count:110);func put(_ n:Int,_ p:Int,_ z:Int){for i in 0..<z{b[p+i]=UInt8(truncatingIfNeeded:n>>(8*(z-i-1)))}};b.replaceSubrange(60..<68,with:Data("TEXtREAd".utf8));put(2,76,2);put(94,78,4);put(110,86,4);put(1,94,2);put(payload.count,98,4);put(1,102,2);b.append(payload);return b}
        XCTAssertEqual(try LegacyText.palm(palm(Data("read me".utf8))),Data("read me".utf8))
        var unsupported=palm(Data("x".utf8));unsupported.replaceSubrange(60..<68,with:Data("DataPlkr".utf8));XCTAssertThrowsError(try LegacyText.palm(unsupported))
        let pdf=Data("%PDF-1.4\nexact\n%%EOF".utf8)
        var mop=Data("%MOP".utf8);for n in [1,1,20,pdf.count]{var x=UInt32(n).bigEndian;withUnsafeBytes(of:&x){mop.append(contentsOf:$0)}};mop.append(pdf)
        XCTAssertEqual(try LegacyText.palm(palm(mop),replica:true),pdf)
    }
    func testArchivePathSafety(){XCTAssertTrue(Archive.isSafeEntryName("OPS/chapter.xhtml"));XCTAssertFalse(Archive.isSafeEntryName("../escape.png"));XCTAssertFalse(Archive.isSafeEntryName("/absolute.png"));XCTAssertFalse(Archive.isSafeEntryName("a\\..\\escape.png"))}
    func testFormatMatrix(){XCTAssertEqual(Format.detect("BOOK.FB2.ZIP"),.book);XCTAssertEqual(Format.detect("icon.ICO"),.image);XCTAssertEqual(Format.detect("comic.CB7"),.comic);for e in Format.extensions{XCTAssertNotEqual(Format.detect("x."+e),.unknown,e)}}

    func testSignatureSniffing(){
        XCTAssertEqual(Format.sniff(Data("%PDF-1.7".utf8)),.pdf);XCTAssertEqual(Format.detect("drawing.ai"),.pdf);XCTAssertEqual(Format.sniff(Data("%!PS-Adobe-3.0".utf8)),.postscript)
        var mobi=Data(repeating:0,count:68);mobi.replaceSubrange(60..<68,with:Data("BOOKMOBI".utf8));XCTAssertEqual(Format.sniff(mobi),.book)
        XCTAssertEqual(Format.sniff(Data([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a])),.image)
        XCTAssertEqual(Format.sniff(Data("ITSF".utf8)),.chm)
        var replica=Data(repeating:0,count:68);replica.replaceSubrange(60..<68,with:Data("BOOKMOBI".utf8))
        XCTAssertEqual(Format.resolve("book.azw4",prefix:replica),.replica)
        XCTAssertEqual(Format.resolve("wrong.txt",prefix:Data("%PDF-1.7".utf8)),.pdf)
    }
}
