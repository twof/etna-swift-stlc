// swift-tools-version: 6.2
import PackageDescription

// PropertyTestingKit requires the patched Swift toolchain (parameter packs) and
// macOS 26. Build via ./scripts/swift-toolchain.sh, not system `swift`.
//
// `-sanitize-coverage=edge,pc-table` instruments the code under test so PTK's
// SanCovHooks can observe edge coverage; `-sanitize=undefined` matches PTK's own
// build. Any product linking the instrumented `STLC` module must also link PTK
// (which provides the SanitizerCoverage callbacks).
let sanitize: [SwiftSetting] = [
    .unsafeFlags(["-sanitize=undefined", "-sanitize-coverage=edge,pc-table"])
]

let package = Package(
    name: "etna-swift-stlc",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "stlc", targets: ["Solve"]),
        .executable(name: "stlc-sampler", targets: ["stlc-sampler"]),
    ],
    dependencies: [
        .package(path: "../PropertyTestingKit"),
    ],
    targets: [
        // System under test + spec + decoders. Instrumented for coverage.
        .target(
            name: "STLC",
            swiftSettings: sanitize
        ),
        // PTK-backed generators + coverage-guided solve/sample strategy.
        .target(
            name: "STLCGen",
            dependencies: [
                "STLC",
                .product(name: "PropertyTestingKit", package: "PropertyTestingKit"),
            ],
            swiftSettings: sanitize
        ),
        // Target dir is `Solve` (not `stlc`) to avoid a case-insensitive
        // filesystem clash with the `STLC` library; the product is still `stlc`.
        .executableTarget(
            name: "Solve",
            dependencies: ["STLCGen"],
            swiftSettings: sanitize
        ),
        .executableTarget(
            name: "stlc-sampler",
            dependencies: ["STLCGen"],
            swiftSettings: sanitize
        ),
        .testTarget(
            name: "STLCTests",
            dependencies: [
                "STLC",
                // GeneratorTests exercises the bespoke generator's well-typedness invariant.
                "STLCGen",
                // Provides the SanitizerCoverage runtime for the instrumented STLC module.
                .product(name: "PropertyTestingKit", package: "PropertyTestingKit"),
            ],
            swiftSettings: sanitize
        ),
    ]
)
