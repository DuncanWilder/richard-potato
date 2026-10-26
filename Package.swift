// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RichardPotato",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "RichardPotato", targets: ["RichardPotato"])],
    targets: [
        .executableTarget(
            name: "RichardPotato",
            path: "RichardPotato",
            exclude: ["Assets.xcassets", "RichardPotato.entitlements"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-Osize"], .when(configuration: .release)),
            ],
            // Keep Swift's link driver on the same Release optimization setting.
            linkerSettings: [
                .unsafeFlags(["-Osize"], .when(configuration: .release))
            ]
        ),
        .testTarget(
            name: "RichardPotatoTests",
            dependencies: ["RichardPotato"],
            path: "RichardPotatoTests"
        ),
    ]
)
