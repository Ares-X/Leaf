#if os(macOS)
import AppKit
import PDFKit
import LeafCore

func runLeafProcess(_ process: Process) throws {
    try Task.checkCancellation()
    try process.run()

    while process.isRunning {
        if Task.isCancelled {
            process.terminate()
            process.waitUntilExit()
            throw CancellationError()
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
}

final class TemporaryDirectory {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("Leaf-" + UUID().uuidString, isDirectory: true)

    init() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

struct ReadingDocument: Identifiable {
    let id = UUID()
    enum Content {
        case pdf(PDFDocument)
        case text(String)
        case chm(CHMSource)
        case pages(Pages)
    }

    let url: URL
    let content: Content
    let temporary: TemporaryDirectory?

    init(url: URL, content: Content, temporary: TemporaryDirectory? = nil) {
        self.url = url
        self.content = content
        self.temporary = temporary
    }

    static func open(_ url: URL) throws -> ReadingDocument {
        try Task.checkCancellation()

        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let folder = URL(fileURLWithPath: url.path, isDirectory: true)
            return .init(url: folder, content: .pages(try Pages(folder, format: .comic)))
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 2048) ?? Data()
        let format = try Format.resolve(url, prefix: prefix)

        switch format {
        case .pdf:
            return .init(url: url, content: .pdf(try readPDF(url)))

        case .replica:
            let data = try LegacyText.palm(
                Data(contentsOf: url, options: .mappedIfSafe),
                replica: true
            )
            return .init(url: url, content: .pdf(try readPDF(url, data: data)))

        case .text:
            return .init(
                url: url,
                content: .text(decode(try Data(contentsOf: url, options: .mappedIfSafe)))
            )

        case .palm:
            do {
                return .init(url: url, content: .pages(try Pages(url, format: .mupdf)))
            } catch {
                try Task.checkCancellation()
                let data = try LegacyText.palm(Data(contentsOf: url, options: .mappedIfSafe))
                return .init(url: url, content: .text(decode(data)))
            }

        case .tcr:
            let data = try LegacyText.tcr(Data(contentsOf: url, options: .mappedIfSafe))
            return .init(url: url, content: .text(decode(data)))

        case .book, .markdown, .html:
            return .init(url: url, content: .pages(try Pages(url, format: .mupdf)))

        case .chm:
            return .init(url: url, content: .chm(try CHMSource(url)))

        case .lit:
            let (temporary, root) = try LitConverter.convert(url)
            return .init(
                url: url,
                content: .pages(try Pages(root, format: .mupdf)),
                temporary: temporary
            )

        case .image, .comic, .mupdf, .djvu:
            return .init(url: url, content: .pages(try Pages(url, format: format)))

        case .postscript:
            return try openPostScript(url)

        default:
            throw ReadError("Unsupported document: \(url.lastPathComponent)")
        }
    }

    // Parse once on the loading task. A failed reload must not replace a readable document.
    private static func readPDF(_ url: URL, data: Data? = nil) throws -> PDFDocument {
        let document: PDFDocument?
        if let data {
            document = PDFDocument(data: data)
        } else {
            document = PDFDocument(url: url)
        }
        guard let document, document.isLocked || document.pageCount > 0 else {
            throw ReadError("Cannot read PDF: \(url.lastPathComponent)")
        }
        return document
    }

    static func decode(_ data: Data) -> String {
        if let string = String(data: data, encoding: .utf8) {
            return string
        }

        var converted: String?
        _ = NSString.stringEncoding(
            for: data,
            encodingOptions: [:],
            convertedString: &converted,
            usedLossyConversion: nil
        )
        return converted ?? String(decoding: data, as: UTF8.self)
    }

    private static func openPostScript(_ url: URL) throws -> ReadingDocument {
        let candidates = ["/opt/homebrew/bin/gs", "/usr/local/bin/gs", "/usr/bin/gs"]
        guard let ghostscript = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw ReadError("PostScript/PJL needs Ghostscript.")
        }

        let temporary = try TemporaryDirectory()
        let output = temporary.url.appendingPathComponent("document.pdf")
        let input: URL

        if url.lastPathComponent.lowercased().hasSuffix(".ps.gz") {
            input = temporary.url.appendingPathComponent("document.ps")

            guard FileManager.default.createFile(atPath: input.path, contents: nil) else {
                throw ReadError("Cannot create temporary PostScript")
            }
            let handle = try FileHandle(forWritingTo: input)
            defer { try? handle.close() }

            let gzip = Process()
            gzip.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
            gzip.arguments = ["-dc", url.path]
            gzip.standardOutput = handle

            try runLeafProcess(gzip)
            guard gzip.terminationStatus == 0 else {
                throw ReadError("Cannot decompress PostScript")
            }
        } else {
            input = url
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghostscript)
        process.arguments = [
            "-dSAFER",
            "-dBATCH",
            "-dNOPAUSE",
            "-sDEVICE=pdfwrite",
            "-sOutputFile=" + output.path,
            "-f",
            input.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try runLeafProcess(process)
        guard process.terminationStatus == 0 else {
            throw ReadError("Ghostscript could not convert this file.")
        }

        return .init(url: url, content: .pdf(try readPDF(output)), temporary: temporary)
    }
}
#endif
