// swift-tools-version: 6.2
//
// test-shows — the generator of the PUBLIC generic test shows (plan D-r2-25, FIX-01) and their
// style book (D-r2-28, FIX-03).
//
// It builds every show through the kit's real write paths — the migrator, MediaService
// import, the store's playlist / directive / surface / session calls, `upsertVariant` for
// renditions — and publishes with the kit's writer, into a checkout of
// `Mountain-View-Staging/marquee-test-shows`. The media is generated here (CoreGraphics,
// ImageIO, AVFoundation, libwebp through webp-swift); nothing is read from a real show.
// See README.md.
//
import PackageDescription

let package = Package(
    name: "test-shows",
    platforms: [.macOS(.v15)],
    dependencies: [
        // The kit by path, like tools/swift-reference: the shows are written by the code
        // Studio for Mac runs, at whatever the sibling checkout is.
        .package(path: "../../../SPM/MarqueeDataKit"),
        // The Swift Loader and filesForLanes, for `verify`.
        .package(path: "../../../SPM/MarqueeSurfaceEngine"),
        // BRAND26 imports its style book through the kit's own `BrandImport` (FIX-03), and the
        // checks read it back through `StyleBook` / `BrandDelivery` and measure contrast with
        // `Contrast` — the code Studio for Mac and the Surface run.
        .package(path: "../../../SPM/MarqueeSessionBoard"),
        // Studio's WebP encoder (libwebp, BSD-3). ImageIO decodes WebP but ships no encoder.
        .package(url: "https://github.com/xocialize/webp-swift", from: "0.1.0"),
        // For the pre-v25 artifacts: the migrator up to an old identifier, and raw rows in
        // `screen_*` tables no current record writes. The version MarqueeDataKit resolves.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "test-shows",
            dependencies: [
                .product(name: "MarqueeDataKit", package: "MarqueeDataKit"),
                .product(name: "MarqueeSurfaceEngine", package: "MarqueeSurfaceEngine"),
                .product(name: "MarqueeSurfaceEngineLoader", package: "MarqueeSurfaceEngine"),
                .product(name: "MarqueeSessionBoard", package: "MarqueeSessionBoard"),
                // BRAND26's template packages: the kit's zip and package rules (PRD 14 M5-1).
                .product(name: "MarqueeSessionBoardTemplate", package: "MarqueeSessionBoard"),
                .product(name: "MarqueeSessionBoardCartridge", package: "MarqueeSessionBoard"),
                .product(name: "WebPSwift", package: "webp-swift"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]),
    ],
    swiftLanguageModes: [.v5]
)
