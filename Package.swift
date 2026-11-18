// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ResonanceStudio",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ResonanceStudio", path: "Sources/ResonanceStudio")
    ]
)
