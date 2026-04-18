// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "YCAPIKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "YCAPIKit",
            targets: ["YCAPIKit"]
        ),
    ],
    targets: [
        .target(name: "YCAPIKit"),
        .testTarget(
            name: "YCAPIKitTests",
            dependencies: ["YCAPIKit"]
        ),
    ]
)
