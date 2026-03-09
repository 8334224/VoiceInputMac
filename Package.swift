// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoiceInputMac",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "VoiceInputMac", targets: ["VoiceInputMac"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "VoiceInputMac",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ]
        ),
        .testTarget(
            name: "VoiceInputMacTests",
            dependencies: ["VoiceInputMac"]
        )
    ]
)
