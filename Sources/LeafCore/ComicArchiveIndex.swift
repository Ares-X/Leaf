import Foundation
public struct ComicArchiveIndex {
    public let pagePaths: [String]
    public init(url: URL) throws {
        let exts = Set(["jpg","jpeg","png","gif","webp","bmp","tif","tiff"])
        pagePaths = try ZipArchive(url:url).entries.filter { exts.contains(URL(fileURLWithPath:$0.path).pathExtension.lowercased()) }.map(\.path).sorted(by: NaturalSort.less)
    }
}
