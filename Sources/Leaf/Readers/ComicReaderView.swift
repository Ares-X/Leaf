#if os(macOS)
import SwiftUI
import AppKit
import LeafCore
struct ComicReaderView:View{
    let url:URL;@State var archive:ZipArchive?;@State var pages:[String]=[];@State var page=0;@State var image:NSImage?
    var body:some View{VStack(spacing:0){GeometryReader{g in ScrollView([.horizontal,.vertical]){if let image{Image(nsImage:image).resizable().scaledToFit().frame(minWidth:g.size.width,minHeight:g.size.height)}}}
        if pages.count>1{Divider();HStack{Button("‹"){show(page-1)}.keyboardShortcut(.leftArrow,modifiers:[]).disabled(page==0);Text("\(page+1) / \(pages.count)");Button("›"){show(page+1)}.keyboardShortcut(.rightArrow,modifiers:[]).disabled(page+1==pages.count)}.padding(6)}}.task{load()}}
    func load(){do{archive=try ZipArchive(url:url);pages=try ComicArchiveIndex(url:url).pagePaths;show(min(Progress.get(url),max(0,pages.count-1)))}catch{}}
    func show(_ n:Int){guard pages.indices.contains(n),let archive,let d=try? archive.data(forPath:pages[n]) else{return};page=n;image=NSImage(data:d);Progress.set(n,url)}
}
#endif
