// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CLibProc",
            path: "Sources/CLibProc",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "ClaudeMonitor",
            dependencies: ["CLibProc"],
            path: "Sources/ClaudeMonitor"
        ),
    ]
)
