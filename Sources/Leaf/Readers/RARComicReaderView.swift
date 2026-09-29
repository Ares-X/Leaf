#if os(macOS)
import SwiftUI
struct RARComicReaderView:View {
    let url:URL; @State var folder:URL?; @State var error:String?
    var body:some View{Group{if let folder{FolderComicView(folder:folder)}else if let error{ReaderStatusView(title:error,systemImage:"wrench",message:"")}else{ProgressView().task{unpack()}}}}
    func unpack(){guard let exe=Tool.find("unar") else{error="Install unar for CBR";return};let d=FileManager.default.temporaryDirectory.appendingPathComponent("Leaf-\(UUID())");try? FileManager.default.createDirectory(at:d,withIntermediateDirectories:true);do{try Tool.run(exe,["-q","-o",d.path,url.path]);folder=d}catch{error="Could not open CBR"}}
}
struct FolderComicView:View{
    let folder:URL;@State var files:[URL]=[];@State var page=0
    var body:some View{VStack(spacing:0){GeometryReader{g in ScrollView{if files.indices.contains(page),let i=NSImage(contentsOf:files[page]){Image(nsImage:i).resizable().scaledToFit().frame(minWidth:g.size.width,minHeight:g.size.height)}}};if files.count>1{HStack{Button("‹"){page=max(0,page-1)};Text("\(page+1) / \(files.count)");Button("›"){page=min(files.count-1,page+1)}}.padding(6)}}.task{let e=Set(["jpg","jpeg","png","webp","gif"]);files=((try? FileManager.default.subpathsOfDirectory(atPath:folder.path)) ?? []).map{folder.appendingPathComponent($0)}.filter{e.contains($0.pathExtension.lowercased())}.sorted{$0.path.localizedStandardCompare($1.path)==.orderedAscending}}}
}
#endif
