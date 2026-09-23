// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AlertCalendar",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "AlertCalendar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/AlertCalendar",
            resources: [
                .process("Resources/Images"),
            ]
        ),
        .testTarget(
            name: "AlertCalendarTests",
            dependencies: ["AlertCalendar"],
            path: "Tests/AlertCalendarTests"
        ),
    ]
)
