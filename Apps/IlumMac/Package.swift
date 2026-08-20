// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IlumMac",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../../Packages/IlumCore")],
    targets: [
        .target(
            name: "IlumMacSupport",
            dependencies: [.product(name: "IlumCore", package: "IlumCore")]
        ),
        .executableTarget(
            name: "IlumMac",
            dependencies: [
                .product(name: "IlumCore", package: "IlumCore"),
                "IlumMacSupport"
            ]
        ),
        .testTarget(
            name: "IlumMacSupportTests",
            dependencies: [
                .product(name: "IlumCore", package: "IlumCore"),
                "IlumMacSupport"
            ]
        )
    ]
)
