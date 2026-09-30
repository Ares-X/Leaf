#if os(macOS)
import AppKit
import Darwin
import LeafCore

enum NativeEngine: String {
    case mupdf = "MuPDF"
    case djvu = "DjVu"
    case chm = "CHM"
    case jpegXL = "JPEGXL"
}

final class NativeFile {
    typealias Open = @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<CChar>) -> UnsafeMutableRawPointer?
    typealias Close = @convention(c) (UnsafeMutableRawPointer) -> Void
    typealias Count = @convention(c) (UnsafeMutableRawPointer) -> Int32
    typealias Render = @convention(c) (
        UnsafeMutableRawPointer,
        Int32,
        Int32,
        UnsafeMutablePointer<Int32>,
        UnsafeMutablePointer<CChar>
    ) -> UnsafeMutableRawPointer?

    let library: UnsafeMutableRawPointer
    let document: UnsafeMutableRawPointer
    let count: Int

    private let closeDocument: Close
    private let render: Render?
    private let textFn: UnsafeMutableRawPointer?
    private let pathFn: UnsafeMutableRawPointer?
    private let readFn: UnsafeMutableRawPointer?
    private let relayoutFn: UnsafeMutableRawPointer?

    init(_ url: URL, engine: NativeEngine) throws {
        let name = engine.rawValue + ".dylib"
        let path: String
        if Bundle.main.bundleURL.pathExtension == "app", let frameworks = Bundle.main.privateFrameworksURL {
            path = frameworks.appendingPathComponent(name).path
        } else {
            path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("build/engines")
                .appendingPathComponent(name)
                .path
        }

        guard let library = dlopen(path, RTLD_LOCAL | RTLD_NOW) else {
            let reason = dlerror().map { String(cString: $0) } ?? "unknown loader error"
            throw ReadError("Cannot load \(engine.rawValue): \(reason)")
        }

        func symbol<T>(_ name: String, _: T.Type) throws -> T {
            guard let pointer = dlsym(library, name) else {
                throw ReadError("Incompatible \(engine.rawValue) engine: \(name)")
            }
            return unsafeBitCast(pointer, to: T.self)
        }

        do {
            let open = try symbol("lf_open", Open.self)
            let close = try symbol("lf_close", Close.self)
            let pageCount = try symbol("lf_count", Count.self)

            var error = [CChar](repeating: 0, count: 512)
            guard let document = open(url.path, &error) else {
                let message = String(cString: error)
                throw ReadError(message.isEmpty ? "Cannot decode this file" : message)
            }

            let count = Int(pageCount(document))
            guard count > 0 else {
                close(document)
                throw ReadError("Document has no readable content")
            }

            self.library = library
            self.document = document
            self.closeDocument = close
            self.render = dlsym(library, "lf_render").map { unsafeBitCast($0, to: Render.self) }
            self.textFn = dlsym(library, "lf_text")
            self.pathFn = dlsym(library, "lf_path")
            self.readFn = dlsym(library, "lf_read")
            self.relayoutFn = dlsym(library, "lf_relayout")
            self.count = count
        } catch {
            dlclose(library)
            throw error
        }
    }

    deinit {
        closeDocument(document)
        dlclose(library)
    }

    func image(_ page: Int, width: Int) throws -> CGImage {
        guard let render else {
            throw ReadError("This engine cannot render pages")
        }

        var info = [Int32](repeating: 0, count: 4)
        var error = [CChar](repeating: 0, count: 512)
        guard let pointer = render(document, Int32(page), Int32(width), &info, &error) else {
            let message = String(cString: error)
            throw ReadError(message.isEmpty ? "Cannot render page" : message)
        }

        let width = Int(info[0])
        let height = Int(info[1])
        let stride = Int(info[2])
        let channels = Int(info[3])
        let data = Data(bytesNoCopy: pointer, count: stride * height, deallocator: .free)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: channels * 8,
                bytesPerRow: stride,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(
                    rawValue: (channels == 4 ? CGImageAlphaInfo.last : .none).rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              )
        else {
            throw ReadError("Cannot create page image")
        }

        return image
    }

    var hasText: Bool {
        textFn != nil
    }

    func relayout(
        fontSize: Double,
        lineHeight: Double,
        margin: Double,
        font: String,
        theme: String
    ) -> Int? {
        typealias Layout = @convention(c) (
            UnsafeMutableRawPointer,
            Float,
            UnsafePointer<CChar>
        ) -> Int32

        guard let relayoutFn else { return nil }

        let family = font == "serif"
            ? "serif"
            : font == "monospace"
                ? "monospace"
                : font == "sans-serif"
                    ? "sans-serif"
                    : "system-ui"

        let colors = theme == "dark"
            ? "background:#111;color:#ddd"
            : theme == "light"
                ? "background:#fff;color:#111"
                : ""

        let css = "body{font-family:\(family);line-height:\(lineHeight);margin:\(margin)px;\(colors)} a{color:\(theme == "dark" ? "#8ab4f8" : "#06c")}"
        return css.withCString {
            let layout = unsafeBitCast(relayoutFn, to: Layout.self)
            let count = layout(document, Float(fontSize), $0)
            return count > 0 ? Int(count) : nil
        }
    }

    func text(_ page: Int) -> String? {
        typealias Get = @convention(c) (UnsafeMutableRawPointer, Int32) -> UnsafeMutablePointer<CChar>?
        guard let textFn else { return nil }

        let get = unsafeBitCast(textFn, to: Get.self)
        guard let pointer = get(document, Int32(page)) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    func path(_ index: Int) throws -> String {
        typealias Get = @convention(c) (UnsafeMutableRawPointer, Int32) -> UnsafePointer<CChar>?
        guard let pathFn else { throw ReadError("Missing CHM path API") }

        let get = unsafeBitCast(pathFn, to: Get.self)
        guard let pointer = get(document, Int32(index)) else {
            throw ReadError("Missing CHM entry")
        }
        return String(cString: pointer)
    }

    func data(_ index: Int) throws -> Data {
        typealias Get = @convention(c) (
            UnsafeMutableRawPointer,
            Int32,
            UnsafeMutablePointer<Int>
        ) -> UnsafeMutableRawPointer?

        var size = 0
        guard let readFn else { throw ReadError("Missing CHM read API") }

        let get = unsafeBitCast(readFn, to: Get.self)
        guard let pointer = get(document, Int32(index), &size) else {
            throw ReadError("Cannot read CHM entry")
        }
        return Data(bytesNoCopy: pointer, count: size, deallocator: .free)
    }
}
#endif
