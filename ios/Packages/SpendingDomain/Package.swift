// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpendingDomain",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "SpendingDomain", targets: ["SpendingDomain"])
    ],
    targets: [
        .target(
            name: "SpendingDomain",
            path: "Sources/SpendingDomain"
        ),
        .testTarget(
            name: "SpendingDomainTests",
            dependencies: ["SpendingDomain"],
            path: "Tests/SpendingDomainTests"
        )
    ]
)
