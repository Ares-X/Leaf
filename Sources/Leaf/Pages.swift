#if os(macOS)
import AppKit
import SwiftUI
import ImageIO
import LeafCore

actor Pages{
    private static let nativeImageExtensions:Set<String>=["jxl","jxr","hdp","wdp","svg"]
    private let archive:Archive?
    private let names:[String]
    private let url:URL
    private var native:NativeFile?
    private let source:CGImageSource?
    private(set) var count:Int
    private var cache:[(String,CGImage)]=[]

    init(_ url:URL,format:Format)throws{
        self.url=url
        let ext=url.pathExtension.lowercased()
        if format == .comic && url.hasDirectoryPath{
            archive=nil;source=nil;native=nil
            let files=FileManager.default.enumerator(at:url,includingPropertiesForKeys:nil,options:[.skipsHiddenFiles])?.allObjects as? [URL] ?? []
            names=files.filter{Self.isComicImage($0.lastPathComponent)}.map{String($0.path.dropFirst(url.path.count+(url.path.hasSuffix("/") ? 0:1)))}.sorted{$0.compare($1,options:[.numeric,.caseInsensitive]) == .orderedAscending}
            count=names.count
        }else if format == .comic{
            let value=try Archive(url);archive=value;source=nil;native=nil
            names=ext=="ora" ? value.entries.filter{$0.name=="mergedimage.png"}.map(\.name):value.images
            count=names.count
        }else if format == .image && ext=="jxl"{
            source=nil;archive=nil;names=[]
            let value=try NativeFile(url,engine:.jpegXL);native=value;count=value.count
        }else if format == .image{
            archive=nil;names=[];native=nil
            guard let value=CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary) else{throw ReadError("ImageIO cannot read this image")}
            source=value;count=CGImageSourceGetCount(value)
        }else{
            source=nil;archive=nil;names=[]
            let value=try NativeFile(url,engine:format == .djvu ? .djvu:.mupdf);native=value;count=value.count
        }
        guard count>0 else{throw ReadError("No readable pages found")}
    }

    func image(_ page:Int,width:Int)throws->CGImage{
        try Task.checkCancellation()
        guard(0..<count).contains(page)else{throw ReadError("Page out of range")}
        let width=max(128,min(16384,width)),key="\(page):\(width)"
        if let i=cache.firstIndex(where:{$0.0==key}){let hit=cache.remove(at:i);cache.append(hit);return hit.1}
        let image:CGImage
        if let native{
            image=try native.image(page,width:width)
        }else if let source{
            image=try Self.imageIO(source,index:page,width:width)
        }else{
            let name=names[page],ext=(name as NSString).pathExtension.lowercased()
            if let engine=Self.engine(forImageExtension:ext){
                let file:URL
                var temp:TemporaryDirectory?
                if url.hasDirectoryPath{file=url.appendingPathComponent(name)}
                else{
                    let value=try archive!.data(name)
                    let directory=try TemporaryDirectory();temp=directory
                    file=directory.url.appendingPathComponent(URL(fileURLWithPath:name).lastPathComponent)
                    try value.write(to:file)
                }
                _=temp
                image=try NativeFile(file,engine:engine).image(0,width:width)
            }else{
                let data=try archive.map{try $0.data(name)} ?? Data(contentsOf:url.appendingPathComponent(name))
                guard let source=CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary) else{throw ReadError("ImageIO cannot read \(name)")}
                image=try Self.imageIO(source,index:0,width:width)
            }
        }
        cache.append((key,image))
        while cache.count>3 || (cache.count>1 && cache.reduce(0,{$0+$1.1.bytesPerRow*$1.1.height})>64*1024*1024){cache.removeFirst()}
        return image
    }

    private static func isComicImage(_ name:String)->Bool{
        Format.detect(name) == .image || nativeImageExtensions.contains((name as NSString).pathExtension.lowercased())
    }
    private static func engine(forImageExtension ext:String)->NativeEngine?{
        ext=="jxl" ? .jpegXL:(["jxr","hdp","wdp","svg"].contains(ext) ? .mupdf:nil)
    }
    private static func imageIO(_ source:CGImageSource,index:Int,width:Int)throws->CGImage{
        let options:[CFString:Any]=[
            kCGImageSourceCreateThumbnailFromImageAlways:true,
            kCGImageSourceCreateThumbnailWithTransform:true,
            kCGImageSourceThumbnailMaxPixelSize:width,
            kCGImageSourceShouldCacheImmediately:true
        ]
        guard let image=CGImageSourceCreateThumbnailAtIndex(source,index,options as CFDictionary) else{throw ReadError("ImageIO cannot decode this image")}
        return image
    }
    var hasText:Bool{native?.hasText == true}
    func relayout(fontSize:Double,lineHeight:Double,margin:Double,font:String,theme:String)->Int?{guard !Task.isCancelled else{return nil};guard let n=native?.relayout(fontSize:fontSize,lineHeight:lineHeight,margin:margin,font:font,theme:theme) else{return nil};count=n;cache.removeAll();return n}
    func frameDelay(_ p:Int)->Double?{guard url.pathExtension.lowercased()=="gif",count>1,let source,let props=CGImageSourceCopyPropertiesAtIndex(source,p,nil) as? [CFString:Any],let gif=props[kCGImagePropertyGIFDictionary] as? [CFString:Any]else{return nil};return max(0.02,gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? gif[kCGImagePropertyGIFDelayTime] as? Double ?? 0.1)}
    func find(_ q:String,after p:Int)->Int?{guard let native,native.hasText,!q.isEmpty,count>0 else{return nil};for o in 1...count{if Task.isCancelled{return nil};let i=(p+o)%count;if native.text(i)?.localizedCaseInsensitiveContains(q)==true{return i}};return nil}
}

