#if os(macOS)
import SwiftUI
import LeafCore
struct ReaderRootView:View{
    @ObservedObject var session:ReaderSession
    var body:some View{Group{if let d=session.document{reader(d).id(d.id)}else{Button("Open…",action:session.chooseFile).keyboardShortcut(.defaultAction)}}.toolbar{Button(action:session.chooseFile){Image(systemName:"folder")};if let d=session.document{Text(d.name).lineLimit(1)}}}
    @ViewBuilder func reader(_ d:OpenDocument)->some View{
        switch d.kind {
        case .pdf:PDFReaderView(url:d.url)
        case .epub:EPUBReaderView(url:d.url)
        case .text,.markdown:TextReaderView(url:d.url,markdown:d.kind == .markdown)
        case .comicZip:ComicReaderView(url:d.url)
        case .image:ImageReaderView(url:d.url)
        case .fb2:FB2ReaderView(url:d.url)
        case .mobi,.azw3:ConvertedReaderView(url:d.url,kind:"ebook")
        case .djvu:ConvertedReaderView(url:d.url,kind:"djvu")
        case .comicRar:RARComicReaderView(url:d.url)
        default:ReaderStatusView(title:"Unsupported",systemImage:"doc",message:d.name)
        }
    }
}
#endif
