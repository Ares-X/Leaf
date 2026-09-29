#if os(macOS)
import SwiftUI
import LeafCore
import UniformTypeIdentifiers

struct ReaderCommand: Equatable { let id=UUID(); var name="",text="";var number=0.0 }
struct ContentsItem:Identifiable,Codable{var id:String{target};let title:String,target:String;var depth=0}
struct ReadingPosition:Codable{var page=0;var cfi:String?;var fraction=0.0}

@MainActor final class ReaderState:ObservableObject{
    @Published var document:ReadingDocument?,busy=false,error:String?,status="",page=0,count=0,zoom=1.0,fraction=0.0,outline:[ContentsItem]=[],command=ReaderCommand(),showContents=false,showFind=false,spread=false,rtl=false
    @Published var fit="page",flow="paged",font="system",fontSize=17.0,lineHeight=1.6,margin=32.0,theme="system",rotation=0,recents:[URL]=[]
    var cfi:String?;private var loading:Task<Void,Never>?
    init(){
        recents=NSDocumentController.shared.recentDocumentURLs
        let d=UserDefaults.standard
        if let v=d.string(forKey:"fit"){fit=v};if let v=d.string(forKey:"flow"){flow=v};if let v=d.string(forKey:"font"){font=v};if let v=d.string(forKey:"theme"){theme=v}
        if d.object(forKey:"fontSize") != nil{fontSize=d.double(forKey:"fontSize")}
        if d.object(forKey:"lineHeight") != nil{lineHeight=d.double(forKey:"lineHeight")}
        if d.object(forKey:"margin") != nil{margin=d.double(forKey:"margin")}
        spread=d.bool(forKey:"spread");rtl=d.bool(forKey:"rtl")
    }
    var isBook:Bool{if case .book= document?.content{return true};return false}
    var isText:Bool{if case .text= document?.content{return true};return false}
    var isPages:Bool{if case .pages= document?.content{return true};return false}
    var positionLabel:String{isBook ? "\(Int(fraction*100))%" : "\(min(page+1,count)) / \(count)"}
    func send(_ name:String,text:String="",number:Double=0){command=.init(name:name,text:text,number:number)}
    func close(){persist();loading?.cancel();document=nil;busy=false;outline=[];count=0;status=""}
    func chooseFile(){let p=NSOpenPanel();p.canChooseDirectories=true;p.begin{[weak self] r in if r == .OK,let u=p.url{self?.open(u)}}}
    func open(_ url:URL){
        persist();loading?.cancel();document=nil;busy=true;error=nil;status="";outline=[];page=0;count=0;zoom=1;fraction=0;cfi=nil
        loading=Task{let worker=Task.detached(priority:.userInitiated){try ReadingDocument.open(url)}
            do{let opened=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()});guard !Task.isCancelled else{return}
                if let d=UserDefaults.standard.data(forKey:"position:"+url.standardizedFileURL.path),let s=try? JSONDecoder().decode(ReadingPosition.self,from:d){page=max(0,s.page);cfi=s.cfi;fraction=s.fraction}
                document=opened;busy=false;NSDocumentController.shared.noteNewRecentDocumentURL(url);recents=NSDocumentController.shared.recentDocumentURLs
            }catch{if !Task.isCancelled{self.error=error.localizedDescription;busy=false}}}
    }
    func persist(){guard let u=document?.url,let d=try? JSONEncoder().encode(ReadingPosition(page:page,cfi:cfi,fraction:fraction))else{return};UserDefaults.standard.set(d,forKey:"position:"+u.standardizedFileURL.path)}
    func turn(_ d:Int){if isBook{send(d>0 ? "next":"prev")}else{page=max(0,min(max(0,count-1),page+d*(spread ? 2:1)));send("page",number:Double(page));persist()}}
    func go(_ s:String){guard let n=Double(s),n.isFinite else{return};if isBook{send("fraction",number:max(0,min(1,n/100)))}else{page=Int(max(0,min(Double(max(0,count-1)),n-1)));send("page",number:Double(page));persist()}}
    func setZoom(_ v:Double){zoom=max(0.25,min(6,v));fit="custom";send("zoom",number:zoom)}
    func setFit(_ v:String){fit=v;zoom=1;UserDefaults.standard.set(v,forKey:"fit");send("fit",text:v)}
    func setFlow(_ v:String){flow=v;UserDefaults.standard.set(v,forKey:"flow");send("flow",text:v)}
    func applyTypography(){let d=UserDefaults.standard;d.set(font,forKey:"font");d.set(fontSize,forKey:"fontSize");d.set(lineHeight,forKey:"lineHeight");d.set(margin,forKey:"margin");send("style",text:"\(font)|\(fontSize)|\(lineHeight)|\(margin)|\(theme)")}
    func setTheme(_ v:String){theme=v;UserDefaults.standard.set(v,forKey:"theme");applyTypography()}
    func rotate(_ d:Int){rotation=(rotation+d+360)%360;send("rotate",number:Double(d))}
    func bookmark(){guard let u=document?.url else{return};persist();UserDefaults.standard.set(UserDefaults.standard.data(forKey:"position:"+u.standardizedFileURL.path),forKey:"bookmark:"+u.standardizedFileURL.path);status="Bookmark saved"}
    func restoreBookmark(){guard let u=document?.url,let d=UserDefaults.standard.data(forKey:"bookmark:"+u.standardizedFileURL.path),let s=try? JSONDecoder().decode(ReadingPosition.self,from:d)else{return};if isBook,let c=s.cfi{send("href",text:c)}else{go(String(s.page+1))}}
}

