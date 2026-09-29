import Foundation

public enum Format: String, Sendable {
    case pdf, book, text, markdown, comic, image, mupdf, djvu, chm, postscript, palm, tcr, replica, html, unknown

    // Single source for dispatch, Finder associations and the coverage report.
    public static let groups: [(Format, String)] = [
        (.pdf, "pdf ai"), (.book, "epub mobi azw azw3 prc fb2 fb2z fbz zfb2 fb2.zip"),
        (.replica, "azw4"), (.palm, "pdb"), (.tcr, "tcr"),
        (.text, "txt log nfo text"), (.markdown, "md markdown"), (.html, "html htm xhtml"),
        (.comic, "cbz cbr cbt cb7 zip rar tar 7z ora"),
        (.djvu, "djvu djv"), (.chm, "chm"), (.mupdf, "xps oxps xod dwfx svg jxr hdp wdp"),
        (.postscript, "ps eps pjl"),
        (.image, "png jpg jpeg jfif gif tif tiff bmp dib tga webp jp2 j2k jpx jpf jpm j2c avif jxl heic heif")
    ]
    public static var extensions: [String] { groups.flatMap { $0.1.split(separator: " ").map(String.init) } }
    public static func detect(_ name: String) -> Format {
        let name = name.lowercased()
        // A compound extension must beat the generic ZIP suffix.
        if name.hasSuffix(".fb2.zip") { return .book }
        return groups.first { _, suffixes in
            suffixes.split(separator: " ").contains { name.hasSuffix("." + $0) }
        }?.0 ?? .unknown
    }
}

public struct ReadError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
