// swift-tools-version: 5.9
// This file exists solely as a dependency manifest for Dependabot and OSV Scanner.
// The actual build uses UnArchiver.xcodeproj — this Package.swift is never built.
import PackageDescription

let package = Package(
    name: "UnArchiver",
    platforms: [.iOS(.v17)],
    dependencies: [
        .package(url: "https://github.com/tsolomko/SWCompression", from: "4.8.0"),
        .package(url: "https://github.com/raspu/Highlightr",       from: "2.2.0"),
    ],
    targets: []
)
