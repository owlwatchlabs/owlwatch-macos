// swift-tools-version:6.0
import PackageDescription

let modules: [String] = [
    "OWAttest",
    "OWBinary",
    "OWCodeSigning",
    "OWCore",
    "OWDNS",
    "OWDevices",
    "OWEndpoint",
    "OWLog",
    "OWNetwork",
    "OWNetworkExt",
    "OWPersistence",
    "OWPosture",
    "OWProcess",
    "OWProtocol",
    "OWRules",
    "OWStore",
    "OWUIKit"
]

let package = Package(
    name: "Owlwatch",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products:
        modules.map { name in
            .library(name: name, targets: [name])
        }
        + [
            .executable(name: "owlwatch", targets: ["owlwatch"])
        ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets:
        modules.map { name in
            .target(name: name)
        }
        + modules.map { name in
            .testTarget(name: "\(name)Tests", dependencies: [.byName(name: name)])
        }
        + [
            .executableTarget(
                name: "owlwatch",
                dependencies: [
                    .byName(name: "OWProcess"),
                    .product(name: "ArgumentParser", package: "swift-argument-parser")
                ]
            ),
            .testTarget(name: "owlwatchTests", dependencies: [.byName(name: "owlwatch")])
        ],
    swiftLanguageModes: [.v6]
)
