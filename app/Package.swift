// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WisprFlow",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WisprFlow",
            path: "Sources/WisprFlow"
        )
    ]
)
