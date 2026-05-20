// swift-tools-version:6.0
import PackageDescription

let modules: [String] = [
    "NWAttest",
    "NWBinary",
    "NWCodeSigning",
    "NWCore",
    "NWDNS",
    "NWDevices",
    "NWEndpoint",
    "NWLog",
    "NWNetwork",
    "NWNetworkExt",
    "NWPersistence",
    "NWPosture",
    "NWProcess",
    "NWProtocol",
    "NWRules",
    "NWStore",
    "NWUIKit"
]

let package = Package(
    name: "Nightwatch",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products:
        modules.map { name in
            .library(name: name, targets: [name])
        }
        + [
            .executable(name: "nwctl", targets: ["nwctl"])
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
                name: "nwctl",
                dependencies: [
                    .byName(name: "NWProcess"),
                    .product(name: "ArgumentParser", package: "swift-argument-parser")
                ]
            ),
            .testTarget(name: "nwctlTests", dependencies: [.byName(name: "nwctl")])
        ],
    swiftLanguageModes: [.v6]
)
