#if os(macOS)
import SwiftUI
import LeafCore
import UniformTypeIdentifiers
import Darwin

struct ReaderCommand:Equatable{let id=UUID();var name="",text="";var number=0.0}
struct ContentsItem:Identifiable,Codable{var id:String{target};let title:String,target:String;var depth=0}
struct ReadingPosition:Codable{var page=0}

@MainActor final class ReaderState:ObservableObject{
    @Published var document: ReadingDocument?
    @Published var busy = false
    @Published var error: String?
    @Published var status = ""
    @Published var page = 0
    @Published var count = 0
    @Published var zoom = 1.0
    @Published var outline: [ContentsItem] = []
    @Published var outlineBusy = false
    @Published var command = ReaderCommand()
    @Published var showContents = false
    @Published var showFind = false
    @Published var spread = false
    @Published var rtl = false
    @Published var fit = "page"
    @Published var flow = "paged"
    @Published var font = "system"
    @Published var fontSize = 17.0
    @Published var lineHeight = 1.6
    @Published var margin = 32.0
    @Published var theme = "system"
    @Published var rotation = 0
    @Published var reflowable = false
    @Published var searchable = false
    @Published var renderRevision = 0
    private var loading:Task<Void,Never>?,reloadTask:Task<Void,Never>?,watch:DispatchSourceFileSystemObject?,requestGeneration=0
    private(set) var generation=0

