# Nightwatch Roadmap

Nightwatch is developed through short, reviewable milestones. `main` remains shippable; milestone work lands through pull requests tied to issues and CI status checks.

## Milestones

| Milestone | Name | Deliverable |
| --- | --- | --- |
| M0 | Foundation | Repository skeleton, CI, signed empty apps, demo infrastructure, initial ADRs |
| M1 | Process inspector | `NWProcess` and `nwctl ps` with process metadata, hierarchy, arguments, libraries, open files |
| M2 | Binary parser | `NWBinary` for Universal and Mach-O parsing, dependencies, symbols, entropy, packing signals |
| M3 | Code signing | `NWCodeSigning` for apps, binaries, disk images, packages, notarization, revocation handling |
| M4 | Network state | `NWNetwork` host-side socket and connection snapshots with process attribution |
| M5 | Persistence enumerator | `NWPersistence` and a user surface for installed auto-start items |
| M6 | Log monitoring | `NWLog` ingestion and structured log event filters |
| M7 | Network monitoring | `NightwatchNetwork` Network Extension filter provider |
| M8 | Endpoint Security | `NightwatchEndpoint` System Extension with NOTIFY events |
| M9 | ES auth and muting | AUTH event decisions, muting, deadlines, allow/block UX |
| M10 | Persistence monitor | Real-time persistence detection feeding rules |
| M11 | Mic and webcam monitor | `NWDevices` with process attribution for device access |
| M12 | DNS monitor | `NightwatchDNS` DNS proxy and suspicious-domain heuristics |
| M13 | Detection engine and rules library | `NWRules`, ADR-0003, schema validation, fixtures, initial MITRE ATT&CK coverage |
| M14 | iOS companion | Posture agent, App Attest, paired-Mac alert dashboard |
| M15 | v1.0 release | Notarized DMG, signed installer, release notes, demo video |

## Current Status

M0 is in progress. The repository skeleton is present; build targets, CI, ADRs, and demo assets are pending follow-up PRs.

