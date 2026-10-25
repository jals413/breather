// swift-tools-version: 6.0
import PackageDescription

/// Paid Apple Developer Program features (Apple push to the iPhone) compile in only with
/// `BREATHER_PAID=1 scripts/build.sh`.
let paid = Context.environment["BREATHER_PAID"] == "1"
let paidSettings: [SwiftSetting] = paid ? [.define("BREATHER_PAID")] : []

let package = Package(
    name: "Breather",
    platforms: [.macOS("26.0"), .iOS("26.0"), .watchOS("26.0")],
    products: [
        .library(name: "BreatherKit", targets: ["BreatherKit"]),
    ],
    targets: [
        /// Shared by the Mac, iPhone and Watch apps: link protocol, Live Activity, feature flags.
        .target(
            name: "BreatherKit",
            path: "Sources/BreatherKit",
            swiftSettings: [.swiftLanguageMode(.v5)] + paidSettings
        ),
        .executableTarget(
            name: "Breather",
            dependencies: ["BreatherKit"],
            path: "Sources/Breather",
            swiftSettings: [.swiftLanguageMode(.v5)] + paidSettings,
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("Network"),
            ]
        ),
        .testTarget(
            name: "BreatherTests",
            dependencies: ["Breather", "BreatherKit"],
            path: "Tests/BreatherTests"
        ),
    ]
)