@main @MainActor struct LeafApp:App{
    @StateObject private var state=ReaderState()
    var body:some Scene{Window("Leaf",id:"reader"){ReaderView(state:state).frame(minWidth:560,minHeight:400).onOpenURL{state.open($0)}.onReceive(NotificationCenter.default.publisher(for:NSApplication.willTerminateNotification)){_ in state.persist()}}.defaultSize(width:900,height:740).commands{
        CommandGroup(replacing:.newItem){Button("Open…",action:state.chooseFile).keyboardShortcut("o");Menu("Open Recent"){ForEach(state.recents,id:\.self){u in Button(u.lastPathComponent){state.open(u)}}}}
        CommandMenu("Reading"){Button("Find…"){state.showFind.toggle()}.keyboardShortcut("f");Button("Previous"){state.turn(-1)}.keyboardShortcut("[");Button("Next"){state.turn(1)}.keyboardShortcut("]");Divider();Button("Zoom In"){state.setZoom(state.zoom*1.2)}.keyboardShortcut("+");Button("Zoom Out"){state.setZoom(state.zoom/1.2)}.keyboardShortcut("-");Button("Actual Size"){state.setFit("actual")}.keyboardShortcut("1");Button("Fit Page"){state.setFit("page")}.keyboardShortcut("0");Button("Fit Width"){state.setFit("width")}.keyboardShortcut("2");Divider();Button("Paged"){state.setFlow("paged")};Button("Continuous"){state.setFlow("continuous")};Toggle("Two Pages",isOn:$state.spread);Toggle("Right to Left",isOn:$state.rtl);Divider();Button("Bookmark This Position",action:state.bookmark).keyboardShortcut("d");Button("Go to Bookmark",action:state.restoreBookmark);Button("Contents"){state.showContents.toggle()}.keyboardShortcut("t",modifiers:[.command,.shift]);Button("Rotate Left"){state.rotate(-90)};Button("Rotate Right"){state.rotate(90)};Divider();Button("Light"){state.setTheme("light")};Button("Dark"){state.setTheme("dark")};Button("System Theme"){state.setTheme("system")};Divider();Button("Full Screen"){NSApp.keyWindow?.toggleFullScreen(nil)}.keyboardShortcut("f",modifiers:[.command,.control])}
    }}
}

