// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clipy",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        // Declaring the executable product causes Xcode to generate a run scheme.
        .executable(name: "Clipy", targets: ["Clipy"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Clipy",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/Clipy",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist", "-Xlinker", "Resources/Info.plist",
                ]),
            ]
        )
    ]
)
