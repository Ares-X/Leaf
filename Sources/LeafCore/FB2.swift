import Foundation
#if os(Linux)
import FoundationXML
#endif

public enum FB2 {
    public static func html(from data:Data)->String {
        let p=Parser(); let x=XMLParser(data:data); x.delegate=p; _=x.parse()
        return "<meta charset=utf-8><style>body{max-width:46em;margin:3em auto;padding:0 2em;font:18px -apple-system;line-height:1.6}h1{text-align:center}</style>"+p.out
    }
}
private final class Parser:NSObject,XMLParserDelegate {
    var out="", text=""
    func parser(_ p:XMLParser,didStartElement e:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]=[:]) { text=""; if e=="section"{out+="<section>"} }
    func parser(_ p:XMLParser,foundCharacters s:String){text+=s}
    func parser(_ p:XMLParser,didEndElement e:String,namespaceURI:String?,qualifiedName:String?) {
        let s=text.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;")
        if e=="p"{out+="<p>\(s)</p>"} else if e=="title"{out+="<h1>\(s)</h1>"} else if e=="subtitle"{out+="<h2>\(s)</h2>"} else if e=="section"{out+="</section>"}
        text=""
    }
}
