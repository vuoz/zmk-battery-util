// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ZMKBatteryUtil",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ZMKBatteryUtil", targets: ["ZMKBatteryUtil"])

    ],
    targets: [
        .executableTarget(
            name: "ZMKBatteryUtil", path: "Sources/ZMKBatteryUtil",
            linkerSettings: [
                .linkedFramework("AppKit"), .linkedFramework("CoreBluetooth"),
            ])
    ],

)
