#if os(macOS)
import AppKit
import SwiftUI
import ImageIO
import LeafCore

actor Pages{
    private let archive:Archive?;private let names:[String];private let url:URL;private var native:NativeFile?;private let source:CGImageSource?;let count:Int;private var cache:[(String,CGImage)]=[]
    init(_ url:URL,format:Format)throws{self.url=url
        if format == .comic && url.hasDirectoryPath{archive=nil;source=nil;let f=FileManager.default.enumerator(at:url,includingPropertiesForKeys:nil,options:[.skipsHiddenFiles])?.allObjects as? [URL] ?? [];names=f.filter{Format.detect($0.lastPathComponent) == .image}.map{String($0.path.dropFirst(url.path.count+(url.path.hasSuffix("/") ? 0:1)))}.sorted{$0.localizedStandardCompare($1) == .orderedAscending};count=names.count}
        else if format == .comic{let a=try Archive(url);archive=a;source=nil;names=url.pathExtension.lowercased()=="ora" ? a.entries.filter{$0.name=="mergedimage.png"}.map(\.name):a.images;count=names.count}
        else if format == .image,let s=CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary){source=s;archive=nil;names=[];count=CGImageSourceGetCount(s)}
        else{source=nil;archive=nil;names=[];let n=try NativeFile(url,engine:format == .djvu ? "DjVu":(url.pathExtension.lowercased()=="jxl" ? "JPEGXL":"MuPDF"));native=n;count=n.count}
        guard count>0 else{throw ReadError("No readable pages found")}
    }
    func image(_ page:Int,width:Int)throws->CGImage{try Task.checkCancellation();guard(0..<count).contains(page)else{throw ReadError("Page out of range")};let width=max(128,width),key="\(page):\(width)";if let i=cache.firstIndex(where:{$0.0==key}){let h=cache.remove(at:i);cache.append(h);return h.1};let image:CGImage
        if let native{image=try native.image(page,width:width)}else{let data=try archive.map{try $0.data(names[page])} ?? (url.hasDirectoryPath ? Data(contentsOf:url.appendingPathComponent(names[page])):nil);let s=data.flatMap{CGImageSourceCreateWithData($0 as CFData,[kCGImageSourceShouldCache:false] as CFDictionary)} ?? source,index=source != nil ? page:0;let o:[CFString:Any]=[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:width,kCGImageSourceShouldCacheImmediately:true];if let s,let d=CGImageSourceCreateThumbnailAtIndex(s,index,o as CFDictionary){image=d}else if let data{let t=try TemporaryDirectory(),f=t.url.appendingPathComponent(URL(fileURLWithPath:names[page]).lastPathComponent);try data.write(to:f);image=try NativeFile(f,engine:f.pathExtension.lowercased()=="jxl" ? "JPEGXL":"MuPDF").image(0,width:width)}else{throw ReadError("The installed image decoder cannot read this image")}}
        cache.append((key,image));while cache.count>3 || (cache.count>1 && cache.reduce(0,{$0+$1.1.bytesPerRow*$1.1.height})>64*1024*1024){cache.removeFirst()};return image}
    func frameDelay(_ p:Int)->Double?{guard url.pathExtension.lowercased()=="gif",count>1,let source,let props=CGImageSourceCopyPropertiesAtIndex(source,p,nil) as? [CFString:Any],let gif=props[kCGImagePropertyGIFDictionary] as? [CFString:Any]else{return nil};return max(0.02,gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? gif[kCGImagePropertyGIFDelayTime] as? Double ?? 0.1)}
    func find(_ q:String,after p:Int)->Int?{guard let native,native.hasText,!q.isEmpty else{return nil};for o in 1...count{if Task.isCancelled{return nil};let i=(p+o)%count;if native.text(i)?.localizedCaseInsensitiveContains(q)==true{return i}};return nil}
}

