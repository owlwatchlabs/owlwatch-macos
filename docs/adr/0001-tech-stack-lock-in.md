# ADR-0001: Tech stack lock-in

## Status

Accepted — 2026-05-19. Lands as part of M0 (Foundation). **Bundle-identifiers subsection superseded by [ADR-0003](0003-rename-to-owlwatch.md) (2026-05-21).** Project name `Owlwatch` and module prefix `OW*` shown below reflect the post-rename state; this document was originally written under the project's working name `Nightwatch` with module prefix `NW*` and bundle ID namespace `dev.xorxorjmp.nightwatch.*`. The technical decisions (Swift version, SPM, XcodeGen, deployment floors, CI runner image) are unchanged.

## Context

Owlwatch ships through 15 milestones (M1–M15) over an extended timeline. Each milestone introduces code into a shared workspace, contributors, and CI pipelines. Tech choices made informally early on become irreversible later: a Swift version bump, a project-file format change, or a deployment-target floor change can each touch dozens of targets and risk breaking signed builds.

This ADR locks in the choices already made by the time M0 closes so that:

1. Future PRs can defer back to this document instead of re-litigating.
2. Contributors arriving at M1+ have a single source of truth for "what's already decided."
3. Tooling churn (Swift versions, Xcode releases, runner images) has an audit trail of when and why something was on a given version.

## Decision

The following are locked. Changing any of them requires a superseding ADR.

### Language and toolchain

- **Swift 6.0** with `swiftLanguageModes: [.v6]` set at the package level — strict concurrency on across all SPM modules.
- **Xcode 16.x or later.** Xcode 26.x is in use on the maintainer's machine; CI runners default to Xcode 16 on `macos-15`. Build settings target macOS 14 / iOS 17 so both Xcode generations build the project.

### Build system

- **Swift Package Manager** is the source of truth for library code under `packages/`. Every `NW*` module is an SPM target; tests are SPM test targets.
- **Xcode workspace** wraps SPM plus per-app/extension `.xcodeproj` files. The workspace lives at repo root: `Owlwatch.xcworkspace`.
- **XcodeGen** generates `.xcodeproj` content from per-project `project.yml` specs. Both the YAML and the generated `.xcodeproj` are committed: YAML is the source of truth, the generated file is committed so CI does not need XcodeGen installed.

### Platforms and deployment

- **macOS 14 (Sonoma)** minimum for the macOS app, every package target, and the future Endpoint / Network / DNS / Persistence extensions.
- **iOS 17** minimum for `OwlwatchMobile` and the iOS-side `NW*` modules (`OWPosture`, `OWAttest`).

### Frameworks

- **AppKit + SwiftUI** for the macOS menubar app. `MenuBarExtra` is the dropdown surface (macOS 13+ API).
- **SwiftUI** for the iOS companion.
- **Endpoint Security framework** (M8+) for the `OwlwatchEndpoint` system extension.
- **Network Extension framework** (M7+) for `OwlwatchNetwork` (filter provider) and `OwlwatchDNS` (DNS proxy provider).
- **XCTest** is the test framework for M0. Swift Testing (swift-testing) is not adopted yet; revisit when Apple ships it as the Xcode default.

### Bundle identifiers

Every target uses the `com.owlwatchlabs.owlwatch.*` namespace:

| Target | Bundle ID |
|---|---|
| macOS menubar app | `com.owlwatchlabs.owlwatch` |
| iOS app | `com.owlwatchlabs.owlwatch.mobile` |
| Endpoint Security ext (M8) | `com.owlwatchlabs.owlwatch.endpoint` |
| Network Extension filter (M7) | `com.owlwatchlabs.owlwatch.network` |
| DNS proxy provider (M12) | `com.owlwatchlabs.owlwatch.dns` |
| Persistence monitor (M10) | `com.owlwatchlabs.owlwatch.persistence` |

This is a personal-namespace pattern, not a domain-ownership claim. If the project ever acquires a real domain, the rename is a one-PR change documented as a superseding ADR.

### Signing

- **Free Apple ID / Personal Team** during M0 through early milestones. `project.yml` pins `CODE_SIGN_STYLE = Manual` and `CODE_SIGN_IDENTITY = "-"` (ad-hoc). `DEVELOPMENT_TEAM` is left empty for contributors to override locally.
- **Paid Apple Developer Program** is required from M7 onward (Network Extension entitlements, Endpoint Security client entitlement). Notarization lands at M15.

### CI

- **GitHub Actions** with the `macos-15` runner image for Swift, Xcode, CodeQL.
- **Required status checks**: `build`, `test`, `lint`, `codeql`, `gitleaks`, `rules-validate`. The check list is owned by `docs/repo-config.md`; this ADR records that the list exists, not what is on it.

## Consequences

### What this buys

- Contributors don't need to re-derive any of these decisions from history. Every PR can assume them.
- Tooling updates (Xcode bumps, Swift version changes) become individually-reviewable ADRs that supersede this one, instead of slipping into unrelated feature PRs.
- CI parity is enforceable: there is exactly one supported toolchain and one supported runner image at any time.

### What this costs

- Locking to Swift 6 / strict concurrency means every `NW*` module pays the strict-concurrency tax. For modules that wrap C APIs (`OWBinary` for Mach-O, `OWEndpoint` for ES C structs), this is real work — `Sendable` conformance and isolation annotations are not free.
- macOS 14 / iOS 17 floors mean a contributor on macOS 13 or earlier cannot run the apps. The project assumes contributors keep up with current macOS.
- XcodeGen as a dependency for adding new targets means M7+ extension PRs require contributors to install it. Mitigated by committing the generated `.xcodeproj` so consumers of the repo (CI, casual cloners) do not need XcodeGen themselves.

### Reversibility

Each decision is reversible via a superseding ADR. Some are cheap to flip (Swift version, Xcode version), some expensive (bundle ID namespace would require store-side coordination if the project ever ships to the Mac App Store; SPM-vs-XcodeGen would be a multi-PR migration).

## Alternatives considered

- **Tuist** instead of XcodeGen — Swift DSL for project generation. Heavier dependency; recompiles its Swift DSL on each generation run; XcodeGen's YAML is sufficient for this project's complexity. Reconsider if multi-platform sharing (visionOS, watchOS) becomes a real need.
- **Pure SPM with no Xcode workspace** — works for libraries but the macOS menubar app and iOS companion need `.app` bundles, Info.plist, entitlements, and code signing, none of which are first-class in SPM. Rejected.
- **Swift 5.x with opt-in strict concurrency** — would lower the migration cost short-term, but locks the project to a deprecated mode the moment Swift 7 ships. Rejected.
- **Sigma / Falco rule syntax** for the future detection schema — explicitly out of scope per `CLAUDE.md`. The detection schema is Owlwatch-native; this ADR does not pre-empt ADR-0003 (M13), which will land that schema.
