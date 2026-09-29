#if os(macOS)
import SwiftUI
import AppKit
struct TextReaderView:View{let url:URL;let markdown:Bool;@State var text="";var body:some View{ScrollView{Text(text).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.topLeading).padding(32)}.task{if let d=try? Data(contentsOf:url){text=String(data:d,encoding:.utf8) ?? String(decoding:d,as:UTF8.self)}}}}
#endif
