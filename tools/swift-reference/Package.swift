// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "refgen",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../../../SPM/MarqueeDataKit")],
    targets: [.executableTarget(name: "refgen", dependencies: [.product(name: "MarqueeDataKit", package: "MarqueeDataKit")])]
)