    init(){readPreferences(layout:true)}
    private func readPreferences(layout:Bool){
        let d=UserDefaults.standard
        if layout{fit=d.string(forKey:"fit") ?? "page";flow=d.string(forKey:"flow") ?? "paged";spread=d.bool(forKey:"spread");rtl=d.bool(forKey:"rtl")}
        font=d.string(forKey:"font") ?? "system";theme=d.string(forKey:"theme") ?? "system"
        fontSize=d.object(forKey:"fontSize") == nil ? 17:d.double(forKey:"fontSize")
        lineHeight=d.object(forKey:"lineHeight") == nil ? 1.6:d.double(forKey:"lineHeight")
        margin=d.object(forKey:"margin") == nil ? 32:d.double(forKey:"margin")
    }
    func syncAppearancePreferences(){
        let oldTypography="\(font)|\(fontSize)|\(lineHeight)|\(margin)",oldTheme=theme
        readPreferences(layout:false)
        let newTypography="\(font)|\(fontSize)|\(lineHeight)|\(margin)"
        if oldTypography != newTypography || (oldTheme != theme && (isText || isCHM)){send("style",text:"\(font)|\(fontSize)|\(lineHeight)|\(margin)|\(theme)")}
    }
    var isText:Bool{if case .text=document?.content{return true};return false}
    var isFixed:Bool{guard let d=document else{return false};switch d.content{case .pdf,.pages:return true;default:return false}}
    var isCHM:Bool{if case .chm=document?.content{return true};return false}
    var supportsFlow:Bool{isFixed}
    var supportsSpread:Bool{isFixed}
    var supportsRTL:Bool{isFixed}
    var supportsFit:Bool{isFixed}
    var supportsRotation:Bool{isFixed}
    var supportsSearch:Bool{isText || isCHM || searchable}
    var hasDocument:Bool{document != nil}
    var canTurn:Bool{isCHM ? hasDocument:count>1}
    var canSaveCopy:Bool{document?.url.hasDirectoryPath == false}
    var hasBookmark:Bool{guard let u=document?.url else{return false};return UserDefaults.standard.data(forKey:"bookmark:"+u.standardizedFileURL.path) != nil}
    var positionLabel:String{count>0 ? "\(min(page+1,count)) / \(count)":"— / —"}
    var zoomLabel:String{
        if isText || isCHM || fit=="custom"{return "\(Int(zoom*100))%"}
        if fit=="width"{return "Fit Width"}
        if fit=="actual"{return "100%"}
        return "Fit Page"
    }
    func send(_ name:String,text:String="",number:Double=0){command = .init(name:name,text:text,number:number)}
    func toggleFind(){showFind.toggle();if !showFind{send("toc")}}
    func chooseFile(){let p=NSOpenPanel();p.canChooseDirectories=true;p.begin{[weak self] r in if r == .OK,let u=p.url{self?.open(u)}}}
    func open(_ url:URL){
        persist();requestGeneration+=1;let g=requestGeneration;loading?.cancel();busy=true;error=nil;status="Opening \(url.lastPathComponent)…"
        loading=Task{let worker=Task.detached(priority:.userInitiated){try ReadingDocument.open(url)}
            do{let opened=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()});guard !Task.isCancelled,g==requestGeneration else{return}
                readPreferences(layout:true);outline=[];outlineBusy=false;page=0;count=0;zoom=1;rotation=0;reflowable=false;searchable=false;renderRevision=0
                if let d=UserDefaults.standard.data(forKey:"position:"+url.standardizedFileURL.path),let p=try? JSONDecoder().decode(ReadingPosition.self,from:d){page=max(0,p.page)}
                generation+=1;document=opened;busy=false;status="";watchFile(url);NSDocumentController.shared.noteNewRecentDocumentURL(url)
            }catch{if !Task.isCancelled,g==requestGeneration{self.error=error.localizedDescription;busy=false;status=""}}}
    }
    func close(){requestGeneration+=1;generation+=1;persist();loading?.cancel();stopWatch();document=nil;busy=false;outline=[];outlineBusy=false;count=0;status="";reflowable=false;searchable=false;renderRevision=0}
    func reload(){guard let u=document?.url else{return};persist();requestGeneration+=1;let g=requestGeneration;loading?.cancel();status="Reloading…";loading=Task{let worker=Task.detached(priority:.userInitiated){try ReadingDocument.open(u)};do{let opened=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()});guard !Task.isCancelled,g==requestGeneration else{return};generation+=1;document=opened;watchFile(u);status=""}catch{if !Task.isCancelled,g==requestGeneration{status="";error=error.localizedDescription}}}}
    func persist(){guard let u=document?.url,let d=try? JSONEncoder().encode(ReadingPosition(page:page))else{return};UserDefaults.standard.set(d,forKey:"position:"+u.standardizedFileURL.path)}
    func turn(_ d:Int){if isCHM{send(d>0 ? "next":"prev");return};page=max(0,min(max(0,count-1),page+d*((spread && isFixed) ? 2:1)));send("page",number:Double(page));persist()}
    func go(_ s:String){guard let n=Double(s),n.isFinite else{return};page=Int(max(0,min(Double(max(0,count-1)),n-1)));send("page",number:Double(page));persist()}
    func sibling(_ delta:Int){guard let u=document?.url,let files=try? FileManager.default.contentsOfDirectory(at:u.deletingLastPathComponent(),includingPropertiesForKeys:nil,options:[.skipsHiddenFiles])else{return};let list=files.filter{Format.detect($0.lastPathComponent) != .unknown}.sorted{$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)== .orderedAscending};guard let i=list.firstIndex(of:u),list.indices.contains(i+delta)else{return};open(list[i+delta])}
    func saveCopy(){
        guard let u=document?.url,!u.hasDirectoryPath else{error="Save a Copy is only available for files.";return}
        let p=NSSavePanel();p.nameFieldStringValue=u.lastPathComponent
        p.begin{r in guard r == .OK,let d=p.url else{return};do{
            let fm=FileManager.default,source=u.standardizedFileURL.resolvingSymlinksInPath(),destination=d.standardizedFileURL.resolvingSymlinksInPath()
            guard source != destination else{throw ReadError("Choose a different location for Save a Copy.")}
            let temp=d.deletingLastPathComponent().appendingPathComponent(".Leaf-copy-"+UUID().uuidString);defer{try? fm.removeItem(at:temp)}
            try fm.copyItem(at:u,to:temp)
            if fm.fileExists(atPath:d.path){_ = try fm.replaceItemAt(d,withItemAt:temp)}else{try fm.moveItem(at:temp,to:d)}
        }catch{self.error=error.localizedDescription}}}
    }
    func watchFile(_ u:URL){
        stopWatch();guard !u.hasDirectoryPath else{return};let fd=Darwin.open(u.path,O_EVTONLY);guard fd>=0 else{return}
        let source=DispatchSource.makeFileSystemObjectSource(fileDescriptor:fd,eventMask:[.write,.delete,.rename],queue:.main);watch=source
        source.setEventHandler{[weak self,weak source] in guard let self,let source else{return};let e=source.data;self.status="File changed on disk";self.reloadTask?.cancel();self.reloadTask=Task{try? await Task.sleep(nanoseconds:250_000_000);guard !Task.isCancelled else{return};if e.contains(.delete)||e.contains(.rename){guard FileManager.default.fileExists(atPath:u.path) else{self.status="File moved or deleted";self.stopWatch();return}};self.reload()}}
        source.setCancelHandler{Darwin.close(fd)};source.resume()
    }
    func stopWatch(){reloadTask?.cancel();reloadTask=nil;watch?.cancel();watch=nil}
    func copyPath(){guard let p=document?.url.path else{return};NSPasteboard.general.clearContents();NSPasteboard.general.setString(p,forType:.string)}
    func printDocument(){send("print")}
    func setZoom(_ v:Double){zoom=max(0.25,min(6,v));fit="custom";send("zoom",number:zoom)}
    func setFit(_ v:String){guard supportsFit,["page","width","actual"].contains(v) else{return};fit=v;zoom=1;UserDefaults.standard.set(v,forKey:"fit");send("fit",text:v)}
    func setFlow(_ v:String){guard ["paged","continuous"].contains(v) else{return};flow=v;UserDefaults.standard.set(v,forKey:"flow");if supportsFlow{send("flow",text:v)}}
    func applyTypography(){let d=UserDefaults.standard;d.set(font,forKey:"font");d.set(fontSize,forKey:"fontSize");d.set(lineHeight,forKey:"lineHeight");d.set(margin,forKey:"margin");send("style",text:"\(font)|\(fontSize)|\(lineHeight)|\(margin)|\(theme)")}
    func setTheme(_ v:String){theme=v;UserDefaults.standard.set(v,forKey:"theme");if isText || isCHM{send("style",text:"\(font)|\(fontSize)|\(lineHeight)|\(margin)|\(theme)")}}
    func rotate(_ d:Int){guard supportsRotation else{return};rotation=(rotation+d+360)%360;send("rotate",number:Double(d))}
    func bookmark(){guard let u=document?.url else{return};persist();UserDefaults.standard.set(UserDefaults.standard.data(forKey:"position:"+u.standardizedFileURL.path),forKey:"bookmark:"+u.standardizedFileURL.path);status="Bookmark saved"}
    func restoreBookmark(){guard let u=document?.url,let d=UserDefaults.standard.data(forKey:"bookmark:"+u.standardizedFileURL.path),let p=try? JSONDecoder().decode(ReadingPosition.self,from:d)else{return};go(String(p.page+1))}
}

