// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AK35iClockSync",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ak35i", targets: ["AK35iClockSync"])
    ],
    targets: [
        .executableTarget(name: "AK35iClockSync"),
        .testTarget(name: "AK35iClockSyncTests", dependencies: ["AK35iClockSync"])
    ]
)
