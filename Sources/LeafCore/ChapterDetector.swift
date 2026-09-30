import Foundation

public struct DetectedChapter:Sendable,Equatable{
    public let title:String
    public let line:Int
    public let depth:Int
    public init(title:String,line:Int,depth:Int=0){self.title=title;self.line=line;self.depth=depth}
}

/// Lightweight novel TOC detection: structural patterns + line shape + document consistency.
/// It deliberately avoids language models and large rule engines so opening text stays cheap.
public enum ChapterDetector{
    private static let number="〇零一二三四五六七八九十百千万两壹贰叁肆伍陆柒捌玖拾佰仟0-9０-９"
    private static let patterns:[NSRegularExpression]=[
        try! .init(pattern:"^\\s*第\\s*["+number+"]+\\s*([章节節回卷部篇集节话話])(?:\\s*[-—:：]?\\s*.*)?$",options:.caseInsensitive),
        try! .init(pattern:"^\\s*[卷部篇集]\\s*["+number+"]+(?:\\s+.*)?$",options:.caseInsensitive),
        try! .init(pattern:"^\\s*(?:序章|序言|前言|楔子|引子|终章|終章|尾声|尾聲|后记|後記|番外(?:["+number+"]+)?|プロローグ|エピローグ)(?:\\s+.*)?$",options:.caseInsensitive),
        try! .init(pattern:#"^\s*(?:chapter|part|book)\s+(?:[0-9]+|[ivxlcdm]+|one|two|three|four|five|six|seven|eight|nine|ten)(?:\b.*)?$"#,options:.caseInsensitive),
        try! .init(pattern:#"^\s*(?:prologue|epilogue|introduction|preface|appendix)(?:\b.*)?$"#,options:.caseInsensitive)
    ]

    public static func detect(_ text:String)->[DetectedChapter]{
        let lines=text.split(omittingEmptySubsequences:false){$0.isNewline && $0 != "\u{000b}" && $0 != "\u{000c}"}
        var candidates:[(Int,String,Int)]=[]
        for (i,raw) in lines.enumerated(){
            if Task.isCancelled{return[]}
            let title=raw.trimmingCharacters(in:.whitespacesAndNewlines.union(CharacterSet(charactersIn:"\u{feff}")))
            guard !title.isEmpty,title.count<=80,!endsLikeProse(title) else{continue}
            let range=NSRange(title.startIndex..<title.endIndex,in:title)
            guard let family=patterns.firstIndex(where:{$0.firstMatch(in:title,range:range) != nil}) else{continue}
            let isolated=(i==0 || lines[i-1].trimmingCharacters(in:.whitespaces).isEmpty ? 1:0)+(i+1==lines.count || lines[i+1].trimmingCharacters(in:.whitespaces).isEmpty ? 1:0)
            candidates.append((i,title,family*3+isolated))
        }
        guard !candidates.isEmpty else{return[]}
        var families:[Int:Int]=[:]
        for c in candidates{families[c.2/3,default:0]+=1}
        let accepted=candidates.filter{let family=$0.2/3,isolation=$0.2%3;return (families[family] ?? 0)>=2 || isolation==2}
        let grouped=accepted.contains{depth($0.1)==0}
        return accepted.map{line,title,_ in DetectedChapter(title:title,line:line,depth:grouped ? depth(title):0)}
    }

    private static func endsLikeProse(_ s:String)->Bool{"。！？!?；;，,".contains(s.last ?? " ")}
    private static func depth(_ s:String)->Int{
        let range=NSRange(s.startIndex..<s.endIndex,in:s),x=s.lowercased()
        if patterns[1].firstMatch(in:s,range:range) != nil || x.hasPrefix("part ") || x.hasPrefix("book "){return 0}
        if let match=patterns[0].firstMatch(in:s,range:range){
            return "卷部篇集".contains((s as NSString).substring(with:match.range(at:1))) ? 0:1
        }
        return 1
    }

    /// Foundation's line boundaries keep TXT navigation consistent with CRLF, CR and Unicode newlines.
    public static func lineOffsets(_ text:String)->[Int]{
        let value=text as NSString
        var offsets=[0],end=0,contentsEnd=0
        while end<value.length{
            if Task.isCancelled{return[]}
            value.getLineStart(nil,end:&end,contentsEnd:&contentsEnd,for:NSRange(location:end,length:0))
            if end<value.length{offsets.append(end)}
        }
        if contentsEnd<value.length{offsets.append(value.length)}
        return offsets
    }
}