@MainActor struct ReaderView:View{
    @ObservedObject var state:ReaderState;@State private var query="",destination="";@FocusState private var finding:Bool
    var body:some View{VStack(spacing:0){
        if state.showFind{HStack{TextField("Find in document",text:$query).focused($finding).onSubmit{state.send("find",text:query)};Button("Find Next"){state.send("find",text:query)};Button{state.showFind=false}label:{Image(systemName:"xmark")}}.padding(8).onAppear{finding=true};Divider()}
        HStack(spacing:0){if state.showContents{List(Array(state.outline.enumerated()),id:\.offset){_,i in Button{state.send("href",text:i.target)}label:{Text(i.title).lineLimit(2).padding(.leading,CGFloat(i.depth*10))}.buttonStyle(.plain)}.frame(width:210);Divider()}
            Group{if let d=state.document{content(d).id(d.url)}else if state.busy{ProgressView("Opening…")}else{Button("Open a document…",action:state.chooseFile)}}.frame(maxWidth:.infinity,maxHeight:.infinity)}
        if !state.status.isEmpty{Divider();Text(state.status).font(.caption).foregroundStyle(.secondary).padding(5)}
    }.navigationTitle(state.document?.url.lastPathComponent ?? "Leaf").onDisappear{state.close()}
    .onChange(of:state.spread){UserDefaults.standard.set($0,forKey:"spread");state.send("spread",number:$0 ? 2:1)}.onChange(of:state.rtl){UserDefaults.standard.set($0,forKey:"rtl");state.send("rtl",number:$0 ? 1:0)}
    .toolbar{Button(action:state.chooseFile){Image(systemName:"folder")};Button{state.showContents.toggle()}label:{Image(systemName:"sidebar.left")};Button{state.turn(-1)}label:{Image(systemName:"chevron.left")};Text(state.positionLabel).monospacedDigit();Button{state.turn(1)}label:{Image(systemName:"chevron.right")};TextField(state.isBook ? "Go to %":state.isText ? "Line":"Page",text:$destination).frame(width:55).onSubmit{state.go(destination);destination=""};Menu{Button("Fit Page"){state.setFit("page")};Button("Fit Width"){state.setFit("width")};Button("Actual Size"){state.setFit("actual")};Divider();Button("Paged"){state.setFlow("paged")};Button("Continuous"){state.setFlow("continuous")};Toggle("Two Pages",isOn:$state.spread);Toggle("Right to Left",isOn:$state.rtl);if state.isBook||state.isText{Divider();TypographyMenu(state:state)};Divider();Button("Rotate Left"){state.rotate(-90)};Button("Rotate Right"){state.rotate(90)};Divider();Button("Light"){state.setTheme("light")};Button("Dark"){state.setTheme("dark")};Button("System Theme"){state.setTheme("system")}}label:{Image(systemName:"textformat.size")};Button{state.setZoom(state.zoom/1.2)}label:{Image(systemName:"minus.magnifyingglass")};Button{state.setZoom(state.zoom*1.2)}label:{Image(systemName:"plus.magnifyingglass")};Button{state.showFind.toggle()}label:{Image(systemName:"magnifyingglass")}}
    .alert("Unable to read document",isPresented:Binding(get:{state.error != nil},set:{if !$0{state.error=nil}})){Button("OK"){state.error=nil}}message:{Text(state.error ?? "")}
    .onDrop(of:[.fileURL],isTargeted:nil){p in guard let f=p.first else{return false};_=f.loadObject(ofClass:URL.self){u,_ in if let u{Task{@MainActor in state.open(u)}}};return true}}
    @ViewBuilder func content(_ d:ReadingDocument)->some View{switch d.content{case .pdf(let u,let x):PDFReader(state:state,url:u,data:x);case .text(let t):TextReader(state:state,text:t);case .book(let s):BookReader(state:state,source:s);case .pages(let p):RasterReader(state:state,pages:p).task{let n=await p.count;guard !Task.isCancelled else{return};state.count=n;state.page=max(0,min(state.page,n-1))}}}
}
struct TypographyMenu:View{ @ObservedObject var state:ReaderState;var body:some View{Group{Picker("Font",selection:$state.font){Text("System").tag("system");Text("Serif").tag("serif");Text("Sans Serif").tag("sans-serif");Text("Monospace").tag("monospace")}.onChange(of:state.font){_ in state.applyTypography()};Stepper("Font \(Int(state.fontSize)) pt",value:$state.fontSize,in:10...36,step:1).onChange(of:state.fontSize){_ in state.applyTypography()};Stepper("Line \(state.lineHeight,specifier:"%.1f")",value:$state.lineHeight,in:1.0...2.4,step:0.1).onChange(of:state.lineHeight){_ in state.applyTypography()};Stepper("Margin \(Int(state.margin))",value:$state.margin,in:0...96,step:8).onChange(of:state.margin){_ in state.applyTypography()}}}}
#else
@main enum LeafCLI{static func main(){print("Leaf's UI requires macOS. Run swift test for portable core checks.")}}
#endif
