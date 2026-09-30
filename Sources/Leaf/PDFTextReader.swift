#if os(macOS)
import SwiftUI
import PDFKit
import LeafCore

@MainActor struct PDFReader:NSViewRepresentable{
    @ObservedObject var state:ReaderState;let url:URL;let data:Data?
    func makeCoordinator()->Coordinator{Coordinator(state)}
    func makeNSView(context:Context)->PDFView{
        let v=PDFView();v.autoScales=true;v.displayMode = .singlePageContinuous;v.document=data.flatMap(PDFDocument.init(data:)) ?? PDFDocument(url:url)
        let c=context.coordinator;c.view=v;NotificationCenter.default.addObserver(c,selector:#selector(Coordinator.changed),name:.PDFViewPageChanged,object:v)
        c.observers=[NotificationCenter.default.addObserver(forName:.PDFDocumentDidFindMatch,object:v.document,queue:.main){[weak c] n in Task{@MainActor in c?.found(n)}},NotificationCenter.default.addObserver(forName:.PDFDocumentDidEndFind,object:v.document,queue:.main){[weak c] n in Task{@MainActor in c?.finished(n)}},NotificationCenter.default.addObserver(forName:.PDFViewVisiblePagesChanged,object:v,queue:.main){[weak c] _ in Task{@MainActor in c?.applyRotation()}},NotificationCenter.default.addObserver(forName:.PDFViewScaleChanged,object:v,queue:.main){[weak c] _ in Task{@MainActor in c?.scaleChanged()}}]
        DispatchQueue.main.async{guard c.active else{return};guard let d=v.document else{state.error="Cannot read PDF: \(url.lastPathComponent)";return};if d.isLocked{let a=NSAlert();a.messageText="PDF password";let p=NSSecureTextField(frame:NSRect(x:0,y:0,width:260,height:24));a.accessoryView=p;a.addButton(withTitle:"Open");a.addButton(withTitle:"Cancel");guard a.runModal() == .alertFirstButtonReturn,d.unlock(withPassword:p.stringValue)else{state.error="PDF is locked or the password was incorrect";return}};state.count=d.pageCount;if state.showContents{state.outline=c.contents(d.outlineRoot,document:d)};if let p=d.page(at:min(state.page,max(0,d.pageCount-1))){v.go(to:p)};c.layout();DispatchQueue.main.async{c.ignoreScale=false}}
        return v
    }
    func updateNSView(_ v:PDFView,context:Context){
        let c=context.coordinator
        c.layout()
        if state.showContents,state.outline.isEmpty,let d=v.document{state.outline=c.contents(d.outlineRoot,document:d)}
        guard c.command != state.command.revision else{return}
        c.command=state.command.revision
        switch state.command.action{
        case .page(let i):
            if let p=v.document?.page(at:i){v.go(to:p)}
        case .href(let target):
            if let i=Int(target),let p=v.document?.page(at:i){v.go(to:p)}
        case .zoom(let factor):
            c.ignoreScale=true;v.autoScales=false;v.scaleFactor=CGFloat(factor);DispatchQueue.main.async{c.ignoreScale=false}
        case .fit(let mode):c.fit(mode)
        case .find(let text):c.find(text)
        case .rotate(_):c.applyRotation();c.layout()
        case .print:v.document?.printOperation(for:NSPrintInfo.shared,scalingMode:.pageScaleToFit,autoRotate:true)?.run()
        default:break
        }
    }
    static func dismantleNSView(_ v:PDFView,coordinator:Coordinator){coordinator.active=false;v.document?.cancelFindString();coordinator.observers.forEach{NotificationCenter.default.removeObserver($0)};NotificationCenter.default.removeObserver(coordinator)}
    @MainActor final class Coordinator:NSObject{
        let state:ReaderState;weak var view:PDFView?;var observers:[NSObjectProtocol]=[],active=true,command:Int?,query="",results:[PDFSelection]=[],hit = -1,lastSize=CGSize.zero,baseRotation:[Int:Int]=[:],truncated=false,ignoreScale=true
        init(_ s:ReaderState){state=s}
        func layout(){guard let v=view else{return};let resized=v.bounds.size != lastSize;lastSize=v.bounds.size;let dark=state.theme=="dark" || (state.theme=="system" && NSApp.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua);v.backgroundColor=dark ? NSColor(white:0.06,alpha:1):.windowBackgroundColor;let mode:PDFDisplayMode=state.flow=="continuous" ? (state.spread ? .twoUpContinuous:.singlePageContinuous):(state.spread ? .twoUp:.singlePage);if v.displayMode != mode{v.displayMode=mode};v.displayDirection = .vertical;v.displaysRTL=state.rtl;if state.fit != "custom",(resized || state.fit != "width" || v.autoScales){fit(state.fit)}}
        func fit(_ mode:String){guard let v=view else{return};ignoreScale=true;switch mode{case"actual":v.autoScales=false;v.scaleFactor=1;case"width":if let p=v.currentPage{v.autoScales=false;v.scaleFactor=max(0.1,(v.bounds.width-12)/p.bounds(for:.cropBox).width/(state.spread ? 2:1))};default:v.autoScales=true};DispatchQueue.main.async{self.ignoreScale=false}}
        func scaleChanged(){guard active,!ignoreScale,let v=view,!v.autoScales else{return};state.fit="custom";state.zoom=max(0.25,min(6,Double(v.scaleFactor)))}
        func applyRotation(){guard active,let v=view,let d=v.document,(state.rotation != 0 || !baseRotation.isEmpty) else{return};for p in v.visiblePages{let i=d.index(for:p);let base=baseRotation[i] ?? p.rotation;baseRotation[i]=base;let rotation=(base+state.rotation+360)%360;if p.rotation != rotation{p.rotation=rotation}}}
        @objc func changed(){guard active,let v=view,let d=v.document,let p=v.currentPage else{return};applyRotation();state.page=d.index(for:p);state.persist()}
        @objc func found(_ n:Notification){guard active,let s=n.userInfo?["PDFDocumentFoundSelection"] as? PDFSelection else{return};if results.count>=1000{truncated=true;view?.document?.cancelFindString();state.status="1000+ matches";return};results.append(s);state.status="\(results.count) matches";if hit<0{select(0)}}
        @objc func finished(_ n:Notification){guard active else{return};state.status=truncated ? "1000+ matches":results.isEmpty ? "No matches":"\(results.count) matches"}
        func find(_ t:String){guard !t.isEmpty,let d=view?.document else{return};if query==t,!results.isEmpty{select((hit+1)%results.count);return};d.cancelFindString();query=t;results=[];hit = -1;truncated=false;state.status="Searching…";d.beginFindString(t,withOptions:.caseInsensitive)}
        func select(_ i:Int){hit=i;view?.setCurrentSelection(results[i],animate:true);view?.go(to:results[i])}
        func contents(_ n:PDFOutline?,document:PDFDocument,depth:Int=0)->[ContentsItem]{guard let n else{return[]};return(0..<n.numberOfChildren).flatMap{i->[ContentsItem] in guard let c=n.child(at:i)else{return[]};var a:[ContentsItem]=[];if let p=c.destination?.page{a.append(.init(title:c.label ?? "Untitled",target:String(document.index(for:p)),depth:depth))};return a+contents(c,document:document,depth:depth+1)}}
    }
}

@MainActor struct TextReader:NSViewRepresentable{
    @ObservedObject var state:ReaderState;let text:String
    func makeCoordinator()->Coordinator{Coordinator(state)}
    func makeNSView(context:Context)->NSScrollView{
        let content=text,scroll=NSTextView.scrollableTextView(),view=scroll.documentView as! NSTextView,c=context.coordinator
        view.isEditable=false;view.isSelectable=true;view.usesFindBar=true;view.string=content;c.view=view
        scroll.contentView.postsBoundsChangedNotifications=true
        NotificationCenter.default.addObserver(c,selector:#selector(Coordinator.scrolled),name:NSView.boundsDidChangeNotification,object:scroll.contentView)
        c.style(force:true);state.outlineBusy=true
        let scan=Task.detached(priority:.utility){
            let lines=ChapterDetector.lineOffsets(content)
            guard !Task.isCancelled else{return([Int](),[DetectedChapter]())}
            return (lines,ChapterDetector.detect(content))
        }
        c.scanTask=scan
        Task{@MainActor in
            let result=await scan.value
            guard c.active,!scan.isCancelled,!result.0.isEmpty else{return}
            c.lines=result.0;c.indexed=true;state.count=result.0.count;c.go(state.page)
            state.outline=result.1.map{.init(title:$0.title,target:String($0.line),depth:$0.depth)}
            state.outlineBusy=false
        }
        return scroll
    }
    func updateNSView(_ s:NSScrollView,context:Context){
        let c=context.coordinator;c.style()
        guard c.command != state.command.revision else{return}
        c.command=state.command.revision
        switch state.command.action{
        case .zoom(let value):c.zoom=value;c.style()
        case .fit(_):c.zoom=1;c.style()
        case .style:c.style(force:true)
        case .page(let page):c.go(page)
        case .href(let target):c.go(Int(target) ?? 0)
        case .find(let query):c.find(query)
        case .print:if let v=c.view{NSPrintOperation(view:v).run()}
        default:break
        }
    }
    static func dismantleNSView(_ v:NSScrollView,coordinator:Coordinator){coordinator.active=false;coordinator.scanTask?.cancel();coordinator.state.outlineBusy=false;NotificationCenter.default.removeObserver(coordinator)}
    @MainActor final class Coordinator:NSObject{let state:ReaderState;weak var view:NSTextView?;var active=true,indexed=false,lines=[0],command:Int?,zoom=1.0,styleKey="";var scanTask:Task<([Int],[DetectedChapter]),Never>?;init(_ s:ReaderState){state=s}
        func style(force:Bool=false){guard let v=view else{return};let key="\(state.font)|\(state.fontSize)|\(state.lineHeight)|\(state.margin)|\(state.resolvedTheme)|\(zoom)";if !force,key==styleKey{return};styleKey=key;let size=state.fontSize*zoom,name=state.font=="serif" ? "New York":state.font=="monospace" ? "SF Mono":nil;v.font=name.flatMap{NSFont(name:$0,size:size)} ?? .systemFont(ofSize:size);v.textContainerInset=NSSize(width:state.margin,height:max(16,state.margin/2));let p=NSMutableParagraphStyle();p.lineHeightMultiple=state.lineHeight;v.defaultParagraphStyle=p;v.typingAttributes[.paragraphStyle]=p;if v.string.utf16.count>0{v.textStorage?.addAttribute(.paragraphStyle,value:p,range:NSRange(location:0,length:v.string.utf16.count))};let dark=state.theme=="dark" || (state.theme=="system" && NSApp.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua);v.textColor=dark ? NSColor(white:0.86,alpha:1):.textColor;v.backgroundColor=dark ? NSColor(white:0.07,alpha:1):.textBackgroundColor}
        func go(_ n:Int){view?.scrollRangeToVisible(NSRange(location:lines[max(0,min(n,lines.count-1))],length:0))}
        func find(_ q:String){guard let v=view,!q.isEmpty else{return};let t=v.string as NSString,start=NSMaxRange(v.selectedRange());var r=t.range(of:q,options:.caseInsensitive,range:NSRange(location:min(start,t.length),length:max(0,t.length-start)));if r.location==NSNotFound{r=t.range(of:q,options:.caseInsensitive)};if r.location != NSNotFound{v.setSelectedRange(r);v.scrollRangeToVisible(r)}else{state.status="No matches"}}
        @objc func scrolled(){guard active,indexed,let v=view,let m=v.layoutManager,let c=v.textContainer,m.numberOfGlyphs>0 else{return};let g=m.glyphIndex(for:NSPoint(x:0,y:max(0,v.visibleRect.minY-v.textContainerInset.height)),in:c),ch=m.characterIndexForGlyph(at:min(g,m.numberOfGlyphs-1));var lo=0,hi=lines.count;while lo<hi{let mid=(lo+hi)/2;if lines[mid]<=ch{lo=mid+1}else{hi=mid}};state.page=max(0,lo-1);state.persist()}
    }}
#endif
