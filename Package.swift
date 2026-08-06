// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AlertCalendar",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .executableTarget(
            name: "AlertCalendar",
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
