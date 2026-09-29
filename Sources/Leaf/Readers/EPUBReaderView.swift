#if os(macOS)
import SwiftUI
import WebKit
import LeafCore
struct EPUBReaderView:View{
    let url:URL;@State var root:URL?;@State var chapters:[URL]=[];@State var page=0
    var body:some View{VStack(spacing:0){if let r=root,!chapters.isEmpty{Web(file:chapters[page],root:r).id(page)}else{ProgressView()}
        if chapters.count>1{Divider();HStack{Button("‹"){go(page-1)}.keyboardShortcut(.leftArrow,modifiers:[]).disabled(page==0);Text("\(page+1) / \(chapters.count)");Button("›"){go(page+1)}.keyboardShortcut(.rightArrow,modifiers:[]).disabled(page+1==chapters.count)}.padding(6)}}.task{load()}}
    func load(){do{let b=try EPUBPackage.load(from:url),z=try ZipArchive(url:url),r=FileManager.default.temporaryDirectory.appendingPathComponent("Leaf-\(UUID())");try z.extractAll(to:r);chapters=b.orderedContentPaths.map{r.appendingPathComponent($0)};root=r;page=min(Progress.get(url),max(0,chapters.count-1))}catch{}}
    func go(_ n:Int){guard chapters.indices.contains(n) else{return};page=n;Progress.set(n,url)}
}
private struct Web:NSViewRepresentable{
    let file:URL,root:URL
    func makeNSView(context:Context)->WKWebView{let c=WKWebViewConfiguration();c.defaultWebpagePreferences.allowsContentJavaScript=false;let w=WKWebView(frame:.zero,configuration:c);w.loadFileURL(file,allowingReadAccessTo:root);return w}
    func updateNSView(_ w:WKWebView,context:Context){if w.url != file{w.loadFileURL(file,allowingReadAccessTo:root)}}
}
#endif
