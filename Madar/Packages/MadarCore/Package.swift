// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MadarCore",
    platforms: [.iOS("27.0"), .macOS(.v26)],
    products: [.library(name: "MadarCore", targets: ["MadarCore"])],
    dependencies: [.package(url: "https://github.com/batoulapps/adhan-swift.git", revision: "a6fa2deee80c5abb0b9ad04466f8ab12b53144e7")],
    targets: [
        .target(name: "MadarCore", dependencies: [.product(name: "Adhan", package: "adhan-swift")]),
        .testTarget(name: "MadarCoreTests", dependencies: ["MadarCore"], resources: [.copy("Fixtures")])
    ]
)
