// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "BananaStudio",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "BananaStudio", targets: ["BananaStudio"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [.executableTarget(name: "BananaStudio", dependencies: [.product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]), .testTarget(name: "BananaStudioTests", dependencies: ["BananaStudio"])]
)
