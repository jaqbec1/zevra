// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "AttentionCore",
  platforms: [.macOS(.v14)],
  products: [.library(name: "AttentionCore", targets: ["AttentionCore"])],
  dependencies: [.package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2")],
  targets: [
    .target(name: "AttentionCore", dependencies: ["Yams"]),
    .testTarget(name: "AttentionCoreTests", dependencies: ["AttentionCore"]),
  ]
)
