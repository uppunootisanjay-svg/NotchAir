// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchAir",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchAir", targets: ["NotchAir"])
    ],
    targets: [
        .executableTarget(
            name: "NotchAir",
            path: "Sources/NotchAir"
        )
    ]
)
