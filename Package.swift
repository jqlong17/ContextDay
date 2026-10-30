// swift-tools-version: 5.9
// Companion SwiftPM manifest. On Mac, prefer opening `ContextDay.xcodeproj`
// (Bundle ID `app.contextday`, AppIcon, entitlements). This package mirrors deps.
import PackageDescription

let package = Package(
    name: "ContextDay",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "ContextDay", targets: ["ContextDay"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/microsoft/onnxruntime-swift-package-manager",
            from: "1.20.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "ContextDay",
            dependencies: [
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
            ],
            path: ".",
            exclude: [
                "docs",
                "Scripts",
                "scripts",
                "Tests",
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
                .copy("Resources/Models"),
                .process("Resources/Assets.xcassets"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedFramework("CoreML"),
                .linkedFramework("ServiceManagement"),
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
