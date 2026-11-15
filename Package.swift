// swift-tools-version:5.9
import PackageDescription

var package = Package(
    name: "SWCompression",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "SWCompression",
            targets: ["SWCompression"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tsolomko/BitByteData", from: "2.1.0"),
    ],
    targets: [
        .target(
            name: "SWCompression",
            dependencies: ["BitByteData"],
            path: "Sources",
            exclude: ["swcomp"],
            sources: ["Common", "7-Zip", "BZip2", "Deflate", "GZip", "LZ4", "LZMA", "LZMA2", "TAR", "XZ", "ZIP", "Zlib"],
            resources: [.copy("PrivacyInfo.xcprivacy")]),
        // LOCAL PATCH (fork): regression tests for the hardening against hostile
        // input. Self-contained (inputs are inline bytes), unlike upstream's
        // tests, which need the Git LFS test-file submodule and run from the
        // Xcode project.
        .testTarget(
            name: "SWCompressionHardeningTests",
            dependencies: ["SWCompression"],
            path: "Tests/Hardening"),
    ],
    swiftLanguageVersions: [.v5]
)

#if os(macOS)
package.dependencies.append(.package(url: "https://github.com/jakeheis/SwiftCLI", from: "6.0.0"))
package.targets.append(.executableTarget(name: "swcomp", dependencies: ["SWCompression", "SwiftCLI"], path: "Sources",
            exclude: ["Common", "7-Zip", "BZip2", "Deflate", "GZip", "LZ4", "LZMA", "LZMA2", "TAR", "XZ", "ZIP", "Zlib", "PrivacyInfo.xcprivacy"],
            sources: ["swcomp"]))
#endif
