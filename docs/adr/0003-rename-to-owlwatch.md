# ADR-0003: Rename project to Owlwatch and adopt `com.owlwatchlabs.owlwatch.*` bundle IDs

## Status

Accepted — 2026-05-21. Supersedes the **Bundle identifiers** subsection of [ADR-0001](0001-tech-stack-lock-in.md).

## Context

The project shipped its M0 foundation under the name **Nightwatch**, with bundle IDs in the `dev.xorxorjmp.nightwatch.*` namespace and Swift module names prefixed `NW*`. Two pressures converged before M1.1 shipped its first user-visible binary:

1. **The `dev.xorxorjmp.*` namespace bakes the maintainer's GitHub handle into every bundle ID.** Apple treats the bundle ID prefix as a permanent claim on its services namespace, tied to a specific Team ID. Re-namespacing later means re-registering every bundle ID, re-submitting Apple entitlement requests, breaking TCC permission grants from any user who'd installed a prior build, and rewriting external references. The cost of changing the prefix grows monotonically over the project's lifetime; it is at its absolute minimum **before any binary ships and before Apple processes the entitlement requests**.
2. **A brand-coherent publisher domain became available.** `owlwatchlabs.com` registered for ~$10/year provides a stable publisher identity (`OwlWatch Labs`) and a natural product name (`Owlwatch`) whose meaning (a nocturnal predator that watches) reinforces the security tool's purpose without the personal-handle baggage.

Renaming the product alongside the namespace produces a coherent identity stack — publisher (`OwlWatch Labs`), product (`Owlwatch`), command-line (`owlwatch`), modules (`OW*`) — at the cost of a single sweeping PR, executed before M1.1 merges so the M1 work lands under the new names natively.

## Decision

The following are adopted as of this ADR, superseding the relevant clauses of ADR-0001.

### Names

- **Product name:** `Owlwatch` (single-cap, no space). Replaces `Nightwatch` everywhere.
- **Publisher / vendor identity:** `OwlWatch Labs` (intercap, two words). Used in `LICENSE` copyright lines, Apple Developer Program registration, future "About" panels, and external attribution.
- **Repository:** `xorxorjmp/owlwatch` on GitHub (rename pending; GitHub auto-redirects the old URL).
- **Command-line:** `owlwatch` (was `nwctl`). The binary's first subcommand remains `ps`, so the new invocation is `owlwatch ps`.
- **Swift module prefix:** `OW*` (was `NW*`). All 17 library modules and 17 test targets renamed: `OWAttest`, `OWBinary`, `OWCodeSigning`, `OWCore`, `OWDNS`, `OWDevices`, `OWEndpoint`, `OWLog`, `OWNetwork`, `OWNetworkExt`, `OWPersistence`, `OWPosture`, `OWProcess`, `OWProtocol`, `OWRules`, `OWStore`, `OWUIKit`.

### Bundle ID namespace

Every Apple target moves to `com.owlwatchlabs.*`:

| Target | Bundle ID |
|---|---|
| macOS menu-bar app | `com.owlwatchlabs.owlwatch` |
| iOS companion | `com.owlwatchlabs.owlwatch.mobile` |
| Endpoint Security extension (M8) | `com.owlwatchlabs.owlwatch.endpoint` |
| Network Extension filter (M7) | `com.owlwatchlabs.owlwatch.network` |
| DNS proxy provider (M12) | `com.owlwatchlabs.owlwatch.dns` |
| Persistence monitor (M10) | `com.owlwatchlabs.owlwatch.persistence` |

This shape (`<publisher>.<product>.<surface>`) is the most idiomatic Apple bundle-ID structure: publisher namespace at the top, product as a stable second-level, per-target suffix at the bottom. The publisher namespace is reusable if OwlWatch Labs ever ships a second product.

### Domain ownership

`owlwatchlabs.com` is registered to the maintainer. This satisfies the conventional Apple Developer Program expectation that the bundle ID prefix reverses to a domain controlled by the developer.

### LICENSE copyright

