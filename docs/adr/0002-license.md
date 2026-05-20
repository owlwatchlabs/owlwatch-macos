# ADR-0002: License — Apache 2.0

## Status

Accepted — 2026-05-19. Lands as part of M0 (Foundation).

## Context

Nightwatch is an open-source Endpoint Detection and Response tool whose components will eventually integrate with Apple's restricted security frameworks (Endpoint Security, Network Extension, DNS Proxy, System Extension). The license choice affects:

- Whether enterprises can adopt, embed, or fork the project without friction.
- Whether contributors can use the project in their work without legal review overhead.
- How the project handles patent rights for any defensive primitives it codifies.
- The bar for upstream contribution back from forks.

A license decision delayed past M0 would block the M0-close tag (`v0.1.0-m0`) and force every prior commit's contributors into ambiguous IP territory. M0 is the right moment to lock this in.

## Decision

Nightwatch is licensed under the **Apache License 2.0**.

The full text ships as `/LICENSE` at the repository root. The license governs every file in the repository unless a file explicitly states otherwise (none currently do).

## Consequences

### What Apache 2.0 buys

- **Patent grant** (Section 3). Every contributor grants every user a patent license over their contributions. The same section's termination clause discourages drive-by patent suits: a downstream user that sues the project (or any user) over its content loses their patent rights under the license. For an EDR that may invent or codify defensive primitives, this matters.
- **Enterprise adoption friction is low.** Apache 2.0 is on every major enterprise legal team's allowlist. Contrast with the GPL family, where adoption often requires case-by-case review and can be blocked outright.
- **Embeddability.** Downstream projects — including commercial EDR products — can ship Nightwatch (or its parts) without releasing their own source. The expected trade-off: stronger uptake, weaker contribute-back guarantee.
- **NOTICE preservation** (Section 4). Redistribution must preserve the `LICENSE` and any `NOTICE` file, providing a minimal attribution floor.

### What Apache 2.0 costs

- **No copyleft.** A downstream commercial fork can ship Nightwatch unchanged, or modified, without releasing their changes. If the project's goal were to force contribute-back, GPLv3 or AGPLv3 would do that; Apache 2.0 does not. Accepted: the adoption upside outweighs the loss of forced reciprocity.
- **GPLv2 incompatibility.** Apache 2.0 is compatible with GPLv3 (one-way: GPLv3 code can absorb Apache 2.0 code) but not with GPLv2. The project does not currently plan to import GPLv2 dependencies; if that changes, a superseding ADR re-evaluates.

### Source-file headers

Source files do **not** need to carry the long Apache boilerplate header. Apache 2.0 itself recommends but does not require per-file headers; many large Apache-licensed projects (Kubernetes, many gRPC files) include them, others (parts of Tailscale's open components, swift-server projects) elide them.

Nightwatch's convention:

- `LICENSE` at repo root is authoritative.
- New source files do not require a per-file boilerplate header.
- If a contributor wants to add an explicit license marker, the canonical short form is:
  ```
  // SPDX-License-Identifier: Apache-2.0
  ```
  No name, no year, no full boilerplate. SPDX identifiers are tool-friendly (license scanners, SBOM generators) and one line.

### Contributor agreement

There is no separate CLA (Contributor License Agreement). Contributions are accepted under the same Apache 2.0 license per the project's `CONTRIBUTING.md` ("inbound = outbound"). The Apache 2.0 text's Section 5 already covers this; no out-of-band agreement adds value.

### Reversibility

License switches in open-source projects are difficult in practice. Switching from Apache 2.0 later requires:

1. A superseding ADR with the new decision and reasoning.
2. Consent of every contributor whose copyright is in the codebase at the time of the switch, unless those contributions were made under a CLA that permits relicense (none are).

Treat this decision as effectively permanent.

## Alternatives considered

- **MIT** — Same effective permissions for users but lacks the patent grant. For a security tool that may invent or codify defensive primitives, the absence of an explicit patent clause is a real (if usually theoretical) gap. Rejected.
- **GPLv3** — Strong copyleft. Forces derivative works to release source. Trade-off is reduced enterprise adoption — many enterprises will not use GPLv3 code in their stacks, which constrains who pilots Nightwatch or contributes back. The project's strategic goal (broad macOS security adoption) outweighs the contribute-back guarantee. Rejected.
- **AGPLv3** — GPLv3 plus network-use clause; even SaaS use must release source. The strictest of the four. Same trade-off as GPLv3 amplified. Rejected for the same reason.
- **BSD-3-Clause / ISC** — Simpler than MIT, still no patent grant. Rejected for the same reason as MIT.
