// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "aria_device",
  platforms: [.iOS("15.0")],
  products: [.library(name: "aria-device", targets: ["aria_device"])],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "aria_device",
      dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")]
    )
  ]
)
