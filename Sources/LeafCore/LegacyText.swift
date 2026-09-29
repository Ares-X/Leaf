import Foundation

/// Palm/TCR layout and AZW4 Print Replica extraction follow SumatraPDF.
/// PalmDbReader.cpp is BSD-licensed; MobiDoc.cpp is AGPL/GPL project code.
/// See THIRD_PARTY.md for pinned source revisions and notices.
public enum LegacyText{
    public static func tcr(_ data:Data)throws->Data{
        let b=[UInt8](data);guard b.starts(with:Array("!!8-Bit!!".utf8))else{throw ReadError("Invalid TCR header")}
        var p=9,dict:[ArraySlice<UInt8>]=[]
        for _ in 0..<256{guard p<b.count else{throw ReadError("Truncated TCR dictionary")};let n=Int(b[p]);p+=1;guard n<=b.count-p else{throw ReadError("Truncated TCR entry")};dict.append(b[p..<p+n]);p+=n}
        var out=Data();for i in b[p...]{out.append(contentsOf:dict[Int(i)])};return out
    }

    public static func palm(_ data:Data,replica:Bool=false)throws->Data{
        let b=[UInt8](data)
        func be(_ p:Int,_ n:Int)throws->Int{guard p>=0,p+n<=b.count else{throw ReadError("Truncated Palm document")};return b[p..<p+n].reduce(0){($0<<8)|Int($1)}}
        let count=try be(76,2);guard count>=2,78+count*8<=b.count else{throw ReadError("Invalid Palm record table")}
        var offsets=try(0..<count).map{try be(78+$0*8,4)};offsets.append(b.count)
        guard offsets[0]>=78+count*8,zip(offsets,offsets.dropFirst()).allSatisfy({$0<=$1})else{throw ReadError("Invalid Palm record offsets")}
        let h=offsets[0];guard offsets[1]-h>=16 else{throw ReadError("Truncated Palm header")}
        let compression=try be(h,2),length=try be(h+4,4),records=try be(h+8,2)
        guard records>0,records<count,[1,2].contains(compression)else{throw ReadError("Unsupported Palm compression or empty document")}
        if replica,try be(h+12,2) != 0{throw ReadError("Encrypted Kindle document")}
        var raw=[UInt8]()
        for i in 1...records{let r=Array(b[offsets[i]..<offsets[i+1]]);raw += try compression==1 ? r:unpackPalm(r)}
        guard raw.count>=length else{throw ReadError("Truncated Palm text")}
        raw=Array(raw.prefix(length))
        return replica ? try printReplica(Data(raw)):Data(raw)
    }

    /// Equivalent to Sumatra's ExtractPdfFromMopRaw(): the first section of
    /// the first %MOP table is the embedded PDF. Falling back to %PDF is also
    /// what Sumatra does for old/non-table Print Replica payloads.
    static func printReplica(_ raw:Data)throws->Data{
        guard raw.count>=5 else{throw ReadError("Print Replica payload is empty")}
        if raw.prefix(4) != Data("%MOP".utf8){
            guard let p=raw.range(of:Data("%PDF-".utf8))?.lowerBound else{throw ReadError("Print Replica contains no PDF")}
            return raw.subdata(in:p..<raw.endIndex)
        }
        func be32(_ p:Int)throws->Int{
            guard p+4<=raw.count else{throw ReadError("Truncated %MOP table")}
            return raw[p..<p+4].reduce(0){($0<<8)|Int($1)}
        }
        let tables=try be32(4);guard tables>0,tables<=32 else{throw ReadError("Invalid %MOP table")}
        var p=8
        for _ in 0..<tables{_ = try be32(p);p+=4}
        let offset=try be32(p),length=try be32(p+4)
        guard length>=5,offset>=0,length>=0,offset<=raw.count,length<=raw.count-offset else{throw ReadError("Invalid %MOP PDF section")}
        let pdf=raw.subdata(in:offset..<offset+length)
        guard pdf.starts(with:Data("%PDF-".utf8))else{throw ReadError("First %MOP section is not PDF")}
        return pdf
    }

    static func unpackPalm(_ b:[UInt8])throws->[UInt8]{
        var out:[UInt8]=[],p=0
        while p<b.count{let c=Int(b[p]);p+=1;switch c{
        case 1...8:guard c<=b.count-p else{throw ReadError("Truncated Palm literal")};out+=b[p..<p+c];p+=c
        case 0,9...127:out.append(UInt8(c))
        case 128...191:guard p<b.count else{throw ReadError("Truncated Palm back-reference")};let pair=(c<<8)|Int(b[p]);p+=1;let distance=(pair&0x3fff)>>3,n=(pair&7)+3;guard distance>0,distance<=out.count else{throw ReadError("Invalid Palm back-reference")};for _ in 0..<n{out.append(out[out.count-distance])}
        default:out += [32,UInt8(c^128)]}}
        return out
    }
}
