// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MutePls",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "mutepls", targets: ["MutePls"])
    ],
    targets: [
        .executableTarget(
            name: "MutePls",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("MediaPlayer")
            ]
        )
    ]
)
