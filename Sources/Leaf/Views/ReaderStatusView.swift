#if os(macOS)
import SwiftUI
struct ReaderStatusView:View{let title:String,systemImage:String,message:String;var body:some View{VStack(spacing:12){Image(systemName:systemImage).font(.largeTitle);Text(title).font(.headline);Text(message).foregroundStyle(.secondary)}.padding()}}
#endif
