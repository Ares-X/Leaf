import Foundation
import CZip
public enum ZipError: Error { case invalid, missing, unsupported }
public struct ZipEntry: Sendable {
    public let path:String; let method:UInt16, compressed:Int, size:Int; let offset:UInt64
    public var isDirectory:Bool { path.hasSuffix("/") }
}
public final class ZipArchive: @unchecked Sendable {
    public let entries:[ZipEntry]; private let url:URL; private let map:[String:ZipEntry]; private let lock=NSLock()
    public init(url:URL) throws { self.url=url; entries=try Self.directory(url); map=Dictionary(entries.map{($0.path,$0)},uniquingKeysWith:{_,b in b}) }
    public func data(forPath path:String)throws->Data { guard let e=map[path] else{throw ZipError.missing}; return try data(e) }
    func data(_ e:ZipEntry)throws->Data {
        if e.isDirectory{return Data()}; lock.lock(); defer{lock.unlock()}
        let f=try FileHandle(forReadingFrom:url); defer{try? f.close()}; try f.seek(toOffset:e.offset)
        guard let h=try f.read(upToCount:30),h.count==30,h.u32(0)==0x04034b50 else{throw ZipError.invalid}
        try f.seek(toOffset:e.offset+UInt64(30+Int(h.u16(26))+Int(h.u16(28))))
        guard let input=try f.read(upToCount:e.compressed),input.count==e.compressed else{throw ZipError.invalid}
        if e.method==0{return input}; guard e.method==8 else{throw ZipError.unsupported}
        var out=Data(count:e.size),written=0; let n=e.size
        let status=input.withUnsafeBytes{src in out.withUnsafeMutableBytes{dst in leaf_inflate_raw(src.bindMemory(to:UInt8.self).baseAddress,input.count,dst.bindMemory(to:UInt8.self).baseAddress,n,&written)}}
        guard status==0,written==n else{throw ZipError.invalid}; return out
    }
    public func extractAll(to root:URL)throws {
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        for e in entries { let parts=e.path.split(separator:"/"); guard !e.path.hasPrefix("/"),!parts.contains("..") else{continue}; let dst=parts.reduce(root){$0.appendingPathComponent(String($1))}
            if e.isDirectory{try FileManager.default.createDirectory(at:dst,withIntermediateDirectories:true)} else {try FileManager.default.createDirectory(at:dst.deletingLastPathComponent(),withIntermediateDirectories:true);try data(e).write(to:dst)}
        }
    }
    static func directory(_ url:URL)throws->[ZipEntry] {
        let f=try FileHandle(forReadingFrom:url);defer{try?f.close()};let size=try f.seekToEnd();guard size>=22 else{throw ZipError.invalid}
        let n=Int(min(size,65557));try f.seek(toOffset:size-UInt64(n));guard let tail=try f.read(upToCount:n),let end=tail.last(0x06054b50) else{throw ZipError.invalid}
        let count=Int(tail.u16(end+10)),bytes=Int(tail.u32(end+12));try f.seek(toOffset:UInt64(tail.u32(end+16)));guard let dir=try f.read(upToCount:bytes) else{throw ZipError.invalid}
        var out:[ZipEntry]=[],p=0;for _ in 0..<count{guard p+46<=dir.count,dir.u32(p)==0x02014b50 else{throw ZipError.invalid};let nl=Int(dir.u16(p+28)),x=Int(dir.u16(p+30)),c=Int(dir.u16(p+32));guard p+46+nl+x+c<=dir.count else{throw ZipError.invalid};let name=String(decoding:dir[(p+46)..<(p+46+nl)],as:UTF8.self);out.append(.init(path:name,method:dir.u16(p+10),compressed:Int(dir.u32(p+20)),size:Int(dir.u32(p+24)),offset:UInt64(dir.u32(p+42))));p+=46+nl+x+c};return out
    }
}
private extension Data {
    func u16(_ i:Int)->UInt16{UInt16(self[i])|UInt16(self[i+1])<<8};func u32(_ i:Int)->UInt32{UInt32(u16(i))|UInt32(u16(i+2))<<16}
    func last(_ s:UInt32)->Int?{guard count>=4 else{return nil};for i in stride(from:count-4,through:0,by:-1) where u32(i)==s{return i};return nil}
}
