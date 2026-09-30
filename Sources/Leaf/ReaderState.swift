#if os(macOS)
import SwiftUI
import LeafCore
import Darwin

enum ReaderAction:Equatable{
    case none,next,previous,print,style,toc
    case page(Int),href(String),zoom(Double),fit(String),find(String),rotate(Int)
}
struct ReaderCommand:Equatable{var revision=0;var action:ReaderAction = .none}
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
    private var loading:Task<Void,Never>?,reloadTask:Task<Void,Never>?,watch:DispatchSourceFileSystemObject?
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
    var isText:Bool{if case .text=document?.content{return true};return false}
    var isPDF:Bool{if case .pdf=document?.content{return true};return false}
    var isFixed:Bool{guard let d=document else{return false};switch d.content{case .pdf,.pages:return true;default:return false}}
    var isCHM:Bool{if case .chm=document?.content{return true};return false}
    var supportsFlow:Bool{isFixed}
    var supportsSpread:Bool{isFixed}
    var supportsRTL:Bool{isFixed}
    var supportsFit:Bool{isFixed}
    var supportsRotation:Bool{isFixed}
    var supportsSearch:Bool{isPDF || isText || isCHM || searchable}
    var hasDocument:Bool{document != nil}
    var canTurn:Bool{isCHM ? hasDocument:count>1}
    var canSaveCopy:Bool{document?.url.hasDirectoryPath == false}
    var printsCurrentPageOnly:Bool{if case .pages=document?.content{return count>1};return false}
    var printTitle:String{printsCurrentPageOnly ? "Print Current Page…":"Print…"}
    var hasBookmark:Bool{guard let u=document?.url else{return false};return UserDefaults.standard.data(forKey:"bookmark:"+u.standardizedFileURL.path) != nil}
    var positionLabel:String{count>0 ? "\(min(page+1,count)) / \(count)":"— / —"}
    var resolvedTheme:String{theme=="system" ? (NSApp.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? "dark":"light"):theme}
    var zoomLabel:String{
        if isText || isCHM || fit=="custom"{return "\(Int(zoom*100))%"}
        if fit=="width"{return "Fit Width"}
        if fit=="actual"{return "100%"}
        return "Fit Page"
    }
    func send(_ action:ReaderAction){command = .init(revision:command.revision &+ 1,action:action)}
    func showFindPanel(){guard supportsSearch else{return};showFind=true}
    func closeFind(){showFind=false;status="";send(.toc)}
    func toggleFind(){showFind ? closeFind():showFindPanel()}
    func chooseFile(){let p=NSOpenPanel();p.canChooseDirectories=true;p.begin{[weak self] r in if r == .OK,let u=p.url{self?.open(u)}}}
    func open(_ url:URL){
        persist();generation+=1;let g=generation;loading?.cancel();busy=true;error=nil;status="Opening \(url.lastPathComponent)…"
        loading=Task{let worker=Task.detached(priority:.userInitiated){try ReadingDocument.open(url)}
            do{let opened=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()});guard !Task.isCancelled,g==generation else{return}
                command=ReaderCommand();readPreferences(layout:true);outline=[];outlineBusy=false;showFind=false;page=0;count=0;zoom=1;rotation=0;reflowable=false;searchable=false;renderRevision=0
                if let d=UserDefaults.standard.data(forKey:"position:"+url.standardizedFileURL.path),let p=try? JSONDecoder().decode(ReadingPosition.self,from:d){page=max(0,p.page)}
                document=opened;busy=false;status="";watchFile(url);NSDocumentController.shared.noteNewRecentDocumentURL(url)
            }catch{if !Task.isCancelled,g==generation{self.error=error.localizedDescription;busy=false;status=""}}}
    }
    func close(){generation+=1;persist();loading?.cancel();stopWatch();document=nil;busy=false;outline=[];outlineBusy=false;showFind=false;count=0;status="";reflowable=false;searchable=false;renderRevision=0}
    func reload(){guard !busy,let u=document?.url else{return};persist();generation+=1;let g=generation;loading?.cancel();busy=true;status="Reloading…";loading=Task{let worker=Task.detached(priority:.userInitiated){try ReadingDocument.open(u)};do{let opened=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()});guard !Task.isCancelled,g==generation else{return};command=ReaderCommand();outline=[];outlineBusy=false;reflowable=false;searchable=false;document=opened;busy=false;watchFile(u);status=""}catch{if !Task.isCancelled,g==generation{busy=false;status="";error=error.localizedDescription}}}}
    func persist(){guard let u=document?.url,let d=try? JSONEncoder().encode(ReadingPosition(page:page))else{return};UserDefaults.standard.set(d,forKey:"position:"+u.standardizedFileURL.path)}
    func turn(_ d:Int){if isCHM{send(d>0 ? .next:.previous);return};page=max(0,min(max(0,count-1),page+d*((spread && isFixed) ? 2:1)));send(.page(page));persist()}
    func go(_ s:String){guard let n=Double(s),n.isFinite else{return};page=Int(max(0,min(Double(max(0,count-1)),n-1)));send(.page(page));persist()}
    func sibling(_ delta:Int){guard let u=document?.url,let files=try? FileManager.default.contentsOfDirectory(at:u.deletingLastPathComponent(),includingPropertiesForKeys:nil,options:[.skipsHiddenFiles])else{return};let list=files.filter{Format.detect($0.lastPathComponent) != .unknown}.sorted{$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending};guard let i=list.firstIndex(of:u),list.indices.contains(i+delta)else{return};open(list[i+delta])}
    func saveCopy(){
        guard let u=document?.url,!u.hasDirectoryPath else{error="Save a Copy is only available for files.";return}
        let p=NSSavePanel();p.nameFieldStringValue=u.lastPathComponent
        p.begin{r in guard r == .OK,let d=p.url else{return};do{
            let fm=FileManager.default,source=u.standardizedFileURL.resolvingSymlinksInPath(),destination=d.standardizedFileURL.resolvingSymlinksInPath()
            guard source != destination else{throw ReadError("Choose a different location for Save a Copy.")}
            let temp=d.deletingLastPathComponent().appendingPathComponent(".Leaf-copy-"+UUID().uuidString);defer{try? fm.removeItem(at:temp)}
            try fm.copyItem(at:u,to:temp)
            if fm.fileExists(atPath:d.path){_ = try fm.replaceItemAt(d,withItemAt:temp)}else{try fm.moveItem(at:temp,to:d)}
        }catch{self.error=error.localizedDescription}}
    }
    func watchFile(_ u:URL){
        stopWatch();guard !u.hasDirectoryPath else{return};let fd=Darwin.open(u.path,O_EVTONLY);guard fd>=0 else{return}
        let source=DispatchSource.makeFileSystemObjectSource(fileDescriptor:fd,eventMask:[.write,.delete,.rename],queue:.main);watch=source
        source.setEventHandler{[weak self] in guard let self,!self.busy,let source=self.watch,self.document?.url==u else{return};let e=source.data;self.status="File changed on disk";self.reloadTask?.cancel();self.reloadTask=Task{try? await Task.sleep(nanoseconds:250_000_000);guard !Task.isCancelled,!self.busy,self.document?.url==u else{return};if e.contains(.delete)||e.contains(.rename){guard FileManager.default.fileExists(atPath:u.path) else{self.status="File moved or deleted";self.stopWatch();return}};self.reload()}}
        source.setCancelHandler{Darwin.close(fd)};source.resume()
    }
    func windowClosed(){persist();generation+=1;loading?.cancel();stopWatch()}
    func stopWatch(){reloadTask?.cancel();reloadTask=nil;watch?.cancel();watch=nil}
    func copyPath(){guard let p=document?.url.path else{return};NSPasteboard.general.clearContents();NSPasteboard.general.setString(p,forType:.string)}
    func printDocument(){send(.print)}
    func setZoom(_ v:Double){zoom=max(0.25,min(6,v));fit="custom";send(.zoom(zoom))}
    func setFit(_ v:String){guard supportsFit,["page","width","actual"].contains(v) else{return};fit=v;zoom=1;UserDefaults.standard.set(v,forKey:"fit");send(.fit(v))}
    func setFlow(_ v:String){guard ["paged","continuous"].contains(v) else{return};flow=v;UserDefaults.standard.set(v,forKey:"flow")}
    func applyTypography(){let d=UserDefaults.standard;d.set(font,forKey:"font");d.set(fontSize,forKey:"fontSize");d.set(lineHeight,forKey:"lineHeight");d.set(margin,forKey:"margin");send(.style)}
    func setTheme(_ v:String){theme=v;UserDefaults.standard.set(v,forKey:"theme");if isText || isCHM || reflowable{send(.style)}}
    func rotate(_ d:Int){guard supportsRotation else{return};rotation=(rotation+d+360)%360;send(.rotate(d))}
    func bookmark(){guard let u=document?.url else{return};persist();UserDefaults.standard.set(UserDefaults.standard.data(forKey:"position:"+u.standardizedFileURL.path),forKey:"bookmark:"+u.standardizedFileURL.path);status="Bookmark saved"}
    func restoreBookmark(){guard let u=document?.url,let d=UserDefaults.standard.data(forKey:"bookmark:"+u.standardizedFileURL.path),let p=try? JSONDecoder().decode(ReadingPosition.self,from:d)else{return};go(String(p.page+1))}
}

#endif