`Copyright 2026 Owlwatch contributors` in the Apache 2.0 LICENSE's appendix block. ADR-0002's substantive decision (Apache 2.0, SPDX-only headers, inbound=outbound) is unchanged; only the project name in the copyright line moves.

## Consequences

### What this buys

- **A bundle-ID prefix the project can keep forever.** No personal-handle baggage; no domain-ownership ambiguity (we own `owlwatchlabs.com`); a clean two-tier prefix (`com.owlwatchlabs.*`) under which future products fit cleanly.
- **A coherent brand stack.** `owlwatchlabs.com` (domain), `OwlWatch Labs` (publisher), `Owlwatch` (product), `owlwatch` (CLI), `OW*` (modules) all share the same stem. External references — Apple's review team, package directories, security catalogs — can parse the relationship at a glance.
- **A transferable identity.** If Owlwatch ever moves to a foundation, an organization, or a successor maintainer, the bundle IDs and copyright line don't have to be rewritten to make sense.

### What this costs

- **A single sweeping PR.** ~80 file changes covering all sources, docs, ADRs, configs, workflows, project specs, Xcode workspace, and Apple entitlement-request scaffold. Mechanical, but large.
- **The v0.1.0-m0 tag retains the old name.** The tag was pushed before this rename. Its commit message says "Nightwatch v0.1.0-m0" and references `dev.xorxorjmp.nightwatch.*`. Tags are immutable in practice; the v0.1.0-m0 tag remains as a historical artifact recording the project's foundation under the prior name. `git log v0.1.0-m0` faithfully reproduces the state at that point.
- **GitHub repo URL changes.** The `xorxorjmp/nightwatch` URL keeps working via GitHub's automatic redirect, but external links to specific files or PR numbers under the old URL may render slightly differently. No action required from external consumers; the redirect is permanent.
- **Apple entitlement requests need updating before submission.** The draft justifications in [`docs/apple-developer/entitlement-requests.md`](../apple-developer/entitlement-requests.md) reference the old bundle IDs. The rename PR updates them; no submission has yet happened, so no Apple-side correspondence needs amending.

### Reversibility

This ADR is effectively permanent. Once the rename PR merges:

- The GitHub repo URL change is reversible (rename back) but introduces additional redirect chaining.
- The bundle ID change is **not** reversible without re-registering everything on Apple's side — same cost as the forward move, plus losing whatever state Apple's review team has accumulated for the new namespace.
- The module-prefix change is reversible (mechanical) but pointless after any external code depends on `OW*`.

Treat the post-merge state as the new baseline. Future rename ADRs would only make sense if OwlWatch Labs itself rebrands, which is a different decision than this one.

## Alternatives considered

- **Keep `Nightwatch` as the product name; only change the bundle ID namespace to `com.owlwatchlabs.nightwatch.*`.** Coherent enough — publisher (`OwlWatch Labs`) and product (`Nightwatch`) are distinct identities, which is a common pattern (Anthropic / Claude, Mozilla / Firefox). Rejected for two reasons: (1) the abstraction of two names with no shared stem makes external messaging fractionally harder ("Nightwatch by OwlWatch Labs" requires explaining the relationship); (2) the project is at exactly the moment when renaming is cheapest, so optimizing for "minimal change" forfeits the brand-coherence upside.
- **Keep `dev.xorxorjmp.nightwatch.*` and only buy the domain for marketing.** Rejected — the bundle ID prefix is the load-bearing piece. A domain without a matching prefix doesn't address the personal-handle baggage.
- **Use `io.github.xorxorjmp.nightwatch.*` (GitHub Pages defensible namespace).** Free, defensible, but still bakes the GitHub handle into every bundle ID. Solves the domain-ownership concern, not the handle-exposure concern.
- **Rename to a different product name entirely (e.g., `Sentry`, `Watchtower`, `Hawk`).** All considered. Rejected: most candidate names have heavy existing usage in security tooling (Sentry → error tracking SaaS, Watchtower → container monitor, Hawk → various). `Owlwatch` carries the brand stem from the publisher and has no notable existing collision in the security-tools space.
