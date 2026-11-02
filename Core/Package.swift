// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MediaCore",
    platforms: [.iOS("26.0"), .tvOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "MediaCore", targets: ["MediaCore"]),
    ],
    targets: [
        .target(name: "MediaCore"),
        .testTarget(
            name: "MediaCoreTests",
            dependencies: ["MediaCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
