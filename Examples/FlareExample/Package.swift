// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlareExample",
    platforms: [.macOS(.v12)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(
            name: "FlareExample",
            dependencies: [
                .product(name: "Flare", package: "flare-client-swift"),
                .product(name: "FlareCrashReporter", package: "flare-client-swift"),
            ]
        ),
    ]
)
