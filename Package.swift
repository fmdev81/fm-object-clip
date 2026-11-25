// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "fm-object-clip",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FMClipCore", targets: ["FMClipCore"]),
        .executable(name: "fm-object-clip-cli", targets: ["fm-object-clip-cli"]),
        .executable(name: "FMObjectClip", targets: ["FMObjectClip"]),
    ],
    targets: [
        .target(name: "FMClipCore"),
        .executableTarget(name: "fm-object-clip-cli", dependencies: ["FMClipCore"]),
        .executableTarget(name: "FMObjectClip", dependencies: ["FMClipCore"]),
        // The tests read Fixtures/ by path (#filePath), so it is not a resource.
        .testTarget(name: "FMClipCoreTests", dependencies: ["FMClipCore", "FMObjectClip"], exclude: ["Fixtures"]),
    ]
)
