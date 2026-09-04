// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NetworkAnalyzer",
    platforms: [.macOS(.v13)],
    targets: [
        .systemLibrary(
            name: "CDNSSD",
            path: "Sources/CDNSSD"
        ),
        .target(
            name: "NetworkAnalyzerCore",
            dependencies: ["CDNSSD"],
            path: "Sources/NetworkAnalyzerCore",
            resources: [
                .copy("Resources/oui.csv")
            ]
        ),
        .executableTarget(
            name: "NetworkAnalyzer",
            dependencies: ["NetworkAnalyzerCore"],
            path: "Sources/NetworkAnalyzer"
        ),
        .testTarget(
            name: "NetworkAnalyzerTests",
            dependencies: ["NetworkAnalyzerCore"],
            path: "Tests/NetworkAnalyzerTests"
        )
    ]
)
