// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NXBiblioteca",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "NXBiblioteca", path: "Sources/NXBiblioteca")
    ]
)
