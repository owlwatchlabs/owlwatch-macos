# Changelog

All notable user-visible and operational changes to Owlwatch are tracked here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Pre-1.0 entries are tagged with the milestone identifier (`v0.1.0-m0`, `v0.2.0-m1`, ...) to keep the link between milestones and tags explicit. The `[Unreleased]` section accumulates entries between tags; each PR that ships a user-visible or operational change adds a line under the relevant subsection.

## [Unreleased]

_No entries yet. M3 work (`OWCodeSigning` — code-signing inspection: signature validity, Team ID, designated requirement, notarization status, hardened-runtime flags, entitlements) lands here._

## [v0.3.0-m2] — 2026-05-21

The binary-parser milestone. Lands `OWBinary` — the second non-stub `OW*` library — plus `owlwatch inspect`, the second subcommand. Together they parse Mach-O and Universal binaries and expose six dimensions of binary inspection (dependencies, runtime search paths, identity, symbols, segment / section layout, per-section entropy) through a single composable CLI. The companion library is the static-analysis foundation every later milestone builds on: M3 (`OWCodeSigning`) reads `LC_CODE_SIGNATURE` from the segment data; M13 (`OWRules`) can match detection rules against linked dylibs, imported symbol names, segment protection bits, and entropy thresholds.

### Added

- **`OWBinary` module** — public surface: `OWBinary.parse(at: URL, includeSymbols: Bool = false) throws -> BinaryFile`, `OWBinary.entropy(of: URL, fileOffset: UInt64, length: UInt64) throws -> Double`, `OWBinary.sectionEntropies(of: BinaryFile) throws -> [SectionEntropy]`. Value types: `BinaryFile` (with `linkedDylibs` convenience deduplicating LC_LOAD_DYLIB-family entries across slices), `Slice` (architecture, fileType, flags, fileOffsetInBinary, loadCommands, optional symbols), `Architecture` enum (`.i386`/`.x86_64`/`.arm`/`.arm64`/`.arm64_32`/`.unknown(cpuType:)`), `FileType` enum (`.executable`/`.dylib`/`.dynamicLinker`/`.bundle`/`.object`/...), `LoadCommand` enum (`.dylib(Dylib)`/`.rpath(path:)`/`.uuid(_:)`/`.main(entryOffset:stackSize:)`/`.segment(Segment)`/`.other(rawType:)`), `Segment` and `Section` (with `SegmentProtection` `OptionSet` rendering `r-x` / `rw-` / `rwx` symbolic forms), `Symbol` with `Kind` enum and `nmCode` (`nm(1)`-style type code), `SectionEntropy`. `OWBinaryError` covers the four failure modes (`unreadable`, `unrecognizedMagic`, `malformed`, `truncated`).
- **Load-command coverage**: `LC_LOAD_DYLIB`, `LC_LOAD_WEAK_DYLIB`, `LC_REEXPORT_DYLIB`, `LC_LAZY_LOAD_DYLIB`, `LC_LOAD_UPWARD_DYLIB`, `LC_ID_DYLIB`, `LC_RPATH`, `LC_UUID`, `LC_MAIN`, `LC_SEGMENT`, `LC_SEGMENT_64`, `LC_SYMTAB` (captured for symbol-table parsing; not surfaced as its own variant). Everything else lands in `LoadCommand.other(rawType:)` with the raw 32-bit `cmd` value preserved.
- **`owlwatch inspect <path>`** — second subcommand. Default output: file path, format (Universal vs thin), per-slice architecture / type / flags / load-command count. Flags:
  - `-l` / `--libs` — list every linked dynamic library with `[required\|weak\|self]` tag.
  - `-r` / `--rpaths` — list every `LC_RPATH` entry.
  - `--identity` — print `LC_UUID` and `LC_MAIN` (entry offset + stack size) per slice.
  - `-s` / `--symbols` — list every symbol in `nm(1)`-style format. `--external-only` narrows to imports + exports.
  - `--segments` — list every segment with its sections, sizes, and VM protection (`r-x` / `rw-` / `rwx`).
  - `--entropy` — compute Shannon entropy per section; flag sections above 7.0 bits/byte as `[HIGH]`.
  All flags compose.
- **Shannon entropy primitive** — Single-pass 256-bucket histogram → entropy calculation. Used by `--entropy` and exposed to callers via `OWBinary.entropy(of:fileOffset:length:)` for arbitrary file ranges. Zero-fill sections (`S_ZEROFILL` / `S_GB_ZEROFILL` / `S_THREAD_LOCAL_ZEROFILL`) are skipped in `sectionEntropies` since they have no on-disk bytes.
- **Owlwatch version bump** — `owlwatch --version` now prints `0.3.0-m2`.

## [v0.2.0-m1] — 2026-05-21