struct WindowPayload:Codable,Hashable{
    var id=UUID()
    var path:String?
    init(path:String?=nil){self.path=path}
}
private struct ReaderStateKey:FocusedValueKey{typealias Value=ReaderState}
private extension FocusedValues{
    var readerState:ReaderState?{get{self[ReaderStateKey.self]}set{self[ReaderStateKey.self]=newValue}}
}

@MainActor private struct ReaderWindow:View{
    @Binding var payload:WindowPayload
    @StateObject private var state=ReaderState()
    @Environment(\.openWindow) private var openWindow
    var body:some View{
        ReaderView(state:state).frame(minWidth:560,minHeight:400)
            .background(WindowTabs())
            .focusedSceneValue(\.readerState,state)
            .task(id:payload.path){if state.document==nil,let path=payload.path,FileManager.default.fileExists(atPath:path){state.open(URL(fileURLWithPath:path))}}
            .onChange(of:state.document?.url.path){payload.path=$0}
            .onOpenURL{url in if state.document == nil{state.open(url)}else{openWindow(id:"reader",value:WindowPayload(path:url.path))}}
            .onReceive(NotificationCenter.default.publisher(for:UserDefaults.didChangeNotification)){_ in state.syncAppearancePreferences()}
            .onReceive(NotificationCenter.default.publisher(for:NSApplication.willTerminateNotification)){_ in state.persist()}
    }
}
private struct WindowTabs:NSViewRepresentable{
    func makeNSView(context:Context)->NSView{let v=NSView();DispatchQueue.main.async{if let w=v.window{NSWindow.allowsAutomaticWindowTabbing=true;w.tabbingIdentifier="LeafReader";w.tabbingMode = .preferred}};return v}
    func updateNSView(_ v:NSView,context:Context){if let w=v.window{w.tabbingIdentifier="LeafReader";w.tabbingMode = .preferred}}
}

