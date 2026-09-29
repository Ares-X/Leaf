#if os(macOS)
import SwiftUI
import AppKit
struct ImageReaderView:View{let url:URL;var body:some View{GeometryReader{g in ScrollView([.horizontal,.vertical]){if let i=NSImage(contentsOf:url){Image(nsImage:i).resizable().scaledToFit().frame(minWidth:g.size.width,minHeight:g.size.height)}}}}}
#endif
