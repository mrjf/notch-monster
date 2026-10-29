// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NotchMonster",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "NotchMonster", targets: ["NotchMonster"])],
    targets: [
        .executableTarget(
            name: "NotchMonster",
            path: "Sources/NotchMonster",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(name: "NotchMonsterTests", dependencies: ["NotchMonster"])
    ]
)
