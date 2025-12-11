// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "Statsig",
    platforms: [.watchOS(.v7), .iOS(.v10), .tvOS(.v10), .macOS(.v10_13)],
    products: [
        .library(
            name: "Statsig",
            targets: ["Statsig"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/AliSoftware/OHHTTPStubs.git", .upToNextMajor(from: "9.1.0")),
        .package(url: "https://github.com/Quick/Nimble.git", .upToNextMajor(from: "10.0.0")),
        .package(url: "https://github.com/Quick/Quick.git", .upToNextMajor(from: "5.0.0")),
        .package(url: "https://github.com/erikdoe/ocmock", .branch("master")),
        .package(
            name: "Gzip", url: "https://github.com/1024jp/GzipSwift", .upToNextMajor(from: "5.1.1")),
    ],
    targets: [
        .target(
            name: "Statsig",
            dependencies: [],
            path: "Sources/Statsig"
        ),
        .testTarget(
            name: "StatsigTests",
            dependencies: [
                "Statsig", "Quick", "Nimble", "OHHTTPStubs", "Gzip",
                .product(name: "OHHTTPStubsSwift", package: "OHHTTPStubs"),
            ]
        ),
        .testTarget(
            name: "StatsigObjcTests",
            dependencies: [.target(name: "Statsig"), .product(name: "OCMock", package: "ocmock")],
            resources: [.process("Resources")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
