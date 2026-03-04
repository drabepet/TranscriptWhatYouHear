// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TranscriptWhatYouHear",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/ggerganov/whisper.spm", branch: "master"),
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0"),
    ],
    targets: [
        .target(
            name: "TranscriptLib",
            dependencies: [
                .product(name: "whisper", package: "whisper.spm"),
                "HotKey",
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Carbon"),
            ]
        ),
        .executableTarget(
            name: "TranscriptWhatYouHear",
            dependencies: ["TranscriptLib"]
        ),
        .executableTarget(
            name: "TestRunner",
            dependencies: ["TranscriptLib"],
            path: "Tests/TestRunner"
        ),
    ]
)
