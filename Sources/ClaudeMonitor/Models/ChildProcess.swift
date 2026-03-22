import Foundation

struct ChildProcess: Identifiable {
    let pid: Int32
    let name: String

    var id: Int32 { pid }
}
