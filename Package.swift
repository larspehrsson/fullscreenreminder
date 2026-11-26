// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FullscreenReminder",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // In-app updates (https://sparkle-project.org). build.sh copies Sparkle.framework into
        // Contents/Frameworks; the rpath below lets the executable find it there.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "FullscreenReminder",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
    ]
)
