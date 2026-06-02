// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Momentum",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Momentum", targets: ["Momentum"]),
    ],
    targets: [
        .target(name: "MomentumKit"),
        .executableTarget(
            name: "Momentum",
            dependencies: ["MomentumKit"]
        ),
        .testTarget(
            name: "MomentumKitTests",
            dependencies: ["MomentumKit"]
        ),
    ]
)
