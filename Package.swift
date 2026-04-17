// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pastie",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Pastie"),
    ]
)
