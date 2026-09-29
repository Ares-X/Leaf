#if os(macOS)
import AppKit
import PDFKit
import LeafCore

func runLeafProcess(_ process:Process)throws{
    try process.run()
    while process.isRunning{if Task.isCancelled{process.terminate();process.waitUntilExit();throw CancellationError()};Thread.sleep(forTimeInterval:0.05)}
    process.waitUntilExit()
}

final class TemporaryDirectory{let url=FileManager.default.temporaryDirectory.appendingPathComponent("Leaf-"+UUID().uuidString,isDirectory:true);init()throws{try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)};deinit{try? FileManager.default.removeItem(at:url)}}

struct ReadingDocument{
    enum Content{case pdf(URL,Data?),text(String),book(BookSource),pages(Pages)}
    let url:URL,content:Content,temporary:TemporaryDirectory?
    init(url:URL,content:Content,temporary:TemporaryDirectory?=nil){self.url=url;self.content=content;self.temporary=temporary}
    static func open(_ url:URL)throws->ReadingDocument{
        try Task.checkCancellation()
        if (try? url.resourceValues(forKeys:[.isDirectoryKey]).isDirectory)==true{let f=URL(fileURLWithPath:url.path,isDirectory:true);return .init(url:f,content:.pages(try Pages(f,format:.comic)))}
        let fh=try FileHandle(forReadingFrom:url),prefix=try fh.read(upToCount:128) ?? Data();try fh.close()
        let format=Format.resolve(url.lastPathComponent,prefix:prefix)

        switch format{
        case .pdf:guard PDFDocument(url:url) != nil else{throw ReadError("Cannot read PDF: \(url.lastPathComponent)")};return .init(url:url,content:.pdf(url,nil))
        case .replica:return .init(url:url,content:.pdf(url,try LegacyText.palm(Data(contentsOf:url,options:.mappedIfSafe),replica:true)))
        case .text,.palm,.tcr:
            var d=try Data(contentsOf:url,options:.mappedIfSafe);if format == .palm{d=try LegacyText.palm(d)};if format == .tcr{d=try LegacyText.tcr(d)};return .init(url:url,content:.text(decode(d)))
        case .book,.markdown:
            do{return .init(url:url,content:.pages(try Pages(url,format:.mupdf)))}
            catch{return .init(url:url,content:.book(try BookSource(url,format:format)))}
        case .html,.chm:return .init(url:url,content:.book(try BookSource(url,format:format)))
        case .lit:
            let (temp,opf)=try LitConverter.convert(url);return .init(url:url,content:.book(try BookSource(opf,format:.book,root:opf.deletingLastPathComponent())),temporary:temp)
        case .image,.comic,.mupdf,.djvu:return .init(url:url,content:.pages(try Pages(url,format:format)))
        case .postscript:
            let candidates=["/opt/homebrew/bin/gs","/usr/local/bin/gs","/usr/bin/gs"];guard let gs=candidates.first(where:{FileManager.default.isExecutableFile(atPath:$0)})else{throw ReadError("PostScript/PJL needs Ghostscript.")}
            let temp=try TemporaryDirectory(),out=temp.url.appendingPathComponent("document.pdf"),input:URL
            if url.lastPathComponent.lowercased().hasSuffix(".ps.gz"){
                input=temp.url.appendingPathComponent("document.ps");let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/gzip");p.arguments=["-dc",url.path];let h=FileManager.default.createFile(atPath:input.path,contents:nil) ? try FileHandle(forWritingTo:input):nil;guard let h else{throw ReadError("Cannot create temporary PostScript")};p.standardOutput=h;try runLeafProcess(p);try h.close();guard p.terminationStatus==0 else{throw ReadError("Cannot decompress PostScript")}
            }else{input=url}
            let p=Process();p.executableURL=URL(fileURLWithPath:gs);p.arguments=["-dSAFER","-dBATCH","-dNOPAUSE","-sDEVICE=pdfwrite","-sOutputFile="+out.path,"-f",input.path];p.standardOutput=FileHandle.nullDevice;p.standardError=FileHandle.nullDevice;try runLeafProcess(p);guard p.terminationStatus==0 else{throw ReadError("Ghostscript could not convert this file.")};return .init(url:url,content:.pdf(out,nil),temporary:temp)
        default:throw ReadError("Unsupported document: \(url.lastPathComponent)")
        }
    }
    static func decode(_ d:Data)->String{if let s=String(data:d,encoding:.utf8){return s};var s:String?;_=NSString.stringEncoding(for:d,encodingOptions:[:],convertedString:&s,usedLossyConversion:nil);return s ?? String(decoding:d,as:UTF8.self)}
}
#endif
