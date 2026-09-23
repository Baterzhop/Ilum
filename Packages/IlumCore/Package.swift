// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IlumCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "IlumCore", targets: ["IlumCore"])
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            pkgConfig: "sqlite3",
            providers: [.apt(["libsqlite3-dev"]), .brew(["sqlite3"])]
        ),
        .target(name: "IlumCore", dependencies: ["CSQLite"]),
        .testTarget(name: "IlumCoreTests", dependencies: ["IlumCore"])
    ]
)
