#if os(macOS)
import Foundation

enum LitConverter {
    static func convert(_ url:URL)throws->(TemporaryDirectory,URL){
        let temp=try TemporaryDirectory(),dir=temp.url.appendingPathComponent("lit",isDirectory:true)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let bundled=Bundle.main.resourceURL?.appendingPathComponent("Tools/clit").path
        let candidates=[bundled,"/opt/homebrew/bin/clit","/usr/local/bin/clit"].compactMap{$0}
        guard let clit=candidates.first(where:{FileManager.default.isExecutableFile(atPath:$0)}) else{throw ReadError("Microsoft Reader LIT support needs the bundled ConvertLIT helper.")}
        try run(clit,[url.path,dir.path])
        let files=(FileManager.default.enumerator(at:dir,includingPropertiesForKeys:nil)?.allObjects as? [URL]) ?? []
        guard let opf=files.first(where:{$0.pathExtension.lowercased()=="opf"}) else{throw ReadError("LIT contains no OEB package")}
        let rel=opf.path.replacingOccurrences(of:dir.path+"/",with:"")
        let meta=dir.appendingPathComponent("META-INF",isDirectory:true);try FileManager.default.createDirectory(at:meta,withIntermediateDirectories:true)
        try Data("application/epub+zip".utf8).write(to:dir.appendingPathComponent("mimetype"))
        let xml="<?xml version=\"1.0\"?><container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\"><rootfiles><rootfile full-path=\"\(rel)\" media-type=\"application/oebps-package+xml\"/></rootfiles></container>"
        try Data(xml.utf8).write(to:meta.appendingPathComponent("container.xml"))
        let epub=temp.url.appendingPathComponent("book.epub")
        try run("/usr/bin/zip",["-q","-X","-0",epub.path,"mimetype"],cwd:dir)
        try run("/usr/bin/zip",["-q","-X","-r","-9",epub.path,".","-x","mimetype"],cwd:dir)
        return(temp,epub)
    }
    private static func run(_ exe:String,_ args:[String],cwd:URL?=nil)throws{
        let p=Process();p.executableURL=URL(fileURLWithPath:exe);p.arguments=args;p.currentDirectoryURL=cwd
        let pipe=Pipe();p.standardOutput=pipe;p.standardError=pipe;try p.run();p.waitUntilExit()
        guard p.terminationStatus==0 else{let d=pipe.fileHandleForReading.readDataToEndOfFile();throw ReadError(String(data:d,encoding:.utf8) ?? "Conversion failed")}
    }
}
#endif
