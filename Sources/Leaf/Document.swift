#if os(macOS)
import AppKit
import LeafCore

final class TemporaryDirectory {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Leaf-" + UUID().uuidString, isDirectory: true)
    init() throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: url) }
}

struct ReadingDocument {
    enum Content { case pdf(URL, Data?), text(String), book(BookSource), pages(Pages) }
    let url: URL
    let content: Content
    let temporary: TemporaryDirectory?
    init(url: URL, content: Content, temporary: TemporaryDirectory? = nil) {
        self.url = url; self.content = content; self.temporary = temporary
    }
    static func open(_ url: URL) throws -> ReadingDocument {
        try Task.checkCancellation()
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let folder = URL(fileURLWithPath: url.path, isDirectory: true)
            return .init(url: folder, content: .pages(try Pages(folder, format: .comic)))
        }
        var format = Format.detect(url.lastPathComponent)
        let file = try FileHandle(forReadingFrom: url)
        let prefix = try file.read(upToCount: 128) ?? Data(); try file.close()
        if prefix.starts(with: Data("%PDF-".utf8)) { format = .pdf }
        else if url.pathExtension.lowercased() == "ai" { format = .postscript }
        else if prefix.count >= 68, String(decoding: prefix[60..<68], as: UTF8.self) == "BOOKMOBI", format == .palm { format = .book }
        if prefix.count >= 68, String(decoding: prefix[60..<68], as: UTF8.self) == "TEXtREAd" { format = .palm }
        switch format {
        case .pdf: return .init(url: url, content: .pdf(url, nil))
        case .replica:
            return .init(url: url, content: .pdf(url, try LegacyText.palm(Data(contentsOf: url, options: .mappedIfSafe), replica: true)))
        case .text, .palm, .tcr:
            var data = try Data(contentsOf: url, options: .mappedIfSafe)
            if format == .palm { data = try LegacyText.palm(data) }
            if format == .tcr { data = try LegacyText.tcr(data) }
            return .init(url: url, content: .text(decode(data)))
        case .book, .markdown, .html, .chm:
            return .init(url: url, content: .book(try BookSource(url, format: format)))
        case .image, .comic, .mupdf, .djvu:
            return .init(url: url, content: .pages(try Pages(url, format: format)))
        case .postscript:
            // Like Sumatra, PostScript/PJL support requires Ghostscript, not a home-grown interpreter.
            let candidates = ["/opt/homebrew/bin/gs", "/usr/local/bin/gs", "/usr/bin/gs"]
            guard let gs = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                throw ReadError("PostScript/PJL needs Ghostscript (brew install ghostscript).")
            }
            let temp = try TemporaryDirectory(), output = temp.url.appendingPathComponent("document.pdf")
            let task = Process(); task.executableURL = URL(fileURLWithPath: gs)
            task.arguments = ["-dSAFER", "-dBATCH", "-dNOPAUSE", "-sDEVICE=pdfwrite", "-sOutputFile=" + output.path, "-f", url.path]
            let log = temp.url.appendingPathComponent("convert.log")
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let stream = try FileHandle(forWritingTo: log); defer { try? stream.close() }
            task.standardOutput = stream; task.standardError = stream
            try task.run(); task.waitUntilExit()
            guard task.terminationStatus == 0 else { throw ReadError("Ghostscript could not convert this file.") }
            return .init(url: url, content: .pdf(output, nil), temporary: temp)
        default: throw ReadError("Unsupported document: \(url.lastPathComponent)")
        }
    }
    static func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        var text: String?
        _ = NSString.stringEncoding(for: data, encodingOptions: [:], convertedString: &text, usedLossyConversion: nil)
        return text ?? String(decoding: data, as: UTF8.self)
    }
}
#endif
