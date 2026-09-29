import Foundation
public enum DocumentKind: String, Sendable {
    case pdf, epub, text, markdown, comicZip, image, mobi, azw3, fb2, djvu, comicRar, unsupported
    public var displayName: String { rawValue }
}