The process-inspector milestone. First runnable Owlwatch binary: `owlwatch ps` lists every process visible to the caller as a table or `pstree`-style hierarchy, with optional argv / executable-path / FD-count / per-PID-focus modifiers. The companion library `OWProcess` is the project's first non-stub `OW*` module and is the data foundation every later milestone builds on.

### Added

- **`OWProcess` module** — public surface: `RunningProcess` value type (`pid`, `parentPid`, `name`, `path`, `userId`, `arguments`, `openFiles`); `OpenFile` enum (`.file`/`.socket`/`.pipe`/`.other`); `OWProcess.all(includeArguments:includeOpenFiles:)` and `OWProcess.snapshot(pid:includeArguments:includeOpenFiles:)` static APIs. Backed by libproc (`proc_listpids`, `proc_pidinfo` PROC_PIDTBSDINFO / PROC_PIDLISTFDS / PROC_PIDFDVNODEPATHINFO / PROC_PIDFDSOCKETINFO, `proc_pidpath`) and `sysctl(KERN_PROCARGS2)`. No entitlements required.
- **`owlwatch` executable target** — first shipping binary. Built on Apple's `swift-argument-parser`.
- **`owlwatch ps`** — print the current process table.
  - Default: fixed-width table with `PID`, `PPID`, `USER`, `NAME`.
  - `-p` / `--paths`: append `PATH` column with the executable path.
  - `-a` / `--args`: append `ARGS` column (or inline annotation in tree mode) with `argv[1..]`.
  - `-f` / `--files`: append `FDS` column (or `[N fds]` annotation) with open-file-descriptor count.
  - `-t` / `--tree`: render as a `pstree`-style hierarchy. Processes whose parent is invisible to the caller group under a synthetic `[unavailable](<ppid>)` header.
  - `--pid <PID>`: focus on a single process. In table mode, returns just the matching process. In tree mode, returns the subtree rooted at that PID (without the synthetic-parent header).
- **`owlwatch --version`** — prints `0.2.0-m1`.
- **`Makefile`** — convenience entry points: `build`, `release`, `test`, `install` (places `owlwatch` at `$PREFIX/bin/owlwatch`, default `PREFIX=/usr/local`), `uninstall`, `clean`. Honors `DESTDIR` for packaging.
- **ADR-0003** at `docs/adr/0003-rename-to-owlwatch.md` documenting the post-M0 project rename, superseding the bundle-identifier subsection of ADR-0001.

### Changed

- **Project renamed from `Nightwatch` to `Owlwatch`** per [ADR-0003](docs/adr/0003-rename-to-owlwatch.md). Bundle ID namespace moved from `dev.xorxorjmp.nightwatch.*` to `com.owlwatchlabs.owlwatch.*`; Swift module prefix moved from `NW*` to `OW*`; CLI binary renamed from `nwctl` to `owlwatch`. The `OwlWatch Labs` publisher identity backs `owlwatchlabs.com` (registered). The `v0.1.0-m0` tag retains the old names as a historical artifact; this release is the first under the new identity.
- **Repository transferred to the `owlwatchlabs` GitHub organization** and renamed to `owlwatch-macos`. New URL: `https://github.com/owlwatchlabs/owlwatch-macos`. GitHub auto-redirects every prior URL (`xorxorjmp/nightwatch`, `xorxorjmp/owlwatch`, `owlwatchlabs/owlwatch`) to the current one. External consumers do not need to act; the redirects are permanent.

### Deferred to M2

- **Linked-library enumeration.** Originally listed under M1's "libraries" deliverable. Listing libraries loaded into another process at runtime requires either `task_for_pid` (privileged Mach API restricted on modern macOS) or `proc_pidinfo(PROC_PIDREGIONPATHINFO)` with extension-based filtering of memory-mapped regions. Static analysis of the process binary's `LC_LOAD_DYLIB` load commands is cleaner and lives naturally in the `OWBinary` module, which is M2's home. The deliverable folds into M2 with a real Mach-O backing.

### Notes

- **First runnable binary.** Build with `make release`; install with `sudo make install`. The release binary lands at `/usr/local/bin/owlwatch` by default.
- **Visibility.** `owlwatch ps` from an unprivileged user shell sees ~370 of the host's ~540 processes — the gap is root-owned and SIP-protected processes that `proc_pidinfo` refuses to expose. Running with `sudo` collapses the gap. This is a macOS-level constraint; the tool is honest about what it can and can't see.

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

[Unreleased]: https://github.com/owlwatchlabs/owlwatch-macos/compare/v0.3.0-m2...HEAD
[v0.3.0-m2]: https://github.com/owlwatchlabs/owlwatch-macos/releases/tag/v0.3.0-m2
[v0.2.0-m1]: https://github.com/owlwatchlabs/owlwatch-macos/releases/tag/v0.2.0-m1
[v0.1.0-m0]: https://github.com/owlwatchlabs/owlwatch-macos/releases/tag/v0.1.0-m0
