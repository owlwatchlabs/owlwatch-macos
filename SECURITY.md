# Security Policy

Nightwatch is security software. Reports that could affect user safety, system integrity, signing, update delivery, IPC boundaries, rule loading, or data protection should be handled through coordinated disclosure.

## Reporting a Vulnerability

Do not open a public issue for suspected vulnerabilities. Use GitHub Security Advisories when available, or contact the maintainers through the private security channel that will be published before the first public release.

Include:

- Affected component and version or commit
- Reproduction steps
- Impact assessment
- Logs, crash reports, or proof of concept where safe to share
- Any known exploitation or public disclosure status

## Disclosure Timeline

Nightwatch follows a 90-day coordinated-disclosure policy by default. Shorter or longer timelines may be used when active exploitation, user risk, ecosystem coordination, or vendor dependencies require it.

## Scope

In scope:

- Privilege escalation
- Unauthorized IPC access
- Code-signing or entitlement validation bypasses
- Rule-loading bypasses or unsafe parsing
- Sensitive event data exposure
- Update, packaging, signing, or notarization weaknesses
- Denial of service in security-critical components

Out of scope:

- Social engineering
- Vulnerabilities requiring already-compromised maintainer credentials
- Scanner-only findings without practical impact
- Reports involving live malware samples sent through public channels

## Data Handling

Nightwatch will not include outbound telemetry without explicit opt-in. Reports should avoid customer-identifying data and should not include live malware samples unless a private handling process has been agreed.

