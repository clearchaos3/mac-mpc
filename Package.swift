// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mac-mpc",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "mac-mpc", targets: ["App"]),
        .library(name: "MMAudio", targets: ["MMAudio"]),
        .library(name: "MMMidi", targets: ["MMMidi"]),
        .library(name: "MMModels", targets: ["MMModels"]),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: ["MMAudio", "MMMidi", "MMModels"],
            path: "Sources/App",
            // SwiftPM blocks Info.plist as a regular resource. Park it in
            // SupportFiles/ (excluded from resources) and embed it directly
            // into the binary's __TEXT,__info_plist section via the linker
            // so AppKit treats the process as a real app.
            exclude: ["SupportFiles"],
            resources: [.process("Resources")],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/App/SupportFiles/Info.plist",
                ])
            ]
        ),
        .target(name: "MMAudio", dependencies: ["MMModels"], path: "Sources/MMAudio"),
        .target(name: "MMMidi", dependencies: ["MMModels"], path: "Sources/MMMidi"),
        .target(name: "MMModels", path: "Sources/MMModels"),
        .testTarget(name: "MMAudioTests",  dependencies: ["MMAudio"],  path: "Tests/MMAudioTests"),
        .testTarget(name: "MMMidiTests",   dependencies: ["MMMidi"],   path: "Tests/MMMidiTests"),
        .testTarget(name: "MMModelsTests", dependencies: ["MMModels"], path: "Tests/MMModelsTests"),
    ]
)
