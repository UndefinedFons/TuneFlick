// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TuneFlick",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TuneFlick", targets: ["TuneFlick"])
    ],
    targets: [
        .executableTarget(
            name: "TuneFlick",
            path: "Sources/TuneFlick"
        )
    ]
)
