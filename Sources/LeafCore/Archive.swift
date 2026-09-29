import Foundation
import CArchive

/// libarchive owns decompression. No extraction, filesystem writes or private ZIP parser.
public struct Archive: Sendable {
    public struct Entry: Sendable, Codable {
        public let name: String
        public let size: Int64
        public init(name: String, size: Int64) { self.name = name; self.size = size }
    }
    public let url: URL
    public let entries: [Entry]

    public init(_ url: URL) throws {
        self.url = url
        let handle = try Self.open(url)
        defer { archive_read_free(handle) }
        var entry: OpaquePointer?, result: [Entry] = []
        while try Self.next(handle, &entry), let entry {
            try Task.checkCancellation()
            guard archive_entry_filetype(entry) == 0o100000,
                  let name = archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry) else { continue }
            result.append(Entry(name: String(cString: name), size: archive_entry_size(entry)))
        }
        entries = result
    }
    public static func isSafeEntryName(_ name:String)->Bool{
        let normalized=name.replacingOccurrences(of:"\\",with:"/")
        guard !normalized.hasPrefix("/"),!normalized.split(separator:"/").contains("..") else{return false}
        return true
    }
    public var images: [String] {
        entries.map(\.name).filter {
            Self.isSafeEntryName($0) &&
            !$0.split(separator: "/").contains(where: { $0.hasPrefix(".") || $0 == "__MACOSX" }) &&
            (Format.detect($0) == .image || ["svg", "jxr", "hdp", "wdp"].contains(($0 as NSString).pathExtension.lowercased()))
        }.sorted { $0.compare($1, options: [.numeric, .caseInsensitive]) == .orderedAscending }
    }
    public func data(_ name: String) throws -> Data {
        guard Self.isSafeEntryName(name) else{throw ReadError("Invalid archive entry path")}
        let handle = try Self.open(url)
        defer { archive_read_free(handle) }
        var entry: OpaquePointer?
        while try Self.next(handle, &entry), let entry {
            try Task.checkCancellation()
            guard let path = archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry),
                  String(cString: path) == name else { archive_read_data_skip(handle); continue }
            let expected=archive_entry_size(entry);guard expected >= 0, expected <= 512 * 1024 * 1024 else { throw ReadError("Archive entry is too large") }
            var result = Data();result.reserveCapacity(Int(expected));var buffer=[UInt8](repeating:0,count:64*1024)
            while true {
                try Task.checkCancellation()
                let n = archive_read_data(handle, &buffer, buffer.count)
                if n == 0 { return result }
                guard n > 0 else { throw Self.error(handle) }
                guard result.count <= 512 * 1024 * 1024 - n else { throw ReadError("Archive entry is too large") }
                result.append(contentsOf: buffer.prefix(n))
            }
        }
        throw ReadError("Archive entry not found: \(name)")
    }
    private static func open(_ url: URL) throws -> OpaquePointer {
        guard let a = archive_read_new() else { throw ReadError("Cannot create archive reader") }
        archive_read_support_filter_all(a)
        archive_read_support_format_all(a)
        guard archive_read_open_filename(a, url.path, 64 * 1024) == ARCHIVE_OK else {
            let e = error(a); archive_read_free(a); throw e
        }
        return a
    }
    private static func next(_ a: OpaquePointer, _ e: inout OpaquePointer?) throws -> Bool {
        let status = archive_read_next_header(a, &e)
        if status == ARCHIVE_EOF { return false }
        guard status >= ARCHIVE_WARN else { throw error(a) }
        return true
    }
    private static func error(_ a: OpaquePointer) -> ReadError {
        ReadError(archive_error_string(a).map(String.init(cString:)) ?? "Cannot read archive")
    }
}
