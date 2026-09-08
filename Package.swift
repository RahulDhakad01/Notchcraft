// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NotchCraft",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "NotchCraft",
            exclude: [
                "Resources/NotchCraft-Info.plist",
                "Resources/AppIcon.iconset"
            ],
            resources: [
                .process("Resources/AppIcon.png"),
                .copy("Resources/AppIcon.icns"),
                .process("Resources/navbar.png")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/NotchCraft/Resources/NotchCraft-Info.plist"
                ])
            ]
        ),
    ]
)
