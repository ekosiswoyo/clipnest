// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ClipNest", platforms: [.macOS(.v13)], products: [.executable(name: "ClipNest", targets: ["ClipNest"])], targets: [.target(name: "ClipNestCore"), .executableTarget(name: "ClipNest", dependencies: ["ClipNestCore"]), .executableTarget(name: "ClipNestChecks", dependencies: ["ClipNestCore"], path: "Tests/ClipNestCoreTests", resources: [.copy("Fixtures")])])
