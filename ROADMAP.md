# Owlwatch Roadmap

Owlwatch is developed through short, reviewable milestones. `main` remains shippable; milestone work lands through pull requests tied to issues and CI status checks.

## Milestones

| Milestone | Name | Deliverable |
| --- | --- | --- |
| M0 | Foundation | Repository skeleton, CI, signed empty apps, demo infrastructure, initial ADRs |
| M1 | Process inspector | `OWProcess` and `owlwatch ps` with process metadata, hierarchy, arguments, libraries, open files |
| M2 | Binary parser | `OWBinary` for Universal and Mach-O parsing, dependencies, symbols, entropy, packing signals |
| M3 | Code signing | `OWCodeSigning` for apps, binaries, disk images, packages, notarization, revocation handling |
| M4 | Network state | `OWNetwork` host-side socket and connection snapshots with process attribution |
| M5 | Persistence enumerator | `OWPersistence` and a user surface for installed auto-start items |
| M6 | Log monitoring | `OWLog` ingestion and structured log event filters |
| M7 | Network monitoring | `OwlwatchNetwork` Network Extension filter provider |
| M8 | Endpoint Security | `OwlwatchEndpoint` System Extension with NOTIFY events |
| M9 | ES auth and muting | AUTH event decisions, muting, deadlines, allow/block UX |
| M10 | Persistence monitor | Real-time persistence detection feeding rules |
| M11 | Mic and webcam monitor | `OWDevices` with process attribution for device access |
| M12 | DNS monitor | `OwlwatchDNS` DNS proxy and suspicious-domain heuristics |
| M13 | Detection engine and rules library | `OWRules`, ADR-0004, schema validation, fixtures, initial MITRE ATT&CK coverage |
| M14 | iOS companion | Posture agent, App Attest, paired-Mac alert dashboard |
| M15 | v1.0 release | Notarized DMG, signed installer, release notes, demo video |
| M16 | App UI integration | Status dashboard + per-source windows (Processes, Network, Logs, Binary Inspector) + menu-bar polish — every CLI surface from M1–M11 gets a GUI affordance |

## Current Status

M0 is in progress. The repository skeleton is present; build targets, CI, ADRs, and demo assets are pending follow-up PRs.

