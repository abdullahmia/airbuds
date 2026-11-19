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
    targets: [
        // Earbud protocol (Jieli RCSP): handshake, framing, payload codecs, capabilities. No UI, no Bluetooth.
        .target(name: "AirBudsKit"),
        // The menu bar app: BLE transport, device state and SwiftUI panel.
        .executableTarget(
            name: "AirBuds",
            dependencies: ["AirBudsKit"],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("ServiceManagement"),
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", infoPlist]),
            ]
        ),
        // `swift run AirBudsKitChecks`: protocol self-checks (XCTest isn't available without Xcode).
        .executableTarget(name: "AirBudsKitChecks", dependencies: ["AirBudsKit"]),
    ]
)
