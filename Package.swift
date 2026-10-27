// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Bolso", platforms: [.macOS(.v13)], products: [.executable(name: "Bolso", targets: ["Bolso"])], targets: [.target(name: "BolsoCore"), .executableTarget(name: "Bolso", dependencies: ["BolsoCore"]), .executableTarget(name: "BolsoChecks", dependencies: ["BolsoCore"], path: "Tests/BolsoCoreTests")])
