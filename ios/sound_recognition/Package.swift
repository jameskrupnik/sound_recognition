// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "sound_recognition",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "sound-recognition", targets: ["sound_recognition"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "sound_recognition",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // Declares nothing collected and no tracking, which is the
                // truth: audio is classified in memory and never stored or
                // sent. Shipped so the app's privacy report says so.
                .process("PrivacyInfo.xcprivacy"),
            ],
            linkerSettings: [
                .linkedFramework("SoundAnalysis"),
                .linkedFramework("AVFoundation"),
            ]
        )
    ]
)
