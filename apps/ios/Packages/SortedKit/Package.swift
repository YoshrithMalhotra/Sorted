// swift-tools-version: 6.0
import PackageDescription

// SortedKit holds the app's logic that has no UI: the recurrence engine,
// the notification window planner and the parse API contract. It builds for
// macOS too, so `swift test` runs it without a simulator.
let package = Package(
    name: "SortedKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SortedKit", targets: ["SortedKit"]),
    ],
    targets: [
        .target(name: "SortedKit"),
        .testTarget(name: "SortedKitTests", dependencies: ["SortedKit"]),
    ]
)
