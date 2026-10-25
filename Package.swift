// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyflowStatus",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    ],
    targets: [
        .target(
            name: "USBTransport",
            path: "USBTransport",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "KeyflowStatus",
            dependencies: [.product(name: "Yams", package: "Yams"), "USBTransport"],
            path: "Sources"
        ),
    ]
)
