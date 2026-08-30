// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AO3Kit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AO3Kit", targets: ["AO3Kit"])
    ],
    targets: [
        .target(name: "AO3Kit"),
        .testTarget(name: "AO3KitTests", dependencies: ["AO3Kit"]),
    ]
)
