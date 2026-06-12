// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GuitarTuner",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "GuitarTuner",
            path: "Sources/GuitarTuner"
        )
    ]
)