private struct LeafCommands:Commands{
    @FocusedValue(\.readerState) private var state
    @Environment(\.openWindow) private var openWindow
    var body:some Commands{
        CommandGroup(after:.newItem){
            Button("Open…",action:openFiles).keyboardShortcut("o")
            Menu("Open Recent"){ForEach(NSDocumentController.shared.recentDocumentURLs.filter{FileManager.default.fileExists(atPath:$0.path)},id:\.self){u in Button(u.lastPathComponent){if let state{state.open(u)}else{openWindow(id:"reader",value:WindowPayload(path:u.path))}}};Divider();Button("Clear Menu"){NSDocumentController.shared.clearRecentDocuments(nil)}}
        }
        CommandGroup(after:.saveItem){
            Button("Save a Copy…"){state?.saveCopy()}.keyboardShortcut("s",modifiers:[.command,.shift]).disabled(state?.canSaveCopy != true)
            Button("Reload"){state?.reload()}.keyboardShortcut("r").disabled(state?.document==nil)
            Button("Show in Finder"){if let u=state?.document?.url{NSWorkspace.shared.activateFileViewerSelecting([u])}}.disabled(state?.document==nil)
            Button("Copy File Path"){state?.copyPath()}.disabled(state?.document==nil)
            Button("Close Document"){state?.close()}.disabled(state?.document==nil)
        }
        CommandGroup(after:.printItem){Button("Print…"){state?.printDocument()}.keyboardShortcut("p").disabled(state?.document==nil)}
        CommandGroup(after:.toolbar){Button("Toggle Contents"){state?.showContents.toggle()}.keyboardShortcut("t",modifiers:[.command,.shift]).disabled(state?.hasDocument != true);Button("Enter Full Screen"){NSApp.keyWindow?.toggleFullScreen(nil)}.keyboardShortcut("f",modifiers:[.command,.control])}
        CommandMenu("Reading"){
            Button("Find…"){state?.toggleFind()}.keyboardShortcut("f").disabled(state?.supportsSearch != true)
            Button("Previous Page"){state?.turn(-1)}.keyboardShortcut("[").disabled(state?.canTurn != true);Button("Next Page"){state?.turn(1)}.keyboardShortcut("]").disabled(state?.canTurn != true)
            Button("Previous File"){state?.sibling(-1)}.keyboardShortcut(.upArrow,modifiers:[.command,.option]);Button("Next File"){state?.sibling(1)}.keyboardShortcut(.downArrow,modifiers:[.command,.option])
            Divider();Button("Zoom In"){if let state{state.setZoom(state.zoom*1.2)}}.keyboardShortcut("+").disabled(state?.hasDocument != true);Button("Zoom Out"){if let state{state.setZoom(state.zoom/1.2)}}.keyboardShortcut("-").disabled(state?.hasDocument != true);Button("Actual Size"){state?.setFit("actual")}.keyboardShortcut("1").disabled(state?.supportsFit != true);Button("Fit Page"){state?.setFit("page")}.keyboardShortcut("0").disabled(state?.supportsFit != true);Button("Fit Width"){state?.setFit("width")}.keyboardShortcut("2").disabled(state?.supportsFit != true)
            Divider();Button("Paged"){state?.setFlow("paged")}.disabled(state?.supportsFlow != true);Button("Continuous"){state?.setFlow("continuous")}.disabled(state?.supportsFlow != true);Toggle("Two Pages",isOn:Binding(get:{state?.spread ?? false},set:{state?.spread=$0})).disabled(state?.supportsSpread != true);Toggle("Right to Left",isOn:Binding(get:{state?.rtl ?? false},set:{state?.rtl=$0})).disabled(state?.supportsRTL != true)
            Divider();Button("Bookmark This Position"){state?.bookmark()}.keyboardShortcut("d").disabled(state?.hasDocument != true);Button("Go to Bookmark"){state?.restoreBookmark()}.disabled(state?.hasBookmark != true);Button("Contents"){state?.showContents.toggle()}.disabled(state?.hasDocument != true)
            Divider();Button("Rotate Left"){state?.rotate(-90)}.disabled(state?.supportsRotation != true);Button("Rotate Right"){state?.rotate(90)}.disabled(state?.supportsRotation != true)
            Divider();Button("Light"){state?.setTheme("light")};Button("Dark"){state?.setTheme("dark")};Button("System Theme"){state?.setTheme("system")}
        }
    }
    private func openFiles(){
        let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.allowsMultipleSelection=true
        panel.begin{result in guard result == .OK else{return};let urls=panel.urls;guard let first=urls.first else{return};if let state{state.open(first)}else{openWindow(id:"reader",value:WindowPayload(path:first.path))};for url in urls.dropFirst(){openWindow(id:"reader",value:WindowPayload(path:url.path))}}
    }
}

