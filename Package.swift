// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Brexel",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Brexel", targets: ["Brexel"])
    ],
    targets: [
        .executableTarget(
            name: "Brexel",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Security")
            ]
        )
    ]
)
