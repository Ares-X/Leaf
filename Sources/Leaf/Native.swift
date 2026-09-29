#if os(macOS)
import AppKit
import Darwin
import LeafCore

/// A tiny ABI, not a plug-in framework. Libraries load only when their format is opened.
final class NativeFile {
    typealias Open = @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<CChar>) -> UnsafeMutableRawPointer?
    typealias Close = @convention(c) (UnsafeMutableRawPointer) -> Void
    typealias Count = @convention(c) (UnsafeMutableRawPointer) -> Int32
    typealias Render = @convention(c) (UnsafeMutableRawPointer, Int32, Int32, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<CChar>) -> UnsafeMutableRawPointer?
    let library: UnsafeMutableRawPointer
    let document: UnsafeMutableRawPointer
    private let closeDocument:Close,render:Render?
    private let textFn:UnsafeMutableRawPointer?,pathFn:UnsafeMutableRawPointer?,readFn:UnsafeMutableRawPointer?,relayoutFn:UnsafeMutableRawPointer?
    let count:Int

    init(_ url: URL, engine: String) throws {
        let candidates = [Bundle.main.privateFrameworksURL, URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/engines")].compactMap { $0?.appendingPathComponent(engine + ".dylib").path }
        let path = candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates[0]
        guard let library = dlopen(path, RTLD_LOCAL | RTLD_NOW) else {
            throw ReadError("\(engine) engine is missing. Build Leaf with scripts/build-engines.sh, then rebuild the app.")
        }
        func symbol<T>(_ name: String, _: T.Type) throws -> T {
            guard let p = dlsym(library, name) else { throw ReadError("Incompatible \(engine) engine: \(name)") }
            return unsafeBitCast(p, to: T.self)
        }
        do {
            let abi = try symbol("lf_abi", (@convention(c) () -> Int32).self)
            guard abi() == 1 else { throw ReadError("Incompatible engine ABI") }
            let open = try symbol("lf_open", Open.self), close = try symbol("lf_close", Close.self)
            let pageCount = try symbol("lf_count", Count.self)
            var error = [CChar](repeating: 0, count: 512)
            guard let document = open(url.path, &error) else { throw ReadError(String(cString: error).isEmpty ? "Cannot decode this file" : String(cString: error)) }
            let count = Int(pageCount(document))
            guard count > 0 else { close(document); throw ReadError("Document has no readable content") }
            self.library=library;self.document=document;self.closeDocument=close;self.render=dlsym(library,"lf_render").map{unsafeBitCast($0,to:Render.self)};self.textFn=dlsym(library,"lf_text");self.pathFn=dlsym(library,"lf_path");self.readFn=dlsym(library,"lf_read");self.relayoutFn=dlsym(library,"lf_relayout");self.count=count
        } catch { dlclose(library); throw error }
    }
    deinit { closeDocument(document); dlclose(library) }
    func symbol<T>(_ name: String, _: T.Type) throws -> T {
        guard let p = dlsym(library, name) else { throw ReadError("This engine does not provide \(name)") }
        return unsafeBitCast(p, to: T.self)
    }
    func image(_ page: Int, width: Int) throws -> CGImage {
        var info = [Int32](repeating: 0, count: 4), error = [CChar](repeating: 0, count: 512)
        guard let render else{throw ReadError("This engine cannot render pages")};guard let p=render(document,Int32(page),Int32(width),&info,&error) else{
            throw ReadError(String(cString: error).isEmpty ? "Cannot render page" : String(cString: error))
        }
        let w = Int(info[0]), h = Int(info[1]), stride = Int(info[2]), channels = Int(info[3])
        guard w>0,h>0,[3,4].contains(channels),w<=Int.max/channels,stride>=w*channels,stride<=Int.max/h else{free(p);throw ReadError("Invalid page bitmap")}
        let bytes=stride*h;guard bytes<=512*1024*1024 else{free(p);throw ReadError("Page bitmap is too large")}
        let data=Data(bytesNoCopy:p,count:bytes,deallocator:.free)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: channels * 8,
                                  bytesPerRow: stride, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: (channels == 4 ? CGImageAlphaInfo.last : .none).rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw ReadError("Cannot create page image")
        }
        return image
    }
    var hasText:Bool{textFn != nil}
    var isReflowable:Bool{relayoutFn != nil}
    func relayout(fontSize:Double,lineHeight:Double,margin:Double,font:String)->Int?{
        typealias Layout=@convention(c)(UnsafeMutableRawPointer,Float,UnsafePointer<CChar>)->Int32
        guard let relayoutFn else{return nil}
        let family=font=="serif" ? "serif":font=="monospace" ? "monospace":font=="sans-serif" ? "sans-serif":"system-ui"
        let css="body{font-family:\(family);line-height:\(lineHeight);margin:\(margin)px}"
        return css.withCString{let n=unsafeBitCast(relayoutFn,to:Layout.self)(document,Float(fontSize),$0);return n>0 ? Int(n):nil}
    }
    func text(_ page: Int) -> String? {
        typealias Get = @convention(c) (UnsafeMutableRawPointer, Int32) -> UnsafeMutablePointer<CChar>?
        guard let fn=textFn else{return nil};let get=unsafeBitCast(fn,to:Get.self);guard let p=get(document,Int32(page)) else{return nil}
        defer { free(p) }; return String(cString: p)
    }
    func path(_ index: Int) throws -> String {
        typealias Get = @convention(c) (UnsafeMutableRawPointer, Int32) -> UnsafePointer<CChar>?
        guard let fn=pathFn else{throw ReadError("Missing CHM path API")};let get=unsafeBitCast(fn,to:Get.self);guard let p=get(document,Int32(index)) else{throw ReadError("Missing CHM entry")}
        return String(cString: p)
    }
    func data(_ index: Int) throws -> Data {
        typealias Get = @convention(c) (UnsafeMutableRawPointer, Int32, UnsafeMutablePointer<Int>) -> UnsafeMutableRawPointer?
        var size = 0
        guard let fn=readFn else{throw ReadError("Missing CHM read API")};let get=unsafeBitCast(fn,to:Get.self);guard let p=get(document,Int32(index),&size) else{throw ReadError("Cannot read CHM entry")};guard size>=0,size<=512*1024*1024 else{free(p);throw ReadError("CHM entry is too large")}
        return Data(bytesNoCopy:p,count:size,deallocator:.free)
    }
}
#endif
