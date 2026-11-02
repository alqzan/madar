// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "MadarData", platforms: [.iOS("27.0"), .macOS(.v26)], products: [.library(name: "MadarData", targets: ["MadarData"])], targets: [.target(name: "MadarData", resources: [.process("Resources")]), .testTarget(name: "MadarDataTests", dependencies: ["MadarData"], resources: [.copy("Resources")])])
