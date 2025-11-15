// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "CapturePlay",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "CapturePlay",
            targets: ["CapturePlay"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "CapturePlay",
            path: "CapturePlay",
            sources: [
                "QCAppDelegate.swift",
                "QCSettingsManager.swift",
                "QCUsbWatcher.swift",
            ]
        )
    ]
)
