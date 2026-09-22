// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "WakeLockCore",
  products: [
    .library(name: "WakeLockCore", targets: ["WakeLockCore"])
  ],
  targets: [
    .target(name: "WakeLockCore"),
    .testTarget(name: "WakeLockCoreTests", dependencies: ["WakeLockCore"]),
  ]
)
