// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lumber",
    // Liquid Glass（glassEffect / GlassEffectContainer）仅 macOS 26+ 提供
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Lumber",
            path: "Sources/Lumber"
        ),
        .testTarget(
            name: "LumberTests",
            dependencies: ["Lumber"],
            path: "Tests/LumberTests"
        ),
    ]
)
