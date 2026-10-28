// swift-tools-version: 5.9
// Companion SwiftPM manifest. On Mac, prefer opening `ContextDay.xcodeproj`
// (Bundle ID `app.contextday`, AppIcon, entitlements). This package is for
// source browsing / future CLI tests — it is not a full .app substitute.
import PackageDescription

let package = Package(
    name: "ContextDay",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "ContextDay", targets: ["ContextDay"]),
    ],
    targets: [
        .executableTarget(
            name: "ContextDay",
            path: ".",
            exclude: [
                "docs",
                "scripts",
                "ContextDay.xcodeproj",
                "README.md",
                "Info.plist",
                "ContextDay.entitlements",
                "Resources/AppIcon",
                ".gitignore",
            ],
            sources: [
                "App",
                "Features",
            ],
            resources: [
                .copy("Resources/DesktopOrb"),
                .process("Resources/Assets.xcassets"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
