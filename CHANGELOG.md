# Changelog

All notable user-visible and operational changes to Owlwatch are tracked here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Pre-1.0 entries are tagged with the milestone identifier (`v0.1.0-m0`, `v0.2.0-m1`, ...) to keep the link between milestones and tags explicit. The `[Unreleased]` section accumulates entries between tags; each PR that ships a user-visible or operational change adds a line under the relevant subsection.

## [Unreleased]

### Changed

- **Project renamed from `Nightwatch` to `Owlwatch`** per [ADR-0003](docs/adr/0003-rename-to-owlwatch.md). Bundle ID namespace moved from `dev.xorxorjmp.nightwatch.*` to `com.owlwatchlabs.owlwatch.*`; Swift module prefix moved from `NW*` to `OW*`; CLI binary renamed from `nwctl` to `owlwatch`. The `OwlWatch Labs` publisher identity backs `owlwatchlabs.com` (registered). The `v0.1.0-m0` tag retains the old names as a historical artifact; everything after this PR lands under the new ones.
- **Repository transferred to the `owlwatchlabs` GitHub organization** and renamed to `owlwatch-macos`. New URL: `https://github.com/owlwatchlabs/owlwatch-macos`. GitHub auto-redirects every prior URL (`xorxorjmp/nightwatch`, `xorxorjmp/owlwatch`, `owlwatchlabs/owlwatch`) to the current one. All in-repo references updated; external consumers do not need to act, the redirects are permanent.

### Added

- **`OWProcess` module** — first real implementation of an `OW*` library. Public surface: `RunningProcess` value type (pid, parentPid, name, path, userId) and `OWProcess.all()` / `OWProcess.snapshot(pid:)` static APIs. Backed by libproc (`proc_listpids`, `proc_pidinfo` PROC_PIDTBSDINFO, `proc_pidpath`). No entitlements required.
- **`owlwatch` executable target** — first shipping binary. Built on Apple's `swift-argument-parser` (v1.5+).
- **`owlwatch ps`** — first user-visible command. Prints the current process table as a fixed-width table (PID, PPID, USER, NAME columns; `--paths` / `-p` adds the executable path). Errors-on-individual-PID are silently skipped so the snapshot reflects the caller's view of the table rather than failing the whole command.
- **`owlwatch --version`** — prints `0.1.0-m0`. Version string is currently a hardcoded literal; M1 milestone-close lands a build-time derivation.
- **ADR-0003** at `docs/adr/0003-rename-to-owlwatch.md` documenting the rename, superseding the bundle-identifier subsection of ADR-0001.
- **M1.2: `owlwatch ps --tree`** — `pstree`-style hierarchy rendering. Children grouped under their `parentPid`; processes whose parent is invisible to the caller (root-owned daemons that `proc_pidinfo` refuses on unprivileged runs) render under a synthetic `[unavailable](<ppid>)` placeholder so the tree's shape stays readable instead of collapsing to a flat list of roots.
- **M1.2: `owlwatch ps --args`** — includes each process's `argv` in the output. Table mode appends an `ARGS` column (containing `argv[1..]`); tree mode appends the arguments inline on each node's line. Captured via `sysctl(KERN_PROCARGS2)`.
- **M1.2: `OWProcess.RunningProcess.arguments: [String]?`** — public surface for the captured `argv`. `nil` when the snapshot was taken without `includeArguments`; empty array when capture was requested but the process is unreachable (other-user / SIP-protected). `OWProcess.all(includeArguments:)` and `OWProcess.snapshot(pid:includeArguments:)` gain the optional parameter (default `false`).
- **M1.3: `owlwatch ps --files`** — adds an `FDS` column (table mode) or `[N fds]` annotation per node (tree mode) showing the open-file-descriptor count per process. Captured via `proc_pidinfo(PROC_PIDLISTFDS)` plus a variant-specific `proc_pidfdinfo` call per FD.
- **M1.3: `OWProcess.OpenFile` enum + `RunningProcess.openFiles: [OpenFile]?`** — public surface for the captured file descriptors. Variants: `.file(fd:path:)`, `.socket(fd:family:type:)`, `.pipe(fd:)`, `.other(fd:rawType:)`. Three-state semantics match `arguments`: `nil` when not captured, `[]` when capture was requested but the process is unreachable, populated array otherwise. `OWProcess.all(includeOpenFiles:)` and `OWProcess.snapshot(pid:includeOpenFiles:)` gain the optional parameter (default `false`).
- **M1.3 deferred: linked-library enumeration moves to M2.** Listing libraries loaded into another process at runtime requires either `task_for_pid` (privileged Mach API restricted on modern macOS) or `proc_pidinfo(PROC_PIDREGIONPATHINFO)` with extension-based filtering of memory-mapped regions. Static analysis of the process binary's `LC_LOAD_DYLIB` load commands is cleaner and lives naturally in the `OWBinary` module, which is M2's home. Rather than ship a partial / privilege-gated implementation in M1.3, the deliverable folds into M2 with a clear Mach-O backing.

## [v0.1.0-m0] — 2026-05-20

