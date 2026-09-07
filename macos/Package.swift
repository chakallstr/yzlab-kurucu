// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "YzlabKurucu",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "YzlabKurucu", path: "Sources/YzlabKurucu")
    ]
)
