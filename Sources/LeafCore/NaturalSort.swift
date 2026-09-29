import Foundation
public enum NaturalSort {
    public static func less(_ a: String, _ b: String) -> Bool { a.compare(b, options: [.numeric, .caseInsensitive]) == .orderedAscending }
}
