// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FMF",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "FMF", path: "Sources/FMF")
    ]
)
