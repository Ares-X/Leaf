import Foundation

public extension Format{
    static func resolve(_ name:String,prefix:Data)->Format{
        let declared=detect(name)
        if let sniffed=sniff(prefix),declared != .replica,declared != .lit{return sniffed}
        return declared
    }
    static func resolve(_ url:URL,prefix:Data)throws->Format{
        let basic=resolve(url.lastPathComponent,prefix:prefix)
        guard basic == .comic,prefix.starts(with:[0x50,0x4b,0x03,0x04]) else{return basic}
        let archive=try Archive(url)
        if archive.contains("META-INF/container.xml") || ((try? archive.data("mimetype")).flatMap{String(data:$0,encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines)}).map({$0=="application/epub+zip" || $0=="application/x-ibooks+zip"}) == true{return .book}
        if archive.contains("_rels/.rels") || archive.contains("_rels/.rels/[0].piece") || archive.contains("_rels/.rels/[0].last.piece"){return .mupdf}
        let files=archive.entries.map{$0.name.lowercased()}
        if files.filter({$0.hasSuffix(".fb2")}).count == 1 && files.allSatisfy({$0.hasSuffix(".fb2") || $0.hasSuffix(".url")}){return .book}
        return basic
    }

    /// Small signature set mirrored from Sumatra's BSD GuessFileType.cpp.
    /// Extension routing still wins for ambiguous containers (ZIP/7z/RAR).
    static func sniff(_ d:Data)->Format?{
        func has(_ bytes:[UInt8],_ off:Int=0)->Bool{off>=0 && d.count>=off+bytes.count && d[d.startIndex+off..<d.startIndex+off+bytes.count].elementsEqual(bytes)}
        func ascii(_ s:String,_ off:Int=0)->Bool{has(Array(s.utf8),off)}
        if d.range(of:Data("%PDF-".utf8),in:d.startIndex..<min(d.endIndex,d.startIndex+1024)) != nil{return .pdf}
        if ascii("Rar!\u{1a}\u{07}\u{00}") || has([0x52,0x61,0x72,0x21,0x1a,0x07,0x01,0x00]) || has([0x37,0x7a,0xbc,0xaf,0x27,0x1c]) || has([0x50,0x4b,0x03,0x04]){return nil}
        if ascii("ITOLITLS"){return .lit}
        if ascii("ITSF"){return .chm}
        if ascii("AT&T"){return .djvu}
        if ascii("BOOKMOBI",60){return .book}
        if ascii("TEXtREAd",60){return .palm}
        if has([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a])||has([0xff,0xd8])||ascii("GIF87a")||ascii("GIF89a")||ascii("BM")||ascii("BA")||has([0,0,1,0])||has([0x4d,0x4d,0,0x2a])||has([0x49,0x49,0x2a,0])||has([0x49,0x49,0xbc,0])||has([0x49,0x49,0xbc,1])||has([0xff,0x4f,0xff,0x51])||has([0xff,0x0a]){return .image}
        if d.count>=12,ascii("RIFF"),ascii("WEBP",8){return .image}
        if d.count>=12,has([0,0,0,0x0c,0x4a,0x58,0x4c,0x20,0x0d,0x0a,0x87,0x0a]){return .image}
        if d.count>=12,ascii("ftyp",4){let brand=String(decoding:d[d.startIndex+8..<min(d.endIndex,d.startIndex+24)],as:UTF8.self);if brand.contains("heic")||brand.contains("heix")||brand.contains("mif1")||brand.contains("avif"){return .image}}
        if ascii("%!PS-Adobe-") || (ascii("\u{1b}%-12345X@PJL") && String(decoding:d,as:UTF8.self).contains("%!PS-Adobe-")){return .postscript}
        return nil
    }
}
