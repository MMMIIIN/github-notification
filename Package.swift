// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GitHubNotifier",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GitHubNotifier", targets: ["GitHubNotifier"])
    ],
    targets: [
        .executableTarget(
            name: "GitHubNotifier",
            path: "Sources/GitHubNotifier"
        ),
        .testTarget(
            name: "GitHubNotifierTests",
            dependencies: ["GitHubNotifier"],
            path: "Tests/GitHubNotifierTests"
        )
    ]
)