@MainActor struct RasterReader:View{
    @ObservedObject var state:ReaderState
    let pages:Pages
    @State private var images:[CGImage]=[]
    @State private var animated=false
    @State private var playing=false
    @State private var pinchStart:Double?
    @State private var scale:CGFloat=2
    @State private var searchTask:Task<Void,Never>?
    @State private var styleTask:Task<Void,Never>?

    var body:some View{
        GeometryReader{g in
            let columns=state.spread ? 2:1
            let logicalWidth=max(128,g.size.width*CGFloat(state.fit=="custom" ? state.zoom:1)/CGFloat(columns))
            let target=max(128,min(16384,Int(logicalWidth*scale)))
            ZStack{
                background
                if state.flow=="continuous"{continuous(target:target)}
                else{paged(size:g.size,target:target,scale:scale,columns:columns)}
            }
            .focusable()
            .onMoveCommand{d in
                if d == .left{state.turn(state.rtl ? 1:-1)}
                if d == .right{state.turn(state.rtl ? -1:1)}
            }
            .gesture(MagnificationGesture().onChanged{v in
                if pinchStart==nil{pinchStart=state.zoom}
                state.setZoom((pinchStart ?? state.zoom)*Double(v))
            }.onEnded{_ in pinchStart=nil})
            .simultaneousGesture(DragGesture(minimumDistance:40).onEnded{v in
                guard state.flow != "continuous",abs(v.translation.width)>abs(v.translation.height),abs(v.translation.width)>80 else{return}
                state.turn(v.translation.width<0 ? (state.rtl ? -1:1):(state.rtl ? 1:-1))
            })
        }
        .background(WindowScale(scale:$scale).frame(width:0,height:0))
        .overlay(alignment:.topTrailing){if animated{Button(playing ? "Pause":"Play"){playing.toggle()}.padding(8)}}
        .task{animated=await pages.frameDelay(0) != nil;playing=animated}
        .task(id:playing){while playing,!Task.isCancelled,let delay=await pages.frameDelay(state.page){do{try await Task.sleep(nanoseconds:UInt64(delay*1_000_000_000))}catch{return};guard !Task.isCancelled else{return};state.page=(state.page+1)%max(1,state.count)}}
        .onChange(of:state.command.revision){_ in handleCommand()}
        .onDisappear{searchTask?.cancel();styleTask?.cancel()}
    }

    @ViewBuilder func continuous(target:Int)->some View{
        ScrollViewReader{proxy in
            ScrollView(.vertical){
                LazyVStack(spacing:4){
                    if state.spread{
                        ForEach(Array(stride(from:0,to:state.count,by:2)),id:\.self){i in
                            HStack(alignment:.top,spacing:4){
                                let pair=state.rtl ? [i+1,i]:[i,i+1]
                                ForEach(pair.filter{$0<state.count},id:\.self){j in LazyPage(state:state,pages:pages,index:j,width:target,scale:scale)}
                            }.id(i)
                        }
                    }else{
                        ForEach(0..<state.count,id:\.self){i in LazyPage(state:state,pages:pages,index:i,width:target,scale:scale).id(i)}
                    }
                }
                .onPreferenceChange(PageOffsetKey.self){v in
                    if let i=v.min(by:{abs($0.value)<abs($1.value)})?.key,state.page != i{state.page=i;state.persist()}
                }
            }
            .coordinateSpace(name:"pages")
            .onAppear{proxy.scrollTo(state.spread ? state.page-(state.page%2):state.page,anchor:.top)}
            .onChange(of:state.command.revision){_ in
                if case .page(let page)=state.command.action{withAnimation{proxy.scrollTo(state.spread ? page-(page%2):page,anchor:.top)}}
            }
        }
    }

