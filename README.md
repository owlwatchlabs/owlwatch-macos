# Nightwatch

Nightwatch is an open-source Endpoint Detection and Response platform for macOS, with a companion iOS posture agent. The macOS product is designed around Endpoint Security, Network Extension, code-signing validation, persistence inspection, and a native detection rules library for identifying suspicious behavior on Apple platforms.

[![Build](https://img.shields.io/badge/build-planned-lightgrey)](#)
[![Tests](https://img.shields.io/badge/tests-planned-lightgrey)](#)
[![Coverage](https://img.shields.io/badge/coverage-planned-lightgrey)](#)
[![Release](https://img.shields.io/badge/release-M0%20in%20progress-lightgrey)](#)
[![License](https://img.shields.io/badge/license-pending%20ADR--0002-lightgrey)](#)
[![Platforms](https://img.shields.io/badge/platforms-macOS%2014%2B%20%7C%20iOS%2017%2B-blue)](#)
[![Rules](https://img.shields.io/badge/rules--validated-planned-lightgrey)](#)

## Demo

Demo recording scripts live in [`docs/demos/`](docs/demos/) and cover the menu-bar agent, console, and `nwctl` quickstart. They are [VHS](https://github.com/charmbracelet/vhs) tape files; run `vhs docs/demos/<name>.tape` to regenerate. At M0 the tapes are placeholders pointing at behavior that ships in later milestones — see [`docs/demos/README.md`](docs/demos/README.md) for the convention and the per-tape milestone mapping.

## Features

- [x] M0 repository skeleton
- [ ] M0 CI, lint, and rule-validation workflow stubs
- [ ] M0 signed empty macOS app, iOS app, and System Extension targets
- [ ] M1 process inspection library and `nwctl ps`
- [ ] M2 Mach-O and Universal binary parser
- [ ] M3 code-signing and notarization inspection
- [ ] M4 host network state inspection
- [ ] M5 persistence enumeration
- [ ] M8 Endpoint Security event ingestion
- [ ] M13 detection rules engine and tested rule library

## Architecture

```mermaid
flowchart LR
    MenuBar[Nightwatch macOS App] <--> XPC[NWProtocol XPC]
    Console[Nightwatch Console] --> Store[NWStore SQLite + FTS5]
    Endpoint[NightwatchEndpoint System Extension] --> XPC
    Network[NightwatchNetwork Filter Provider] --> XPC
    DNS[NightwatchDNS Proxy Provider] --> XPC
    Persistence[NightwatchPersistence Watcher] --> XPC
    XPC --> Store
    Store --> Rules[NWRules Engine]
    Rules --> Detections[Detections]
    Mobile[NightwatchMobile iOS] <--> Protocol[NWProtocol Wire Format]
```

## Detection Library

Rules live in `rules/` and use a Nightwatch-native YAML schema. The schema, catalog generator, fixtures, and MITRE ATT&CK coverage land in M13. Rule contributions are expected to include schema-valid YAML, fixtures, severity, and MITRE mapping where applicable.

## Install

No public release is available yet. Release artifacts will be Developer ID signed, notarized, distributed as a DMG, and accompanied by checksums and an SBOM.

## Build From Source

The bootstrap flow is planned for M0:

```bash
make bootstrap
make build
make sign
```

## Run Tests

The test and lint entry points are planned for M0:

```bash
make test
make lint
```

## Contributing

See `CONTRIBUTING.md`. Detection rule contributions are first-class and must include fixtures.

## Security

See `SECURITY.md` for coordinated disclosure policy and reporting expectations.

## License

License selection is pending ADR-0002.

## Acknowledgments

Nightwatch is designed to build on Apple platform security frameworks and established open-source macOS security engineering practices.

