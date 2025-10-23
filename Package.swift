// swift-tools-version:5.5
import PackageDescription

var swiftDateTargets: [Target] = [
    .target(
        name: "SwiftDate",
        dependencies: [],
        resources: [
            .copy("Formatters/RelativeFormatter/langs"),
            .process("Resources")
        ]
    ),
    .executableTarget(
        name: "MicAssignBridge",
        dependencies: [],
        path: "Sources/MicAssignBridge"
    ),
    .testTarget(
        name: "MicAssignBridgeTests",
        dependencies: ["MicAssignBridge"],
        path: "Tests/MicAssignBridgeTests"
    )
]

#if !os(Linux)
swiftDateTargets.append(
    .testTarget(
        name: "SwiftDateTests",
        dependencies: ["SwiftDate"]
    )
)
#endif

let package = Package(
    name: "SwiftDate",
    defaultLocalization: "it",
    platforms: [
        .macOS(.v10_15), .iOS(.v13), .watchOS(.v6), .tvOS(.v13)
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(name: "SwiftDate", targets: ["SwiftDate"]),
        .executable(name: "MicAssignBridge", targets: ["MicAssignBridge"])
    ],
    dependencies: [],
    targets: swiftDateTargets
)