    func paged(size:CGSize,target:Int,scale:CGFloat,columns:Int)->some View{
        ScrollView([.horizontal,.vertical]){
            HStack(spacing:state.spread ? 4:0){
                ForEach(Array((state.rtl ? Array(images.reversed()):images).enumerated()),id:\.offset){_,image in page(image,size,scale,columns)}
            }.frame(minWidth:size.width,minHeight:size.height)
        }
        .task(id:"\(state.page):\(target):\(state.spread):\(state.renderRevision)"){
            let page=state.page,generation=state.generation,revision=state.renderRevision,spread=state.spread,count=state.count
            do{
                var r=[try await pages.image(page,width:target)]
                if spread,page+1<count{r.append(try await pages.image(page+1,width:target))}
                guard !Task.isCancelled,generation==state.generation,revision==state.renderRevision else{return};images=r
                if page+r.count<count{_=try? await pages.image(page+r.count,width:target)}
            }catch{if !Task.isCancelled{state.error=error.localizedDescription}}
        }
    }

    func handleCommand(){
        let command=state.command,generation=state.generation,page=state.page
        switch command.action{
        case .print:
            Task{do{
                let image=try await pages.image(page,width:2400)
                guard !Task.isCancelled,generation==state.generation else{return}
                let view=NSImageView();view.image=NSImage(cgImage:image,size:.zero);view.imageScaling = .scaleProportionallyUpOrDown
                view.frame=NSRect(x:0,y:0,width:612,height:792);NSPrintOperation(view:view).run()
            }catch{if generation==state.generation{state.error=error.localizedDescription}}}
        case .style:
            searchTask?.cancel();styleTask?.cancel()
            let font=state.font,size=state.fontSize,line=state.lineHeight,margin=state.margin,theme=state.resolvedTheme
            styleTask=Task{
                guard let count=await pages.relayout(fontSize:size,lineHeight:line,margin:margin,font:font,theme:theme),!Task.isCancelled,generation==state.generation else{return}
                state.count=count;state.page=min(state.page,max(0,count-1));state.renderRevision += 1
                state.send(.page(state.page))
            }
        case .find(let query):
            searchTask?.cancel();guard !query.isEmpty else{return};state.status="Searching…"
            searchTask=Task{
                let match=await pages.find(query,after:page)
                guard !Task.isCancelled,generation==state.generation,state.command.revision==command.revision else{return}
                if let match{state.page=match;state.status="";state.send(.page(match));state.persist()}
                else{state.status="No matching text (image-only pages have no searchable text)"}
            }
        case .toc,.page(_):
            searchTask?.cancel()
        default:break
        }
    }

    var background:Color{state.theme=="dark" ? Color(nsColor:NSColor(white:0.06,alpha:1)):state.theme=="light" ? .white:Color(nsColor:.windowBackgroundColor)}
    func page(_ image:CGImage,_ size:CGSize,_ scale:CGFloat,_ columns:Int)->some View{
        let rotated=state.rotation%180 != 0,iw=CGFloat(rotated ? image.height:image.width)/scale,ih=CGFloat(rotated ? image.width:image.height)/scale,slot=size.width/CGFloat(columns)
        return Image(decorative:image,scale:scale).resizable().aspectRatio(contentMode:.fit).rotationEffect(.degrees(Double(state.rotation)))
            .frame(width:state.fit=="actual" ? iw*CGFloat(state.zoom):state.fit=="width" ? slot*CGFloat(state.zoom):nil,
                   height:state.fit=="page" ? size.height*CGFloat(state.zoom):state.fit=="actual" ? ih*CGFloat(state.zoom):nil)
            .frame(maxWidth:state.fit=="page" ? slot*CGFloat(state.zoom):nil)
    }
}
private struct WindowScale:NSViewRepresentable{ @Binding var scale:CGFloat;func makeNSView(context:Context)->NSView{let v=NSView();DispatchQueue.main.async{scale=v.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2};return v};func updateNSView(_ v:NSView,context:Context){DispatchQueue.main.async{let x=v.window?.backingScaleFactor ?? 2;if scale != x{scale=x}}}}
private struct PageOffsetKey:PreferenceKey{static var defaultValue:[Int:CGFloat]=[:];static func reduce(value:inout[Int:CGFloat],nextValue:()->[Int:CGFloat]){value.merge(nextValue(),uniquingKeysWith:{_,b in b})}}
@MainActor private struct LazyPage:View{
    @ObservedObject var state:ReaderState;let pages:Pages,index:Int,width:Int,scale:CGFloat;@State private var image:CGImage?
    var body:some View{Group{if let image{Image(decorative:image,scale:scale).resizable().scaledToFit().rotationEffect(.degrees(Double(state.rotation))).scaleEffect(state.fit=="custom" ? state.zoom:1)}else{ProgressView().frame(height:180)}}.frame(maxWidth:.infinity).background(GeometryReader{g in Color.clear.preference(key:PageOffsetKey.self,value:[index:g.frame(in:.named("pages")).midY])}).task(id:"\(width):\(state.renderRevision)"){do{let loaded=try await pages.image(index,width:width);guard !Task.isCancelled else{return};image=loaded}catch{if !Task.isCancelled{state.error=error.localizedDescription}}}.onDisappear{image=nil}}
}
#endif