@MainActor struct RasterReader:View{
    @ObservedObject var state:ReaderState;let pages:Pages;@State private var images:[CGImage]=[],isAnimation=false,playing=false,pinchStart:Double?
    var body:some View{GeometryReader{g in
        let scale=NSScreen.main?.backingScaleFactor ?? 2,columns=max(1,state.spread ? 2:1),target=state.fit=="actual" ? 4096:max(128,Int(g.size.width*scale*max(1,state.zoom)/CGFloat(columns)))
        ZStack{background
            if state.flow=="continuous"{ScrollViewReader{proxy in ScrollView(.vertical){LazyVStack(spacing:4){ForEach(0..<state.count,id:\.self){i in LazyPage(state:state,pages:pages,index:i,width:target,scale:scale).id(i)}}}.coordinateSpace(name:"pages").onPreferenceChange(PageOffsetKey.self){v in if let i=v.min(by:{abs($0.value)<abs($1.value)})?.key,state.page != i{state.page=i;state.persist()}}.onChange(of:state.command.id){_ in if state.command.name=="page"{withAnimation{proxy.scrollTo(Int(state.command.number),anchor:.top)}}}}}
            else{ScrollView([.horizontal,.vertical]){HStack(spacing:state.spread ? 4:0){ForEach(Array((state.rtl ? Array(images.reversed()):images).enumerated()),id:\.offset){_,image in page(image,g.size,scale,columns)}}.frame(minWidth:g.size.width,minHeight:g.size.height)}
                .task(id:"\(state.page):\(target):\(state.spread):\(state.fit):\(state.zoom):\(state.rotation)"){do{var r=[try await pages.image(state.page,width:target)];if state.spread,state.page+1<state.count{r.append(try await pages.image(state.page+1,width:target))};guard !Task.isCancelled else{return};images=r;if state.page+r.count<state.count{_=try? await pages.image(state.page+r.count,width:target)}}catch{if !Task.isCancelled{state.error=error.localizedDescription}}}}
        }.focusable().onMoveCommand{d in if d == .left{state.turn(state.rtl ? 1:-1)};if d == .right{state.turn(state.rtl ? -1:1)}}
        .gesture(MagnificationGesture().onChanged{v in if pinchStart==nil{pinchStart=state.zoom};state.setZoom((pinchStart ?? state.zoom)*Double(v))}.onEnded{_ in pinchStart=nil})
    }.overlay(alignment:.topTrailing){if isAnimation{Button(playing ? "Pause":"Play"){playing.toggle()}.padding(8)}}.task{isAnimation=await pages.frameDelay(0) != nil;playing=isAnimation}
    .task(id:playing){while playing,!Task.isCancelled,let delay=await pages.frameDelay(state.page){do{try await Task.sleep(nanoseconds:UInt64(delay*1_000_000_000))}catch{return};guard !Task.isCancelled else{return};state.page=(state.page+1)%max(1,state.count)}}
    .onChange(of:state.command.id){_ in if state.command.name=="find"{let q=state.command.text,p=state.page,id=state.command.id;Task{let m=await pages.find(q,after:p);guard state.command.id==id,case .pages(let a)?=state.document?.content,a===pages else{return};if let m{state.page=m;state.persist()}else{state.status="No matching text (image-only pages have no searchable text)"}}}}
    var background:Color{state.theme=="dark" ? Color(nsColor:NSColor(white:0.06,alpha:1)):state.theme=="light" ? .white:Color(nsColor:.windowBackgroundColor)}
    func page(_ image:CGImage,_ size:CGSize,_ scale:CGFloat,_ columns:Int)->some View{let iw=CGFloat(image.width)/scale,ih=CGFloat(image.height)/scale,slot=size.width/CGFloat(columns);return Image(decorative:image,scale:scale).resizable().aspectRatio(contentMode:.fit).rotationEffect(.degrees(Double(state.rotation))).frame(width:state.fit=="actual" ? iw*CGFloat(state.zoom):state.fit=="width" ? slot*CGFloat(state.zoom):nil,height:state.fit=="page" ? size.height*CGFloat(state.zoom):state.fit=="actual" ? ih*CGFloat(state.zoom):nil).frame(maxWidth:state.fit=="page" ? slot*CGFloat(state.zoom):nil)}
}
private struct PageOffsetKey:PreferenceKey{static var defaultValue:[Int:CGFloat]=[:];static func reduce(value:inout[Int:CGFloat],nextValue:()->[Int:CGFloat]){value.merge(nextValue(),uniquingKeysWith:{_,b in b})}}\n@MainActor private struct LazyPage:View{
    @ObservedObject var state:ReaderState;let pages:Pages,index:Int,width:Int,scale:CGFloat;@State private var image:CGImage?
    var body:some View{Group{if let image{Image(decorative:image,scale:scale).resizable().scaledToFit().rotationEffect(.degrees(Double(state.rotation)))}else{ProgressView().frame(height:180)}}.frame(maxWidth:.infinity).background(GeometryReader{g in Color.clear.preference(key:PageOffsetKey.self,value:[index:g.frame(in:.named("pages")).midY])}).task(id:"\(width):\(state.rotation)"){image=try? await pages.image(index,width:width)}}
}
#endif
