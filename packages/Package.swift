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
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets:
        modules.map { name -> Target in
            // Per-module dependency edges:
            // - OWDevices's attribution layer (M11.3) reads TCC events
            //   via OWLog.
            // - OWRules (M13.1) evaluates detection rules over process
            //   + persistence snapshots, parsed from YAML via Yams.
            let deps: [Target.Dependency]
            switch name {
            case "OWDevices":
                deps = [.byName(name: "OWLog")]
            case "OWRules":
                deps = [
                    .byName(name: "OWBinary"),
                    .byName(name: "OWProcess"),
                    .byName(name: "OWPersistence"),
                    .product(name: "Yams", package: "Yams")
                ]
            default:
                deps = []
            }
            return .target(name: name, dependencies: deps)
        }
        + modules.map { name in
            .testTarget(name: "\(name)Tests", dependencies: [.byName(name: name)])
        }
        + [
            .executableTarget(
                name: "owlwatch",
                dependencies: [
                    .byName(name: "OWBinary"),
                    .byName(name: "OWCodeSigning"),
                    .byName(name: "OWDevices"),
                    .byName(name: "OWLog"),
                    .byName(name: "OWNetwork"),
                    .byName(name: "OWPersistence"),
                    .byName(name: "OWProcess"),
                    .byName(name: "OWRules"),
                    .product(name: "ArgumentParser", package: "swift-argument-parser")
                ]
            ),
            .testTarget(name: "owlwatchTests", dependencies: [.byName(name: "owlwatch")])
        ],
    swiftLanguageModes: [.v6]
)
