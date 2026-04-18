// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "YCAIKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "YCAIKit",
            targets: ["YCAIKit"]
        ),
    ],
    targets: [
        .target(name: "YCAIKit"),
        .testTarget(
            name: "YCAIKitTests",
            dependencies: ["YCAIKit"]
        ),
    ]
)
