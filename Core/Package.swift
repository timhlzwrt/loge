// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LogeCore",
    platforms: [.iOS("26.0"), .tvOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "LogeCore", targets: ["LogeCore"]),
    ],
    targets: [
        .target(name: "LogeCore"),
        .testTarget(
            name: "LogeCoreTests",
            dependencies: ["LogeCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
