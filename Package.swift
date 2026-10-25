// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Breather",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Breather",
            path: "Sources/Breather",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "BreatherTests",
            dependencies: ["Breather"],
            path: "Tests/BreatherTests"
        ),
    ]
)
