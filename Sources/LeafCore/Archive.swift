import Foundation
import CArchive

/// Thin libarchive reader. Metadata is indexed once; sequential entry reads reuse one cursor.
public final class Archive: @unchecked Sendable {
    public struct Entry: Sendable, Codable {
        public let name: String
        public let size: Int64

        public init(name: String, size: Int64) {
            self.name = name
            self.size = size
        }
    }

    public let url: URL
    public let entries: [Entry]

    private let positions: [String: Int]
    private let lock = NSLock()
    private var cursor: OpaquePointer?
    private var cursorIndex = -1

    public init(_ url: URL) throws {
        self.url = url
        let handle = try Self.open(url)
        defer { archive_read_free(handle) }

        var entry: OpaquePointer?
        var result: [Entry] = []
        while try Self.next(handle, &entry), let entry {
            try Task.checkCancellation()
            guard archive_entry_filetype(entry) == 0o100000,
                  let name = archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry)
            else { continue }
            result.append(.init(name: String(cString: name), size: archive_entry_size(entry)))
        }

        entries = result
        positions = Dictionary(
            result.enumerated().map { ($0.element.name, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    deinit { resetCursor() }

    public func contains(_ name: String) -> Bool {
        entries.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public var images: [String] {
        positions.keys.filter {
            !$0.split(separator: "/").contains(where: { $0.hasPrefix(".") || $0 == "__MACOSX" })
                && (Format.detect($0) == .image
                    || ["svg", "jxr", "hdp", "wdp"].contains(($0 as NSString).pathExtension.lowercased()))
        }.sorted { $0.compare($1, options: [.numeric, .caseInsensitive]) == .orderedAscending }
    }

    public func data(_ name: String) throws -> Data {
        guard let target = positions[name] else {
            throw ReadError("Archive entry not found: \(name)")
        }

        lock.lock()
        defer { lock.unlock() }

        do {
            if cursor == nil || target <= cursorIndex {
                resetCursor()
                cursor = try Self.open(url)
            }
            guard let cursor else { throw ReadError("Cannot read archive") }

            var entry: OpaquePointer?
            while try Self.next(cursor, &entry), let entry {
                try Task.checkCancellation()
                guard archive_entry_filetype(entry) == 0o100000,
                      archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry) != nil
                else {
                    archive_read_data_skip(cursor)
                    continue
                }

                cursorIndex += 1
                guard cursorIndex == target else {
                    archive_read_data_skip(cursor)
                    continue
                }

                let maxBytes = Int(LEAF_MAX_DECODED_BYTES)
                let expected = archive_entry_size(entry)
                guard expected >= 0 else {
                    throw ReadError("Archive entry has an invalid size")
                }

                var result = Data()
                result.reserveCapacity(Int(min(expected, 64 * 1024)))
                var buffer = [UInt8](repeating: 0, count: 64 * 1024)

                while true {
                    try Task.checkCancellation()
                    let n = archive_read_data(cursor, &buffer, buffer.count)
                    if n == 0 { return result }
                    guard n > 0 else { throw Self.error(cursor) }
                    guard result.count <= maxBytes - n else {
                        throw ReadError("Archive entry is too large")
                    }
                    result.append(contentsOf: buffer.prefix(n))
                }
            }

            throw ReadError("Archive entry not found: \(name)")
        } catch {
            resetCursor()
            throw error
        }
    }

    private func resetCursor() {
        if let cursor { archive_read_free(cursor) }
        cursor = nil
        cursorIndex = -1
    }

    private static func open(_ url: URL) throws -> OpaquePointer {
        guard let archive = archive_read_new() else {
            throw ReadError("Cannot create archive reader")
        }
        archive_read_support_filter_all(archive)
        archive_read_support_format_all(archive)
        guard archive_read_open_filename(archive, url.path, 64 * 1024) == ARCHIVE_OK else {
            let error = error(archive)
            archive_read_free(archive)
            throw error
        }
        return archive
    }

    private static func next(_ archive: OpaquePointer, _ entry: inout OpaquePointer?) throws -> Bool {
        let status = archive_read_next_header(archive, &entry)
        if status == ARCHIVE_EOF { return false }
        guard status == ARCHIVE_OK || status == ARCHIVE_WARN else {
            throw error(archive)
        }
        return true
    }

    private static func error(_ archive: OpaquePointer) -> ReadError {
        ReadError(
            archive_error_string(archive).map(String.init(cString:))
                ?? "Cannot read archive"
        )
    }
}
