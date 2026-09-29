import Foundation
public enum FormatDetector {
    static let map: [String: DocumentKind] = [
        "pdf":.pdf,"epub":.epub,"txt":.text,"log":.text,"md":.markdown,"markdown":.markdown,
        "cbz":.comicZip,"zip":.comicZip,"jpg":.image,"jpeg":.image,"png":.image,"gif":.image,
        "webp":.image,"heic":.image,"tiff":.image,"bmp":.image,"mobi":.mobi,"azw":.azw3,
        "azw3":.azw3,"fb2":.fb2,"djvu":.djvu,"djv":.djvu,"cbr":.comicRar
    ]
    public static func detect(fileName: String) -> DocumentKind { map[URL(fileURLWithPath:fileName).pathExtension.lowercased()] ?? .unsupported }
    public static func detect(url: URL) -> DocumentKind { detect(fileName:url.lastPathComponent) }
    public static func detect(prefix: Data) -> DocumentKind { prefix.starts(with: Data("%PDF".utf8)) ? .pdf : .unsupported }
}
