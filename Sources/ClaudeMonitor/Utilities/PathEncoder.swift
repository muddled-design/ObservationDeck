import Foundation

enum PathEncoder {
    static func encode(_ absolutePath: String) -> String {
        absolutePath.replacingOccurrences(of: "/", with: "-")
    }
}
