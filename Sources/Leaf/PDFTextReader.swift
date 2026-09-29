#if os(macOS)
import SwiftUI
import PDFKit

@MainActor struct PDFReader:NSViewRepresentable{
    @ObservedObject var state:ReaderState;let url:URL;let data:Data?
    func makeCoordinator()->Coordinator{Coordinator(state)}
    func makeNSView(context:Context)->PDFView{
        let v=PDFView();v.autoScales=true;v.displayMode=.singlePageContinuous;v.document=data.flatMap(PDFDocument.init(data:)) ?? PDFDocument(url:url)
        let c=context.coordinator;c.view=v;NotificationCenter.default.addObserver(c,selector:#selector(Coordinator.changed),name:.PDFViewPageChanged,object:v)
        c.observers=[NotificationCenter.default.addObserver(forName:.PDFDocumentDidFindMatch,object:v.document,queue:.main){[weak c] n in Task{@MainActor in c?.found(n)}},NotificationCenter.default.addObserver(forName:.PDFDocumentDidEndFind,object:v.document,queue:.main){[weak c] n in Task{@MainActor in c?.finished(n)}}]
        DispatchQueue.main.async{guard c.active,let d=v.document else{return};if d.isLocked{let a=NSAlert();a.messageText="PDF password";let p=NSSecureTextField(frame:NSRect(x:0,y:0,width:260,height:24));a.accessoryView=p;a.addButton(withTitle:"Open");a.addButton(withTitle:"Cancel");guard a.runModal() == .alertFirstButtonReturn,d.unlock(withPassword:p.stringValue)else{state.error="PDF is locked or the password was incorrect";return}};state.count=d.pageCount;state.outline=c.contents(d.outlineRoot,document:d);if let p=d.page(at:min(state.page,max(0,d.pageCount-1))){v.go(to:p)};c.layout()}
        return v
    }
    func updateNSView(_ v:PDFView,context:Context){let c=context.coordinator;c.layout();guard c.command != state.command.id else{return};c.command=state.command.id;switch state.command.name{case"page","href":let i=state.command.name=="href" ? Int(state.command.text) ?? 0:Int(state.command.number);if let p=v.document?.page(at:i){v.go(to:p)};case"zoom":v.autoScales=false;v.scaleFactor=v.scaleFactorForSizeToFit*CGFloat(state.command.number);case"fit":c.fit(state.command.text);case"find":c.find(state.command.text);case"rotate":if let d=v.document{for i in 0..<d.pageCount{if let p=d.page(at:i){p.rotation=(p.rotation+Int(state.command.number)+360)%360}};c.layout()};case"print":NSPrintOperation(view:v).run();default:break}}
    static func dismantleNSView(_ v:PDFView,coordinator:Coordinator){coordinator.active=false;v.document?.cancelFindString();coordinator.observers.forEach{NotificationCenter.default.removeObserver($0)};NotificationCenter.default.removeObserver(coordinator)}
    @MainActor final class Coordinator:NSObject{
        let state:ReaderState;weak var view:PDFView?;var observers:[NSObjectProtocol]=[],active=true,command:UUID?,query="",results:[PDFSelection]=[],hit = -1
        init(_ s:ReaderState){state=s}
        func layout(){guard let v=view else{return};let dark=state.theme=="dark" || (state.theme=="system" && NSApp.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua);v.backgroundColor=dark ? NSColor(white:0.06,alpha:1):.windowBackgroundColor;let mode:PDFDisplayMode=state.flow=="continuous" ? (state.spread ? .twoUpContinuous:.singlePageContinuous):(state.spread ? .twoUp:.singlePage);if v.displayMode != mode{v.displayMode=mode};v.displayDirection=.vertical;v.displaysRTL=state.rtl;if state.fit != "custom"{fit(state.fit)}}
        func fit(_ mode:String){guard let v=view else{return};switch mode{case"actual":v.autoScales=false;v.scaleFactor=1;case"width":if let p=v.currentPage{v.autoScales=false;v.scaleFactor=max(0.1,(v.bounds.width-12)/p.bounds(for:.cropBox).width/(state.spread ? 2:1))};default:v.autoScales=true}}
        @objc func changed(){guard active,let v=view,let d=v.document,let p=v.currentPage else{return};state.page=d.index(for:p);state.persist()}
        @objc func found(_ n:Notification){guard active,let s=n.userInfo?["PDFDocumentFoundSelection"] as? PDFSelection else{return};results.append(s);state.status="\(results.count) matches";if hit<0{select(0)}}
        @objc func finished(_ n:Notification){guard active else{return};state.status=results.isEmpty ? "No matches":"\(results.count) matches"}
        func find(_ t:String){guard !t.isEmpty,let d=view?.document else{return};if query==t,!results.isEmpty{select((hit+1)%results.count);return};d.cancelFindString();query=t;results=[];hit = -1;state.status="Searching…";d.beginFindString(t,withOptions:.caseInsensitive)}
        func select(_ i:Int){hit=i;view?.setCurrentSelection(results[i],animate:true);view?.go(to:results[i])}
        func contents(_ n:PDFOutline?,document:PDFDocument,depth:Int=0)->[ContentsItem]{guard let n else{return[]};return(0..<n.numberOfChildren).flatMap{i->[ContentsItem] in guard let c=n.child(at:i)else{return[]};var a:[ContentsItem]=[];if let p=c.destination?.page{a.append(.init(title:c.label ?? "Untitled",target:String(document.index(for:p)),depth:depth))};return a+contents(c,document:document,depth:depth+1)}}
    }
}

@MainActor struct TextReader:NSViewRepresentable{
    @ObservedObject var state:ReaderState;let text:String
    func makeCoordinator()->Coordinator{Coordinator(state)}
    func makeNSView(context:Context)->NSScrollView{let s=NSTextView.scrollableTextView(),v=s.documentView as! NSTextView;v.isEditable=false;v.isSelectable=true;v.usesFindBar=true;v.string=text;let c=context.coordinator;c.view=v;for(i,x)in text.utf16.enumerated()where x==10{c.lines.append(i+1)};s.contentView.postsBoundsChangedNotifications=true;NotificationCenter.default.addObserver(c,selector:#selector(Coordinator.scrolled),name:NSView.boundsDidChangeNotification,object:s.contentView);c.style();DispatchQueue.main.async{state.count=c.lines.count;c.go(state.page)};return s}
    func updateNSView(_ s:NSScrollView,context:Context){let c=context.coordinator;c.style();guard c.command != state.command.id else{return};c.command=state.command.id;switch state.command.name{case"zoom":c.zoom=state.command.number;c.style();case"fit":c.zoom=1;c.style();case"style":c.style();case"page":c.go(Int(state.command.number));case"find":c.find(state.command.text);case"print":NSPrintOperation(view:s).run();default:break}}
    static func dismantleNSView(_ v:NSScrollView,coordinator:Coordinator){coordinator.active=false;NotificationCenter.default.removeObserver(coordinator)}
    @MainActor final class Coordinator:NSObject{let state:ReaderState;weak var view:NSTextView?;var active=true,lines=[0],command:UUID?,zoom=1.0;init(_ s:ReaderState){state=s}
        func style(){guard let v=view else{return};let size=state.fontSize*zoom,name=state.font=="serif" ? "New York":state.font=="monospace" ? "SF Mono":nil;v.font=name.flatMap{NSFont(name:$0,size:size)} ?? .systemFont(ofSize:size);v.textContainerInset=NSSize(width:state.margin,height:max(16,state.margin/2));let p=NSMutableParagraphStyle();p.lineHeightMultiple=state.lineHeight;v.defaultParagraphStyle=p;v.typingAttributes[.paragraphStyle]=p;let dark=state.theme=="dark" || (state.theme=="system" && NSApp.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua);v.textColor=dark ? NSColor(white:0.86,alpha:1):.textColor;v.backgroundColor=dark ? NSColor(white:0.07,alpha:1):.textBackgroundColor}
        func go(_ n:Int){view?.scrollRangeToVisible(NSRange(location:lines[max(0,min(n,lines.count-1))],length:0))}
        func find(_ q:String){guard let v=view,!q.isEmpty else{return};let t=v.string as NSString,start=NSMaxRange(v.selectedRange());var r=t.range(of:q,options:.caseInsensitive,range:NSRange(location:min(start,t.length),length:max(0,t.length-start)));if r.location==NSNotFound{r=t.range(of:q,options:.caseInsensitive)};if r.location != NSNotFound{v.setSelectedRange(r);v.scrollRangeToVisible(r)}else{state.status="No matches"}}
        @objc func scrolled(){guard active,let v=view,let m=v.layoutManager,let c=v.textContainer,m.numberOfGlyphs>0 else{return};let g=m.glyphIndex(for:NSPoint(x:0,y:max(0,v.visibleRect.minY-v.textContainerInset.height)),in:c),ch=m.characterIndexForGlyph(at:min(g,m.numberOfGlyphs-1));var lo=0,hi=lines.count;while lo<hi{let mid=(lo+hi)/2;if lines[mid]<=ch{lo=mid+1}else{hi=mid}};state.page=max(0,lo-1);state.persist()}
    }}
#endif
