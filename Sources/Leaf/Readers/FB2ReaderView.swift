#if os(macOS)
import SwiftUI
import WebKit
import LeafCore
struct FB2ReaderView:NSViewRepresentable {
    let url:URL
    func makeNSView(context:Context)->WKWebView { let w=WKWebView(); if let d=try? Data(contentsOf:url){w.loadHTMLString(FB2.html(from:d),baseURL:nil)}; return w }
    func updateNSView(_ w:WKWebView,context:Context){}
}
#endif
