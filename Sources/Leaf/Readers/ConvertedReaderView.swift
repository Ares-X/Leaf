#if os(macOS)
import SwiftUI
struct ConvertedReaderView:View {
    let url:URL,kind:String; @State var output:URL?; @State var error:String?
    var body:some View { Group {
        if let output { if output.pathExtension=="epub"{EPUBReaderView(url:output)}else{PDFReaderView(url:output)} }
        else if let error { ReaderStatusView(title:error,systemImage:"wrench",message:"") }
        else { ProgressView().task{convert()} }
    }}
    func convert(){
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent("Leaf-\(UUID())")
        try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        do {
            if kind=="ebook",let exe=Tool.find("ebook-convert"){let dst=dir.appendingPathComponent("book.epub");try Tool.run(exe,[url.path,dst.path]);output=dst}
            else if kind=="djvu",let exe=Tool.find("ddjvu"){let dst=dir.appendingPathComponent("book.pdf");try Tool.run(exe,["-format=pdf",url.path,dst.path]);output=dst}
            else {error=kind=="ebook" ? "Install Calibre for MOBI/AZW3" : "Install DjVuLibre for DjVu"}
        } catch { error="Could not open file" }
    }
}
#endif
