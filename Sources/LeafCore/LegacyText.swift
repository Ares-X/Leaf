import Foundation

/// Palm record layout follows SumatraPDF's BSD-licensed PalmDbReader.cpp.
/// Print Replica follows its issue-1315 fixture. See THIRD_PARTY.md for pinned sources.
public enum LegacyText {
    public static func tcr(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.starts(with: Array("!!8-Bit!!".utf8)) else { throw ReadError("Invalid TCR header") }
        var p = 9, dictionary: [ArraySlice<UInt8>] = []
        for _ in 0..<256 {
            guard p < bytes.count else { throw ReadError("Truncated TCR dictionary") }
            let n = Int(bytes[p]); p += 1
            guard n <= bytes.count - p else { throw ReadError("Truncated TCR entry") }
            dictionary.append(bytes[p..<p+n]); p += n
        }
        var result = Data()
        for index in bytes[p...] { result.append(contentsOf: dictionary[Int(index)]) }
        return result
    }
    public static func palm(_ data: Data, replica: Bool = false) throws -> Data {
        let b = [UInt8](data)
        func number(_ p: Int, _ count: Int) throws -> Int {
            guard p >= 0, p + count <= b.count else { throw ReadError("Truncated Palm document") }
            return b[p..<p+count].reduce(0) { ($0 << 8) | Int($1) }
        }
        let count = try number(76, 2)
        guard count >= 2, 78 + count * 8 <= b.count else { throw ReadError("Invalid Palm record table") }
        var offsets = try (0..<count).map { try number(78 + $0 * 8, 4) }
        offsets.append(b.count)
        guard offsets[0] >= 78 + count * 8, zip(offsets, offsets.dropFirst()).allSatisfy({ $0 <= $1 }) else {
            throw ReadError("Invalid Palm record offsets")
        }
        guard offsets[1] - offsets[0] >= 16 else { throw ReadError("Truncated Palm header") }
        let start = offsets[0], compression = try number(start, 2), length = try number(start + 4, 4)
        let textCount = try number(start + 8, 2)
        guard textCount > 0, textCount < count, [1, 2].contains(compression) else {
            throw ReadError("Unsupported Palm compression or empty document")
        }
        if replica, try number(start + 12, 2) != 0 { throw ReadError("Encrypted Kindle document") }
        var result = [UInt8]()
        for i in 1...textCount {
            let record = Array(b[offsets[i]..<offsets[i+1]])
            result += try compression == 1 ? record : unpackPalm(record)
        }
        guard result.count >= length else { throw ReadError("Truncated Palm text") }
        result = Array(result.prefix(length))
        if !replica { return Data(result) }
        guard result.starts(with: Array("%MOP".utf8)) else { throw ReadError("Not a Kindle Print Replica document") }
        // The PDF is a section inside %MOP, not HTML. Preserve its original bytes.
        let payload = Data(result)
        guard let start = payload.range(of: Data("%PDF-".utf8))?.lowerBound,
              let end = payload.range(of: Data("%%EOF".utf8), options: .backwards)?.upperBound,
              end > start else { throw ReadError("Print Replica contains no readable PDF") }
        return payload.subdata(in: start..<end)
    }
    static func unpackPalm(_ b: [UInt8]) throws -> [UInt8] {
        var out: [UInt8] = [], p = 0
        while p < b.count {
            let c = Int(b[p]); p += 1
            switch c {
            case 1...8:
                guard c <= b.count - p else { throw ReadError("Truncated Palm literal") }
                out += b[p..<p+c]; p += c
            case 0, 9...127: out.append(UInt8(c))
            case 128...191:
                guard p < b.count else { throw ReadError("Truncated Palm back-reference") }
                let pair = (c << 8) | Int(b[p]); p += 1
                let distance = (pair & 0x3fff) >> 3, n = (pair & 7) + 3
                guard distance > 0, distance <= out.count else { throw ReadError("Invalid Palm back-reference") }
                for _ in 0..<n { out.append(out[out.count - distance]) }
            default: out += [32, UInt8(c ^ 128)]
            }
        }
        return out
    }
}
