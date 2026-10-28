// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tendedero",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        // Resources holds the translations. scripts/build-app.sh copies them
        // into the app, so SwiftPM leaves them alone.
        .executableTarget(name: "Tendedero", dependencies: [.product(name: "Sparkle", package: "Sparkle")],
                          path: "Sources/Tendedero", exclude: ["Resources"],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "TendederoTests", dependencies: ["Tendedero"]),
        .testTarget(name: "ImageHistoryTests", dependencies: ["Tendedero"], path: "Tests/ImageHistoryTests")
    ]
)
