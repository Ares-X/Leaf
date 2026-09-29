#if os(macOS)
import Foundation

enum LitConverter{
    static func convert(_ url:URL)throws->(TemporaryDirectory,URL){
        let temp=try TemporaryDirectory(),dir=temp.url.appendingPathComponent("lit",isDirectory:true)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let bundled=Bundle.main.resourceURL?.appendingPathComponent("Tools/clit").path
        guard let clit=[bundled,"/opt/homebrew/bin/clit","/usr/local/bin/clit"].compactMap({$0}).first(where:{FileManager.default.isExecutableFile(atPath:$0)})else{throw ReadError("Microsoft Reader LIT support needs ConvertLIT.")}
        let log=temp.url.appendingPathComponent("convertlit.log");guard FileManager.default.createFile(atPath:log.path,contents:nil),let output=try? FileHandle(forWritingTo:log) else{throw ReadError("Cannot create ConvertLIT log")}
        let p=Process();p.executableURL=URL(fileURLWithPath:clit);p.arguments=[url.path,dir.path];p.standardOutput=output;p.standardError=output;try runLeafProcess(p);try output.close()
        guard p.terminationStatus==0 else{let data=(try? Data(contentsOf:log)) ?? Data();throw ReadError(String(data:data,encoding:.utf8) ?? "LIT conversion failed")}
        let files=(FileManager.default.enumerator(at:dir,includingPropertiesForKeys:nil)?.allObjects as? [URL]) ?? []
        guard let opf=files.first(where:{$0.pathExtension.lowercased()=="opf"})else{throw ReadError("LIT contains no OEB package")}
        let meta=dir.appendingPathComponent("META-INF",isDirectory:true);try FileManager.default.createDirectory(at:meta,withIntermediateDirectories:true)
        let relative=String(opf.path.dropFirst(dir.path.count+1)).replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:""",with:"&quot;")
        let container="<?xml version=\"1.0\" encoding=\"UTF-8\"?><container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\"><rootfiles><rootfile full-path=\"\(relative)\" media-type=\"application/oebps-package+xml\"/></rootfiles></container>"
        try Data(container.utf8).write(to:meta.appendingPathComponent("container.xml"),options:.atomic)
        return(temp,dir)
    }
}
#endif
