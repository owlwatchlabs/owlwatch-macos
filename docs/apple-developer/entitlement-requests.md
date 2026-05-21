# Apple Developer entitlement requests

Single source of truth for every restricted-entitlement request Owlwatch has submitted to Apple. Records what was asked of Apple, when, the justification text submitted, and the current status.

The submission text in this file is the **exact text sent to Apple**. Edit only to fix factual errors before submission, or to add a status update after submission. Do not retroactively rewrite a submitted justification — a frozen record of what was claimed at submission time is more valuable than a polished after-the-fact version.

## Status legend

- **Drafted** — Justification text is finalized but not yet submitted to Apple. Awaiting prerequisites (paid Developer Program membership, etc.).
- **Submitted** — Submitted via [Apple's request form](https://developer.apple.com/contact/request/system-extension/) on the date noted. Apple case number recorded.
- **Approved** — Apple has granted the entitlement on the Owlwatch Team ID. The entitlement key can be added to the relevant target's `.entitlements` file.
- **Denied** — Apple has rejected. The denial reason and any re-submission plan are recorded in the section.

## Submission #1 — drafted 2026-05-19

**Project name:** Owlwatch
**Bundle ID prefix:** `com.owlwatchlabs.owlwatch.*`
**Distribution model:** Direct (Developer ID), not Mac App Store
**Source code:** https://github.com/xorxorjmp/owlwatch (Apache 2.0)
**Team ID:** captured in Apple's case record; not committed to the repository (each contributor uses their own development team locally; the project's "production" team is the one that ships signed Developer ID builds at M15).

Three entitlements requested in a single submission so the multi-week review clocks run in parallel.

### 1. `com.apple.developer.endpoint-security.client`

**Status:** Drafted — awaiting Apple Developer Program enrollment, then submission.
**Target milestones:** M8 (NOTIFY events), M9 (AUTH events), M10 (Background Task Management persistence events).
**System extension target:** `OwlwatchEndpoint` (bundle `com.owlwatchlabs.owlwatch.endpoint`).

#### Justification submitted to Apple

> **Product**
>
> Owlwatch is an open-source Endpoint Detection and Response (EDR) platform for macOS, with an iOS companion posture agent. The macOS product surfaces suspicious system behavior to the user via a menu-bar app: process executions from unsigned or revoked binaries, persistence installations, anomalous file events, and policy violations expressed as user-defined detection rules. Source code is public on GitHub under the Apache License 2.0; the project is in active development with a 15-milestone public roadmap.
>
> **Requested entitlement**
>
> `com.apple.developer.endpoint-security.client`, used by the `OwlwatchEndpoint` system extension (bundle ID `com.owlwatchlabs.owlwatch.endpoint`).
>
> **How it will be used**
>
> The system extension will subscribe to NOTIFY events for process lifecycle (`ES_EVENT_TYPE_NOTIFY_EXEC`, `_FORK`, `_EXIT`), file activity (`_OPEN`, `_CLOSE`, `_RENAME`, `_UNLINK`, `_CREATE`), code-signing events (`_CS_INVALIDATED`, `_SIGNAL`), and Background Task Management lifecycle (`_BTM_LAUNCH_ITEM_ADD`, `_BTM_LAUNCH_ITEM_REMOVE`). A later release introduces selective AUTH events for blocking unsigned executions and unauthorized persistence, with explicit user policy and a visible decision UI.
>
> **Why Endpoint Security and not an alternative**
>
> Userspace alternatives were evaluated and rejected:
>
> - `NSWorkspace` notifications do not surface file events or code-signing invalidation, and process events are limited to application launches.
> - `proc_pidinfo` polling misses short-lived processes and provides no real-time guarantee.
> - The audit pipe (`/dev/auditpipe`) is deprecated; Apple has stated Endpoint Security is its replacement.
> - Kernel Extensions are deprecated for new development and gated behind reduced-security mode on Apple Silicon.
>
> Endpoint Security is the only API on modern macOS that provides the event coverage, fidelity, and real-time guarantees required for EDR-grade detection.
>
> **User value**
>
> The macOS user gains visibility into the kinds of post-compromise activity that commercial EDRs surface (malware execution, persistence implants, lateral movement primitives) in a tool whose source code they can audit. Owlwatch complements but does not replace XProtect, Gatekeeper, or commercial EDR products.

---

### 2. `com.apple.developer.networking.networkextension` → `content-filter-provider`

**Status:** Drafted — awaiting Apple Developer Program enrollment, then submission.
**Target milestone:** M7 (Network Extension filter provider).
**System extension target:** `OwlwatchNetwork` (bundle `com.owlwatchlabs.owlwatch.network`).

