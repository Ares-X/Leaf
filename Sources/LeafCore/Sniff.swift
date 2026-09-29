import Foundation

public extension Format{
    /// Small signature set mirrored from Sumatra's BSD GuessFileType.cpp.
    /// Extension routing still wins for ambiguous containers (ZIP/7z/RAR).
    static func sniff(_ d:Data)->Format?{
        func has(_ bytes:[UInt8],_ off:Int=0)->Bool{off>=0 && d.count>=off+bytes.count && d[off..<off+bytes.count].elementsEqual(bytes)}
        func ascii(_ s:String,_ off:Int=0)->Bool{has(Array(s.utf8),off)}
        if d.range(of:Data("%PDF-".utf8),in:d.startIndex..<min(d.endIndex,d.startIndex+1024)) != nil{return .pdf}
        if ascii("ITSF"){return .chm}
        if ascii("AT&T"){return .djvu}
        if ascii("BOOKMOBI",60){return .book}
        if ascii("TEXtREAd",60){return .palm}
        if has([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a])||has([0xff,0xd8])||ascii("GIF87a")||ascii("GIF89a")||ascii("BM")||has([0,0,1,0])||has([0x4d,0x4d,0,0x2a])||has([0x49,0x49,0x2a,0])||has([0x49,0x49,0xbc,0])||has([0x49,0x49,0xbc,1])||has([0xff,0x4f,0xff,0x51])||has([0xff,0x0a]){return .image}
        if d.count>=12,ascii("RIFF"),ascii("WEBP",8){return .image}
        if d.count>=12,has([0,0,0,0x0c,0x4a,0x58,0x4c,0x20,0x0d,0x0a,0x87,0x0a]){return .image}
        if d.count>=12,ascii("ftyp",4){let brand=String(decoding:d[8..<min(d.count,24)],as:UTF8.self);if brand.contains("heic")||brand.contains("heix")||brand.contains("mif1")||brand.contains("avif"){return .image}}
        if ascii("%!PS-Adobe-") || (ascii("\u{1b}%-12345X@PJL") && String(decoding:d,as:UTF8.self).contains("%!PS-Adobe-")){return .postscript}
        return nil
    }
}
