// swift-tools-version:5.9
import Foundation
import PackageDescription

// Embedding Info.plist in the executable lets a bare `swift run AirBuds` use
// Bluetooth too; without the usage string macOS kills the process on first access.
let infoPlist = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Resources/Info.plist").path

let package = Package(
    name: "AirBuds",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AirBuds", targets: ["AirBuds"]),
    ],
    dependencies: [
        // Auto-update. Ships as a prebuilt framework; build-app.sh embeds it in the app.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Earbud protocol (Jieli RCSP): handshake, framing, payload codecs, capabilities. No UI, no Bluetooth.
        .target(name: "AirBudsKit"),
        // The menu bar app: BLE transport, device state and SwiftUI panel.
        .executableTarget(
            name: "AirBuds",
            dependencies: ["AirBudsKit", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("ServiceManagement"),
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", infoPlist]),
                // Sparkle.framework sits in Contents/Frameworks inside the app (see build-app.sh).
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        // `swift run AirBudsKitChecks`: protocol self-checks (XCTest isn't available without Xcode).
        .executableTarget(name: "AirBudsKitChecks", dependencies: ["AirBudsKit"]),
    ]
)
