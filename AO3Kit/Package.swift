// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AO3Kit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AO3Kit", targets: ["AO3Kit"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        .target(name: "AO3Kit", dependencies: ["ZIPFoundation"]),
        .testTarget(name: "AO3KitTests", dependencies: ["AO3Kit"]),
    ]
)
