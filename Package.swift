// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MissionTokenLive",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MissionTokenLive", targets: ["MissionTokenLive"])
    ],
    targets: [
        // En-tête C exposé par la crate Rust `mission-token-ffi`.
        .systemLibrary(name: "CMissionTokenFFI", path: "Sources/CMissionTokenFFI"),
        .executableTarget(
            name: "MissionTokenLive",
            dependencies: ["CMissionTokenFFI"],
            path: "MissionTokenLive",
            swiftSettings: [.unsafeFlags(["-swift-version", "5"])],
            linkerSettings: [
                .unsafeFlags(["-L", "Sources/CMissionTokenFFI/lib", "-lmission_token_ffi"])
            ]
        ),
        .testTarget(
            name: "MissionTokenLiveTests",
            dependencies: ["MissionTokenLive"],
            path: "Tests/MissionTokenLiveTests",
            swiftSettings: [.unsafeFlags(["-swift-version", "5"])]
        )
    ]
)
