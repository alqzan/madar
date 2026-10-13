// swift-tools-version: 6.2
import PackageDescription

let package = Package(name: "MadarInbox", platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [.library(name: "MadarInbox", targets: ["MadarInbox"]), .executable(name: "MadarInboxProducer", targets: ["MadarInboxProducer"])],
    dependencies: [.package(path: "../MadarCore"), .package(path: "../MadarSnapshots")],
    targets: [.target(name: "MadarInbox", dependencies: ["MadarCore"]),
              .executableTarget(name: "MadarInboxProducer", dependencies: ["MadarInbox", "MadarCore"]),
              .testTarget(name: "MadarInboxTests", dependencies: ["MadarInbox", "MadarCore", "MadarSnapshots"])])
