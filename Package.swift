// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "cc-env-switcher",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "CCEnvSwitcherCore",
            targets: ["CCEnvSwitcherCore"]
        ),
        .executable(
            name: "cc-env-switcher",
            targets: ["CCEnvSwitcherExecutable"]
        )
    ],
    targets: [
        .target(
            name: "CCEnvSwitcherCore",
            path: "Sources/CCEnvSwitcherCore"
        ),
        .target(
            name: "CCEnvSwitcherApp",
            dependencies: ["CCEnvSwitcherCore"],
            path: "Sources/CCEnvSwitcherApp"
        ),
        .executableTarget(
            name: "CCEnvSwitcherExecutable",
            dependencies: ["CCEnvSwitcherApp"],
            path: "Sources/CCEnvSwitcherExecutable"
        ),
        .testTarget(
            name: "CCEnvSwitcherCoreTests",
            dependencies: ["CCEnvSwitcherCore"],
            path: "Tests/CCEnvSwitcherCoreTests"
        ),
        .testTarget(
            name: "CCEnvSwitcherAppTests",
            dependencies: ["CCEnvSwitcherApp", "CCEnvSwitcherCore"],
            path: "Tests/CCEnvSwitcherAppTests"
        )
    ]
)
