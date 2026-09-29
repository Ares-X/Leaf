#if os(macOS)
import AppKit
import SwiftUI
import ImageIO
import LeafCore

actor Pages {
    private let archive: Archive?
    private let names: [String]
    private let url: URL
    private var native: NativeFile?
    private let source: CGImageSource?
    let count: Int
    // At most three viewport-sized images; never keep an entire comic decoded.
    private var cache: [(String, CGImage)] = []
    init(_ url: URL, format: Format) throws {
        self.url = url
        if format == .comic && url.hasDirectoryPath {
            archive = nil; source = nil
            let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])?.allObjects as? [URL] ?? []
            names = files.filter { Format.detect($0.lastPathComponent) == .image }.map { String($0.path.dropFirst(url.path.count + (url.path.hasSuffix("/") ? 0 : 1))) }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            count = names.count
        } else if format == .comic {
            let a = try Archive(url)
            archive = a; source = nil
            names = url.pathExtension.lowercased() == "ora" ? a.entries.filter { $0.name == "mergedimage.png" }.map(\.name) : a.images
            count = names.count
        } else if format == .image, let s = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) {
            source = s; archive = nil; names = []
            count = CGImageSourceGetCount(s)
        } else {
            source = nil; archive = nil; names = []
            let n = try NativeFile(url, engine: format == .djvu ? "DjVu" : (url.pathExtension.lowercased() == "jxl" ? "JPEGXL" : "MuPDF"))
            native = n; count = n.count
        }
        guard count > 0 else { throw ReadError("No readable pages found") }
    }
    func image(_ page: Int, width: Int) throws -> CGImage {
        try Task.checkCancellation()
        guard (0..<count).contains(page) else { throw ReadError("Page out of range") }
        let width = max(128, width), key = "\(page):\(width)"
        if let i = cache.firstIndex(where: { $0.0 == key }) {
            let hit = cache.remove(at: i); cache.append(hit); return hit.1
        }
        let image: CGImage
        if let native { image = try native.image(page, width: width) }
        else {
            let data = try archive.map { try $0.data(names[page]) } ?? (url.hasDirectoryPath ? Data(contentsOf: url.appendingPathComponent(names[page])) : nil)
            let s = data.flatMap { CGImageSourceCreateWithData($0 as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) } ?? source
            let index = source != nil ? page : 0
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: width,
                kCGImageSourceShouldCacheImmediately: true]
            if let s, let decoded = CGImageSourceCreateThumbnailAtIndex(s, index, options as CFDictionary) { image = decoded }
            else if let data {
                // Rare archive image codecs need the native decoder. Materialize one page, not the archive.
                let temp = try TemporaryDirectory()
                let file = temp.url.appendingPathComponent(URL(fileURLWithPath: names[page]).lastPathComponent)
                try data.write(to: file)
                image = try NativeFile(file, engine: file.pathExtension.lowercased() == "jxl" ? "JPEGXL" : "MuPDF").image(0, width: width)
            } else { throw ReadError("The installed image decoder cannot read this image") }
        }
        cache.append((key, image))
        while cache.count > 3 || (cache.count > 1 && cache.reduce(0, { $0 + $1.1.bytesPerRow * $1.1.height }) > 64 * 1024 * 1024) { cache.removeFirst() }
        return image
    }
    func frameDelay(_ page: Int) -> Double? {
        guard url.pathExtension.lowercased() == "gif", count > 1, let source,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, page, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return nil }
        return max(0.02, gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? gif[kCGImagePropertyGIFDelayTime] as? Double ?? 0.1)
    }
    func find(_ query: String, after page: Int) -> Int? {
        guard let native, native.hasText, !query.isEmpty else { return nil }
        for offset in 1...count {
            if Task.isCancelled { return nil }
            let index = (page + offset) % count
            if native.text(index)?.localizedCaseInsensitiveContains(query) == true { return index }
        }
        return nil
    }
}

@MainActor struct RasterReader: View {
    @ObservedObject var state: ReaderState
    let pages: Pages
    @State private var images: [CGImage] = []
    @State private var isAnimation = false
    @State private var playing = false
    var body: some View {
        GeometryReader { geometry in
            let width = max(128, Int(geometry.size.width * (NSScreen.main?.backingScaleFactor ?? 2) * state.zoom / (state.spread ? 2 : 1)))
            ScrollView([.horizontal, .vertical]) {
                HStack(spacing: 4) {
                    ForEach(Array((state.rtl ? Array(images.reversed()) : images).enumerated()), id: \.offset) { _, image in
                        Image(decorative: image, scale: 1).resizable().scaledToFit()
                            .frame(width: geometry.size.width * CGFloat(state.zoom) / CGFloat(max(1, images.count)),
                                   height: state.fitWidth ? nil : geometry.size.height * CGFloat(state.zoom))
                    }
                }.frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
            }
            .task(id: "\(state.page):\(width):\(state.spread)") {
                do {
                    var result = [try await pages.image(state.page, width: width)]
                    if state.spread, state.page + 1 < state.count { result.append(try await pages.image(state.page + 1, width: width)) }
                    guard !Task.isCancelled else { return }; images = result
                    if state.page + result.count < state.count { _ = try? await pages.image(state.page + result.count, width: width) }
                } catch { if !Task.isCancelled { state.error = error.localizedDescription } }
            }
            .focusable().onMoveCommand { direction in
                if direction == .left { state.turn(state.rtl ? 1 : -1) }
                if direction == .right { state.turn(state.rtl ? -1 : 1) }
            }
        }
        .overlay(alignment: .topTrailing) {
            if isAnimation { Button(playing ? "Pause" : "Play") { playing.toggle() }.padding(8) }
        }
        .task { isAnimation = await pages.frameDelay(0) != nil; playing = isAnimation }
        .task(id: playing) {
            while playing, !Task.isCancelled, let delay = await pages.frameDelay(state.page) {
                do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
                guard !Task.isCancelled else { return }
                state.page = (state.page + 1) % max(1, state.count)
            }
        }.onChange(of: state.command.id) { _ in
            if state.command.name == "find" {
                let query = state.command.text, current = state.page, command = state.command.id
                Task {
                    let match = await pages.find(query, after: current)
                    guard state.command.id == command, case .pages(let active)? = state.document?.content, active === pages else { return }
                    if let match { state.page = match; state.persist() }
                    else { state.status = "No matching text (image-only pages have no searchable text)" }
                }
            }
        }
    }
}
#endif
