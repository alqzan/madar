// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "MadarCommands", platforms: [.iOS("26.0"), .macOS("26.0")], products: [.library(name: "MadarCommands", targets: ["MadarCommands"]), .executable(name: "MadarCommandProbe", targets: ["MadarCommandProbe"])], dependencies: [.package(path: "../MadarCore"), .package(path: "../MadarData")], targets: [.target(name: "MadarCommands", dependencies: ["MadarCore", "MadarData"]), .executableTarget(name: "MadarCommandProbe", dependencies: ["MadarCommands", "MadarData", "MadarCore"])])
