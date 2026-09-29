#if os(macOS)
import Foundation
enum Progress {
    static func key(_ url:URL)->String{"leaf."+String(url.path.hashValue)}
    static func get(_ url:URL)->Int{UserDefaults.standard.integer(forKey:key(url))}
    static func set(_ n:Int,_ url:URL){UserDefaults.standard.set(n,forKey:key(url))}
}
#endif
