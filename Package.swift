// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "flare-client-swift",
    platforms: [.macOS(.v12), .iOS(.v15), .tvOS(.v15)],
    products: [
        .library(name: "Flare", targets: ["Flare"]),
        .library(name: "FlareCrashReporter", targets: ["FlareCrashReporter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/microsoft/plcrashreporter.git", from: "1.12.2"),
    ],
    targets: [
        .target(name: "Flare"),
        .target(
            name: "FlareCrashReporter",
            dependencies: [
                "Flare",
                .product(name: "CrashReporter", package: "plcrashreporter", condition: .when(platforms: [.macOS, .iOS, .tvOS])),
            ]
        ),
        .testTarget(name: "FlareTests", dependencies: ["Flare"]),
        .testTarget(name: "FlareCrashReporterTests", dependencies: ["FlareCrashReporter"]),
    ]
)
