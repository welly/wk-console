// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WKConsole",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "WKConsole", path: "Sources/WKConsole"),
    ],
    swiftLanguageModes: [.v5]
)
