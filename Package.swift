// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iPhoneGamepad",
    platforms: [.macOS(.v15), .iOS(.v17)],
    products: [.executable(name: "gamepad-host", targets: ["GamepadHost"])],
    targets: [
        .target(name: "GamepadCore"),
        .target(name: "MacSupport", dependencies: ["GamepadCore"]),
        .executableTarget(name: "GamepadHost", dependencies: ["GamepadCore", "MacSupport"]),
        .testTarget(name: "GamepadCoreTests", dependencies: ["GamepadCore"]),
        .testTarget(name: "MacSupportTests", dependencies: ["GamepadCore", "MacSupport"])
    ],
    swiftLanguageModes: [.v5]
)
