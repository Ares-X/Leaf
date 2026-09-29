import Foundation

public enum Format:String,Sendable{
    case pdf,book,text,markdown,comic,image,mupdf,djvu,chm,postscript,palm,tcr,replica,html,lit,unknown
    public static let groups:[(Format,String)]=[
        (.pdf,"pdf ai"),(.book,"epub mobi azw azw1 azw3 prc fb2 fb2z fbz zfb2 fb2.zip"),
        (.replica,"azw4"),(.palm,"pdb"),(.tcr,"tcr"),(.lit,"lit"),
        (.text,"txt js json xml log nfo text diz"),(.markdown,"md markdown"),(.html,"html htm xhtml"),
        (.comic,"cbz cbr cbt cb7 zip rar tar 7z ora"),
        (.djvu,"djvu djv"),(.chm,"chm"),(.mupdf,"xps oxps xod dwfx svg jxr hdp wdp"),
        (.postscript,"ps ps.gz eps pjl"),
        (.image,"png jpg jpeg jfif gif tif tiff bmp dib ico tga webp jp2 j2k jpx jpf jpm j2c avif jxl heic heif")
    ]
    public static var extensions:[String]{groups.flatMap{$0.1.split(separator:" ").map(String.init)}}
    public static func detect(_ name:String)->Format{
        let n=name.lowercased()
        if n.hasSuffix(".fb2.zip"){return .book}
        if n.hasSuffix(".ps.gz"){return .postscript}
        if n.hasSuffix("file_id.diz") || n.hasSuffix("read.me"){return .text}
        return groups.first{_,s in s.split(separator:" ").contains{n.hasSuffix("."+$0)}}?.0 ?? .unknown
    }
}
public struct ReadError:LocalizedError,Sendable{public let message:String;public init(_ message:String){self.message=message};public var errorDescription:String?{message}}
