#if os(macOS)
import SwiftUI
import WebKit
import UniformTypeIdentifiers
import LeafCore

actor CHMSource{
    let url:URL
    private let chm:NativeFile
    private let index:[String:Int]
    let entries:[Archive.Entry]
    init(_ url:URL)throws{
        self.url=url
        let chm=try NativeFile(url,engine:"CHM");self.chm=chm
        var index:[String:Int]=[:],entries:[Archive.Entry]=[]
        for i in 0..<chm.count{
            let path=String(try chm.path(i).drop(while:{$0=="/"}))
            index[path.lowercased()]=i;entries.append(.init(name:path,size:0))
        }
        self.index=index;self.entries=entries
    }
    func response(_ url:URL)throws->Data{
        try Task.checkCancellation()
        if url.path=="/meta"{return try JSONSerialization.data(withJSONObject:["name":self.url.lastPathComponent,"format":"chm","entries":entries.map{["filename":$0.name,"size":$0.size]}])}
        guard url.path.hasPrefix("/entry/") else{throw ReadError("CHM resource not found")}
        let name=String(url.path.dropFirst("/entry/".count));guard Archive.isSafeEntryName(name),let i=index[name.lowercased()] else{throw ReadError("CHM resource not found")}
        let data=try chm.data(i)
        return ["htm","html","hhc","hhk","css"].contains((name as NSString).pathExtension.lowercased()) ? Data(ReadingDocument.decode(data).utf8):data
    }
}

@MainActor struct CHMReader:NSViewRepresentable{
    @ObservedObject var state:ReaderState;let source:CHMSource
    func makeCoordinator()->Coordinator{Coordinator(state:state,source:source)}
    func makeNSView(context:Context)->WKWebView{let c=context.coordinator,x=WKWebViewConfiguration();x.websiteDataStore = .nonPersistent();x.setURLSchemeHandler(c,forURLScheme:"leaf");x.userContentController.add(c,name:"leaf")
        let style="\(state.font)|\(state.fontSize)|\(state.lineHeight)|\(state.margin)|\(state.theme)"
        let s="window.leafStyle='\(style)';"
        x.userContentController.addUserScript(WKUserScript(source:s,injectionTime:.atDocumentStart,forMainFrameOnly:true));let v=WKWebView(frame:.zero,configuration:x);v.navigationDelegate=c;v.load(URLRequest(url:URL(string:"leaf://reader/reader.html")!));return v}
    func updateNSView(_ v:WKWebView,context:Context){let c=context.coordinator;guard c.command != state.command.id else{return};c.command=state.command.id;if state.command.name=="print"{v.printView(nil);return};if c.ready{c.deliver(state.command,to:v)}else{c.pending=state.command}}
    static func dismantleNSView(_ v:WKWebView,coordinator:Coordinator){coordinator.requests.values.forEach{$0.cancel()};coordinator.requests.removeAll();v.configuration.userContentController.removeScriptMessageHandler(forName:"leaf");v.navigationDelegate=nil;v.stopLoading()}
    @MainActor final class Coordinator:NSObject,WKURLSchemeHandler,WKScriptMessageHandler,WKNavigationDelegate{
        let state:ReaderState,source:CHMSource;var command:UUID?,ready=false,pending:ReaderCommand?,requests:[ObjectIdentifier:Task<Void,Never>]=[:];init(state:ReaderState,source:CHMSource){self.state=state;self.source=source}
        func deliver(_ command:ReaderCommand,to v:WKWebView){let m:[String:Any]=["name":command.name,"text":command.text,"number":command.number];if let d=try? JSONSerialization.data(withJSONObject:m){v.evaluateJavaScript("window.leafCommand?.(\(String(decoding:d,as:UTF8.self)))")}}
        func webView(_ v:WKWebView,start t:WKURLSchemeTask){let id=ObjectIdentifier(t);requests[id]=Task{@MainActor in do{guard let u=t.request.url else{throw ReadError("Missing resource URL")};let d:Data;if u.host=="reader"{let p=Bundle.main.resourceURL?.appendingPathComponent("Reader"),root=(p.flatMap{FileManager.default.fileExists(atPath:$0.path) ? $0:nil} ?? Bundle.module.url(forResource:"Reader",withExtension:nil)!).standardizedFileURL.resolvingSymlinksInPath(),f=root.appendingPathComponent(String(u.path.dropFirst())).standardizedFileURL.resolvingSymlinksInPath();guard f.path.hasPrefix(root.path+"/") else{throw ReadError("Invalid reader resource path")};d=try await Task.detached{try Data(contentsOf:f)}.value}else if u.host=="book"{d=try await source.response(u)}else{throw ReadError("Unknown resource host")};guard !Task.isCancelled,requests[id] != nil else{return};let mime=["js":"text/javascript","hhc":"text/html","hhk":"text/html"][u.pathExtension.lowercased()] ?? UTType(filenameExtension:u.pathExtension)?.preferredMIMEType ?? "application/octet-stream";t.didReceive(HTTPURLResponse(url:u,statusCode:200,httpVersion:"HTTP/1.1",headerFields:["Content-Type":mime,"Content-Length":String(d.count)])!);t.didReceive(d);t.didFinish()}catch{if !Task.isCancelled,requests[id] != nil{t.didFailWithError(error)}};requests.removeValue(forKey:id)}}
        func webView(_ v:WKWebView,stop t:WKURLSchemeTask){let id=ObjectIdentifier(t);requests.removeValue(forKey:id)?.cancel()}
        func userContentController(_ c:WKUserContentController,didReceive m:WKScriptMessage){guard m.frameInfo.isMainFrame,let b=m.body as? [String:Any],let t=b["type"] as? String else{return};switch t{case"toc","results":if let i=b["items"],let d=try? JSONSerialization.data(withJSONObject:i),let x=try? JSONDecoder().decode([ContentsItem].self,from:d){if t=="toc"{state.outline=x}else{state.searchResults=x}};if t=="results"{state.showContents=true};case"ready":ready=true;if let pending,let view=m.webView{deliver(pending,to:view);self.pending=nil};case"status":state.status=b["message"] as? String ?? "";case"error":state.error=b["message"] as? String ?? "Unable to render book";case"external":if let h=b["href"] as? String,let u=URL(string:h),["https","http","mailto"].contains(u.scheme){NSWorkspace.shared.open(u)};default:break}}
        func webView(_ v:WKWebView,decidePolicyFor a:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){decisionHandler(["leaf","blob","about","data"].contains(a.request.url?.scheme ?? "") ? .allow:.cancel)}
    }}
#endif
