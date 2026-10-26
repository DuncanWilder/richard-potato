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
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
