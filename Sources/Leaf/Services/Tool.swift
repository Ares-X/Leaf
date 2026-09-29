#if os(macOS)
import Foundation
enum Tool {
    static func find(_ names:String...)->String? {
        let dirs=["/opt/homebrew/bin","/usr/local/bin","/usr/bin"]
        for n in names { for d in dirs { let p="\(d)/\(n)"; if FileManager.default.isExecutableFile(atPath:p){return p} } }
        return nil
    }
    static func run(_ exe:String,_ args:[String])throws {
        let p=Process();p.executableURL=URL(fileURLWithPath:exe);p.arguments=args;try p.run();p.waitUntilExit()
        if p.terminationStatus != 0 { throw CocoaError(.fileReadUnknown) }
    }
}
#endif
