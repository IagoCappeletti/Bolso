// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Bolso",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Bolso", targets: ["Bolso"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1")],
    targets: [
        .target(name: "BolsoCore"),
        .executableTarget(
            name: "Bolso",
            dependencies: ["BolsoCore", .product(name: "Sparkle", package: "Sparkle")],
            // build.sh embeds Sparkle.framework in the app's Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .executableTarget(name: "BolsoChecks", dependencies: ["BolsoCore"], path: "Tests/BolsoCoreTests"),
    ]
)