#### Justification submitted to Apple

> **Product**
>
> (Same product description as the Endpoint Security request above.)
>
> **Requested entitlement**
>
> `com.apple.developer.networking.networkextension` with the `content-filter-provider` value, used by the `OwlwatchNetwork` system extension (bundle ID `com.owlwatchlabs.owlwatch.network`).
>
> **How it will be used**
>
> The filter data provider subscribes to outbound and inbound flows for the host, attributes each flow to the originating process via `NEFilterFlow.sourceAppIdentifier` and `NEFilterFlow.sourceAppAuditToken`, and emits the flow records to the Owlwatch daemon for correlation with Endpoint Security process events. Flows are observed, not blocked, in initial releases; blocking by user-defined policy is introduced as a later milestone with an explicit decision UI.
>
> **Why Network Extension content filtering and not an alternative**
>
> - `Network.framework` and `nw_path_evaluator` operate per-app inside the app's own address space and cannot see system-wide flows from other processes.
> - Berkeley Packet Filter (BPF) and `libpcap` provide raw packet visibility but no process attribution.
> - `pf` rules can block traffic but cannot introspect with process attribution and cannot run as a userspace observer.
>
> Network Extension content filtering is the only userspace API on modern macOS that provides system-wide flow visibility with process attribution.
>
> **User value**
>
> The user can see and reason about every outbound connection their machine makes — including connections from system daemons that command-line `netstat` does not attribute correctly — and identify suspicious destinations (rare TLDs, recently-registered domains, known indicator IPs) in the same UI that surfaces process and file events.

---

### 3. `com.apple.developer.networking.networkextension` → `dns-proxy`

**Status:** Drafted — awaiting Apple Developer Program enrollment, then submission.
**Target milestone:** M12 (DNS proxy and heuristics).
**System extension target:** `OwlwatchDNS` (bundle `com.owlwatchlabs.owlwatch.dns`).

#### Justification submitted to Apple

> **Product**
>
> (Same product description as above.)
>
> **Requested entitlement**
>
> `com.apple.developer.networking.networkextension` with the `dns-proxy` value, used by the `OwlwatchDNS` system extension (bundle ID `com.owlwatchlabs.owlwatch.dns`).
>
> **How it will be used**
>
> The DNS proxy provider intercepts DNS queries before they reach `mDNSResponder`, records query name, type, and the originating process, optionally forwards to a user-selected resolver, and applies suspicious-domain heuristics (DGA scoring, recently-registered TLDs, NXDOMAIN burst patterns). Queries are logged; blocking is policy-driven and opt-in with an explicit decision UI.
>
> **Why DNS proxy and not an alternative**
>
> The content-filter-provider entitlement sees DNS traffic as opaque UDP/TCP flows on port 53 and cannot decode queries reliably across encrypted DNS, fragmented responses, or the system resolver's caching behavior. The DNS proxy API delivers parsed query records and lets the system resolver continue handling caching, DNSSEC, and DoH/DoT correctly.
>
> **User value**
>
> DNS is the highest-signal observability channel for early-stage compromise: command-and-control callbacks, DGA-based malware, and exfiltration over DNS all surface in lookup patterns. Surfacing them to the user is a defensive primitive most commercial EDRs charge enterprise prices for.

---

## What happens after submission

1. Apple sends an automated confirmation email with a case number. Record the case number in the section's **Status** line as `Submitted YYYY-MM-DD, case #XXXXXXXX`.
2. Apple may respond with follow-up questions (typical for ES). Record each round-trip in a new sub-section under the entitlement, labelled by date.
3. On approval, flip **Status** to **Approved YYYY-MM-DD**, add the entitlement key to the relevant target's `.entitlements` file in a follow-up PR, and reference this document in that PR.
4. On denial, record the reason verbatim, draft a response or revised submission if appropriate, and link to the response.

## Why this file is in the repository

Three reasons this is committed source-of-truth rather than living in personal notes:

1. **Audit trail.** A future contributor reviewing an entitlement-bearing PR can read the exact case Apple was sold on and check whether the PR matches that scope. Drift between what Apple was told and what the code does is a risk both legally (Developer Program License Agreement section 3.3) and practically (Apple revokes Team IDs for misuse).
2. **Resubmission.** If Apple denies and a new submission is needed, the previous justification text is the starting point.
3. **Onboarding.** A new maintainer arriving at M7+ work needs to know which entitlements were requested, when, and why, without spelunking through the personal email of whoever submitted them.
