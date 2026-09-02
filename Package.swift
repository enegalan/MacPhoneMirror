// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacPhoneMirror",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "MacPhoneMirror",
            targets: ["MacPhoneMirror"]
        ),
        .library(
            name: "MacPhoneMirrorCore",
            targets: ["MacPhoneMirrorCore"]
        ),
        .library(
            name: "MacPhoneMirrorUI",
            targets: ["MacPhoneMirrorUI"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CAirPlayFairPlay",
            path: "Sources/CAirPlayFairPlay",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("playfair"),
            ]
        ),
        .target(
            name: "MacPhoneMirrorCore",
            dependencies: ["CAirPlayFairPlay"],
            path: "Sources/MacPhoneMirrorCore"
        ),
        .target(
            name: "MacPhoneMirrorUI",
            dependencies: ["MacPhoneMirrorCore"],
            path: "Sources/MacPhoneMirrorUI"
        ),
        .executableTarget(
            name: "MacPhoneMirror",
            dependencies: [
                "MacPhoneMirrorCore",
                "MacPhoneMirrorUI",
            ],
            path: "Sources/MacPhoneMirror",
            exclude: ["Info.plist"],
            resources: [
                .process("Assets.xcassets"),
                .process("Resources"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/MacPhoneMirror/Info.plist",
                ], .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "MacPhoneMirrorTests",
            dependencies: [
                "MacPhoneMirrorCore",
                "MacPhoneMirrorUI",
            ],
            path: "Tests/MacPhoneMirrorTests"
        ),
    ]
)
