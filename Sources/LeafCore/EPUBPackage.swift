import Foundation
#if os(Linux)
import FoundationXML
#endif
public struct EPUBPackage:Sendable {
    public let packagePath:String,title:String?,orderedContentPaths:[String]
    public static func load(from url:URL)throws->EPUBPackage {
        let z=try ZipArchive(url:url), c=Container(), p=XMLParser(data:try z.data(forPath:"META-INF/container.xml"));p.delegate=c
        guard p.parse(),let path=c.path else{throw ZipError.invalid}
        let op=Package(),x=XMLParser(data:try z.data(forPath:path));x.delegate=op;guard x.parse() else{throw ZipError.invalid}
        let base=(path as NSString).deletingLastPathComponent
        return .init(packagePath:path,title:op.title,orderedContentPaths:op.spine.compactMap{op.items[$0]}.map{base.isEmpty ? $0:(base as NSString).appendingPathComponent($0)})
    }
}
private final class Container:NSObject,XMLParserDelegate{var path:String?;func parser(_ p:XMLParser,didStartElement e:String,namespaceURI:String?,qualifiedName:String?,attributes a:[String:String]=[:]){if e.split(separator:":").last=="rootfile"{path=a["full-path"]}}}
private final class Package:NSObject,XMLParserDelegate{
    var items:[String:String]=[:],spine:[String]=[],title:String?,inTitle=false,buf=""
    func parser(_ p:XMLParser,didStartElement e:String,namespaceURI:String?,qualifiedName:String?,attributes a:[String:String]=[:]){switch String(e.split(separator:":").last ?? ""){case"item":if let id=a["id"],let h=a["href"]{items[id]=h.removingPercentEncoding ?? h};case"itemref":if let id=a["idref"]{spine.append(id)};case"title":inTitle=true;buf="";default:break}}
    func parser(_ p:XMLParser,foundCharacters s:String){if inTitle{buf+=s}}
    func parser(_ p:XMLParser,didEndElement e:String,namespaceURI:String?,qualifiedName:String?){if e.split(separator:":").last=="title"{title=buf;inTitle=false}}
}
