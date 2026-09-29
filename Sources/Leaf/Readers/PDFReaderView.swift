#if os(macOS)
import SwiftUI
import PDFKit
struct PDFReaderView:NSViewRepresentable {
    let url:URL
    func makeCoordinator()->Coordinator{Coordinator(url)}
    func makeNSView(context:Context)->PDFView{
        let v=PDFView();v.autoScales=true;v.displayMode=.singlePageContinuous;v.document=PDFDocument(url:url)
        if let d=v.document,d.pageCount>0{v.go(to:d.page(at:min(Progress.get(url),d.pageCount-1))!)}
        NotificationCenter.default.addObserver(context.coordinator,selector:#selector(Coordinator.changed(_:)),name:.PDFViewPageChanged,object:v)
        return v
    }
    func updateNSView(_ v:PDFView,context:Context){}
    final class Coordinator:NSObject{let url:URL;init(_ u:URL){url=u};@objc func changed(_ n:Notification){guard let v=n.object as? PDFView,let d=v.document,let p=v.currentPage else{return};Progress.set(d.index(for:p),url)}}
}
#endif