The foundation milestone. Establishes the repository, build system, CI, governance, and supporting documentation that every later milestone depends on. No user-visible runtime behavior yet — the macOS menu-bar app and iOS companion are empty SwiftUI shells, and the `owlwatch` CLI does not exist.

> **Historical note.** This tag was published under the project's original name `Nightwatch`, with module prefix `NW*`, bundle ID namespace `dev.xorxorjmp.nightwatch.*`, and CLI name `nwctl`. The project was renamed to Owlwatch shortly after the tag landed (see [ADR-0003](docs/adr/0003-rename-to-owlwatch.md)). The bullets below are written in the post-rename vocabulary; `git checkout v0.1.0-m0` produces the original tree with the prior names intact.

### Added

- **Repository scaffolding** (`apps/`, `extensions/`, `packages/`, `rules/`, `scripts/`, `tools/`, `docs/`) plus the meta files `README.md`, `ROADMAP.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`.
- **Swift 6 SPM package** at `packages/` with 17 library targets (`OWAttest`, `OWBinary`, `OWCodeSigning`, `OWCore`, `OWDNS`, `OWDevices`, `OWEndpoint`, `OWLog`, `OWNetwork`, `OWNetworkExt`, `OWPersistence`, `OWPosture`, `OWProcess`, `OWProtocol`, `OWRules`, `OWStore`, `OWUIKit`) and 17 matching test targets. All compile under `swiftLanguageModes: [.v6]` (strict concurrency).
- **Xcode workspace** (`Owlwatch.xcworkspace`) integrating the SPM package, a macOS menu-bar app target (`apps/Owlwatch/`), and an iOS companion target (`apps/OwlwatchMobile/`). XcodeGen `project.yml` specs are the source of truth; generated `.xcodeproj` files are committed so CI does not need XcodeGen installed.
- **Bundle ID namespace** `com.owlwatchlabs.owlwatch.*` for every current and future target. Documented in ADR-0001.
- **GitHub Actions CI** on `macos-15` runners with six required status checks: `build`, `test`, `lint` (SwiftLint), `codeql` (security-extended queries), `gitleaks`, `rules-validate` (stub until M13).
- **Branch protection on `main`**: PR required, 1 approval, signed commits, linear history, no force pushes, no deletions, no admin bypass (except the documented solo-maintainer review-rule bypass).
- **Pull request template**, `CODEOWNERS`, signed-commit configuration (SSH signing with `allowedSignersFile` for local verification).
- **LICENSE** — Apache License 2.0 at repo root.
- **ADR-0001** at `docs/adr/0001-tech-stack-lock-in.md` — locks Swift 6, SPM, Xcode + XcodeGen, macOS 14 / iOS 17 floors, AppKit + SwiftUI, Endpoint Security and Network Extension framework choices, XCTest, bundle ID namespace, signing posture, and CI runner image.
- **ADR-0002** at `docs/adr/0002-license.md` — records the Apache 2.0 decision, the SPDX-only source-file header convention (`// SPDX-License-Identifier: Apache-2.0`), and "inbound = outbound" contribution model (no separate CLA).
- **ADR conventions** at `docs/adr/README.md` — filename format, section order, never-edit-after-merge rule.
- **Apple restricted-entitlement request scaffold** at `docs/apple-developer/entitlement-requests.md` — drafted justifications for Endpoint Security client (M8), Network Extension content-filter-provider (M7), and Network Extension dns-proxy (M12). Ready to submit once paid Apple Developer Program enrollment completes.
- **Demo infrastructure** at `docs/demos/` — VHS tape placeholders for the CLI/TUI surfaces (`owlwatch.tape` for M1, `console.tape` for M6) and documented screen-capture approach for menu-bar (M2/M3) and iOS (M14) surfaces.
- **Repository configuration spec** at `docs/repo-config.md` — canonical record of intended GitHub settings; the GitHub UI is the source of truth for *applied* configuration, this document is the source of truth for *intended* configuration.

### Governance

- **Conventional Commits** enforced by convention (Commitlint not yet wired; lands when M1 first has many small commits to enforce against).
- **Solo-maintainer review path** documented in `docs/repo-config.md`: until a second maintainer joins, the "Require approvals: 1" rule is satisfied via a documented bypass-list addition; every other branch-protection rule still applies.
- **Private repo posture** documented in `docs/repo-config.md`: the three GitHub Advanced Security features (Secret scanning, Push protection, Private vulnerability reporting) are paid on private repos and deferred until the repository flips public at or before M15. `gitleaks` in CI is the de-facto secret scanner meanwhile.

### Notes

- **No user-installable artifact ships with this tag.** The next runnable binary lands at M1 (`owlwatch ps`); the next visible app surface lands at M2/M3.
- The four planned system extensions — Endpoint Security (M8), Network Extension filter (M7), DNS proxy (M12), Persistence monitor (M10) — exist as placeholder directories under `extensions/` but have no target shells yet. Each lands in its own milestone PR with the appropriate Apple-restricted entitlement (assuming Apple approval has landed by then).

[Unreleased]: https://github.com/owlwatchlabs/owlwatch-macos/compare/v0.1.0-m0...HEAD
[v0.1.0-m0]: https://github.com/owlwatchlabs/owlwatch-macos/releases/tag/v0.1.0-m0
