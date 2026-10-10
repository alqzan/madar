// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "MadarDesign", platforms: [.iOS(.v26), .macOS(.v26)], products: [.library(name: "MadarDesign", targets: ["MadarDesign"])], targets: [.target(name: "MadarDesign", resources: [.process("Resources")])])
