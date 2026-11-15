// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "MadarSnapshots", platforms: [.iOS("27.0"), .macOS("27.0"), .watchOS("27.0")], products: [.library(name: "MadarSnapshots", targets: ["MadarSnapshots"])], targets: [.target(name: "MadarSnapshots"), .testTarget(name: "MadarSnapshotsTests", dependencies: ["MadarSnapshots"])])