@main @MainActor struct LeafApp:App{
    init(){NSWindow.allowsAutomaticWindowTabbing=true}
    var body:some Scene{
        WindowGroup("Leaf",id:"reader",for:WindowPayload.self){$payload in ReaderWindow(payload:$payload)} defaultValue:{WindowPayload()}
            .defaultSize(width:900,height:740)
            .commands{LeafCommands()}
        Settings{SettingsView()}
    }
}

@MainActor struct ReaderView:View{
    @ObservedObject var state:ReaderState;@State private var query="";@State private var destination="";@FocusState private var finding:Bool;@Environment(\.openWindow) private var openWindow
    var body:some View{VStack(spacing:0){
        if state.showFind{HStack{TextField("Find in document",text:$query).focused($finding).onSubmit{state.send("find",text:query)};Button("Find Next"){state.send("find",text:query)};Button{state.showFind=false;state.send("toc")}label:{Image(systemName:"xmark")}}.padding(8).onAppear{finding=true};Divider()}
        mainArea
        if state.document != nil{Divider();HStack{Text(state.status.isEmpty ? (state.document?.url.lastPathComponent ?? ""):state.status).lineLimit(1);Spacer();if state.count>0{Text(state.positionLabel).monospacedDigit()};Text(state.zoomLabel).monospacedDigit()}.font(.caption).foregroundStyle(.secondary).padding(.horizontal,8).padding(.vertical,4)}
    }.navigationTitle(state.document?.url.lastPathComponent ?? "Leaf")
    .modifier(DocumentProxy(url:state.document?.url))
    .preferredColorScheme(state.theme=="dark" ? .dark:state.theme=="light" ? .light:nil)
    .onChange(of:state.spread){UserDefaults.standard.set($0,forKey:"spread");if state.supportsSpread{state.send("spread",number:$0 ? 2:1)}}
    .onChange(of:state.rtl){UserDefaults.standard.set($0,forKey:"rtl");if state.supportsRTL{state.send("rtl",number:$0 ? 1:0)}}
    .toolbar{Button(action:state.chooseFile){Image(systemName:"folder")}.help("Open Document");Button{state.showContents.toggle()}label:{Image(systemName:"sidebar.left")}.disabled(!state.hasDocument).help("Toggle Contents");Button{state.turn(-1)}label:{Image(systemName:"chevron.left")}.disabled(!state.canTurn).help("Previous Page");if state.hasDocument{Text(state.positionLabel).monospacedDigit()};Button{state.turn(1)}label:{Image(systemName:"chevron.right")}.disabled(!state.canTurn).help("Next Page");TextField(state.isText ? "Line":"Page",text:$destination).frame(width:55).disabled(!state.hasDocument || state.isCHM).onSubmit{state.go(destination);destination=""};Menu{if state.supportsFit{Button("Fit Page"){state.setFit("page")};Button("Fit Width"){state.setFit("width")};Button("Actual Size"){state.setFit("actual")};Divider()};if state.supportsFlow{Button("Paged"){state.setFlow("paged")};Button("Continuous"){state.setFlow("continuous")};Toggle("Two Pages",isOn:$state.spread);if state.supportsRTL{Toggle("Right to Left",isOn:$state.rtl)};Divider()};if state.isText || state.isCHM || state.reflowable{TypographyMenu(state:state);Divider()};if state.supportsRotation{Button("Rotate Left"){state.rotate(-90)};Button("Rotate Right"){state.rotate(90)};Divider()};Button("Light"){state.setTheme("light")};Button("Dark"){state.setTheme("dark")};Button("System Theme"){state.setTheme("system")}}label:{Image(systemName:"slider.horizontal.3")}.help("Reading Options");Button{state.setZoom(state.zoom/1.2)}label:{Image(systemName:"minus.magnifyingglass")}.disabled(!state.hasDocument).help("Zoom Out");Button{state.setZoom(state.zoom*1.2)}label:{Image(systemName:"plus.magnifyingglass")}.disabled(!state.hasDocument).help("Zoom In");Button{state.toggleFind()}label:{Image(systemName:"magnifyingglass")}.disabled(!state.supportsSearch).help("Find")}
    .contextMenu{Button("Open…",action:state.chooseFile);if state.document != nil{Button("Show in Finder"){if let u=state.document?.url{NSWorkspace.shared.activateFileViewerSelecting([u])}};Button("Copy File Path",action:state.copyPath);Divider();Button("Previous"){state.turn(-1)};Button("Next"){state.turn(1)};if state.supportsFit{Button("Fit Page"){state.setFit("page")};Button("Fit Width"){state.setFit("width")}}}}
    .dropDestination(for:URL.self){urls,_ in guard let first=urls.first else{return false};state.open(first);for u in urls.dropFirst(){openWindow(id:"reader",value:WindowPayload(path:u.path))};return true}
    .alert("Unable to read document",isPresented:Binding(get:{state.error != nil},set:{if !$0{state.error=nil}})){Button("OK"){state.error=nil}}message:{Text(state.error ?? "")}}
    @ViewBuilder var mainArea:some View{
        if state.showContents{HSplitView{contentsSidebar.frame(minWidth:180,idealWidth:220,maxWidth:360);documentArea}}
        else{documentArea}
    }
    @ViewBuilder var contentsSidebar:some View{
        if state.outlineBusy{VStack{Spacer();ProgressView();Text("Detecting chapters…").font(.caption).foregroundStyle(.secondary);Spacer()}}
        else if state.outline.isEmpty{VStack{Spacer();Text("No contents").font(.caption).foregroundStyle(.secondary);Spacer()}}
        else{List(Array(state.outline.enumerated()),id:\.offset){_,i in Button{state.send("href",text:i.target)}label:{Text(i.title).lineLimit(2).padding(.leading,CGFloat(i.depth*10))}.buttonStyle(.plain)}.listStyle(.sidebar)}
    }
    @ViewBuilder var documentArea:some View{
        Group{if let d=state.document{content(d).id(state.generation)}else if state.busy{ProgressView("Opening…")}else{WelcomeView(open:state.chooseFile)}}.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    @ViewBuilder func content(_ d:ReadingDocument)->some View{switch d.content{case .pdf(let u,let x):PDFReader(state:state,url:u,data:x);case .text(let t):TextReader(state:state,text:t);case .chm(let s):CHMReader(state:state,source:s);case .pages(let p):RasterReader(state:state,pages:p).task{state.searchable=await p.hasText;if let n=await p.relayout(fontSize:state.fontSize,lineHeight:state.lineHeight,margin:state.margin,font:state.font){state.reflowable=true;state.count=n}else{state.reflowable=false;state.count=await p.count};guard !Task.isCancelled else{return};state.page=max(0,min(state.page,state.count-1))}}}
}
private struct DocumentProxy:ViewModifier{
    let url:URL?
    @ViewBuilder func body(content:Content)->some View{if let url{content.navigationDocument(url)}else{content}}
}
private struct WelcomeView:View{
    let open:()->Void
    var body:some View{VStack(spacing:14){
        Image(nsImage:NSApp.applicationIconImage).resizable().scaledToFit().frame(width:72,height:72)
        Text("Leaf").font(.largeTitle.weight(.semibold))
        Text("A fast, focused document reader for macOS").foregroundStyle(.secondary)
        Button("Open Document…",action:open).keyboardShortcut("o")
        Text("Drop a document here, or use File → Open").font(.caption).foregroundStyle(.tertiary)
    }.padding(40)}
}
struct TypographyMenu:View{@ObservedObject var state:ReaderState;var body:some View{Group{Picker("Font",selection:$state.font){Text("System").tag("system");Text("Serif").tag("serif");Text("Sans Serif").tag("sans-serif");Text("Monospace").tag("monospace")}.onChange(of:state.font){_ in state.applyTypography()};Stepper("Font \(Int(state.fontSize)) pt",value:$state.fontSize,in:10...36,step:1).onChange(of:state.fontSize){_ in state.applyTypography()};Stepper("Line \(state.lineHeight,specifier:"%.1f")",value:$state.lineHeight,in:1...2.4,step:0.1).onChange(of:state.lineHeight){_ in state.applyTypography()};Stepper("Margin \(Int(state.margin))",value:$state.margin,in:0...96,step:8).onChange(of:state.margin){_ in state.applyTypography()}}}}
#else
@main enum LeafCLI{static func main(){print("Leaf's UI requires macOS. Run swift test for portable core checks.")}}
#endif
