# ADR-0004: Rules engine format — declarative YAML with JSON Schema validation

## Status

Accepted — 2026-05-23.

## Context

M13 introduces Owlwatch's detection rules engine and a tested rule library tagged to MITRE ATT&CK. Three load-bearing decisions had to be made before any code could land:

1. **Rule format.** How are rules expressed — Swift code, a custom DSL, or a declarative document?
2. **Distribution.** Is the rule library compiled into the binary, shipped as files alongside it, or fetched at runtime?
3. **Validation.** How do we catch malformed rules before they reach production — at compile time, at parse time, or at runtime?

The choice cascades. A Swift-code format gives compile-time safety but forces a rebuild for every rule change and locks third parties out of contributing rules without a Swift toolchain. A declarative document is editable by anyone with a text editor but requires a parser, a schema, and a runtime validation story. The wrong choice here would either gate the contribution surface unnecessarily or smuggle invalid rules into the binary.

Two adjacent constraints shape the answer:

- **Owlwatch is open-source and contributor-friendly.** The rule library is *the* artifact that benefits most from external contribution — security researchers can submit rules without touching Swift if the format is declarative. Compare YARA, Sigma, and Falco, all of which ship as text rules and have thriving community libraries; compare Apple's own `MetricKit` rules, which are Swift code and have effectively zero community contribution.
- **MITRE ATT&CK is a stable, document-shaped taxonomy.** Tagging rules with technique IDs (`T1546.004`, `T1059.004`, ...) maps cleanly onto declarative fields, not onto code annotations. The ROADMAP entry for M13 explicitly calls out "schema validation, fixtures, initial MITRE ATT&CK coverage" — that framing points at documents, not code.

Inside the declarative-document branch, the YAML-vs-JSON axis matters less for the engine and more for authoring ergonomics: YAML supports comments and block strings (useful for the `description:` field), JSON does not. Both parse to the same in-memory `Rule` value.

## Decision

The Owlwatch rules engine adopts the following:

### Rule format: declarative YAML

Each rule is a single YAML document with this shape:

```yaml
id: T1546.004-launchagent-in-downloads
name: Launch agent installed in ~/Downloads
description: |
  A LaunchAgent plist installed in a user-writable download path is a
  common persistence technique. Most legitimate installers drop agents
  to ~/Library/LaunchAgents via signed bundles; agents directly placed
  in download or temp paths are suspicious.
mitre: T1546.004
severity: high
when:
  source: launch_service
  match:
    executable_path:
      starts_with: ~/Downloads/
evidence:
  - plist_path
  - executable_path
```

Required fields: `id`, `name`, `severity`, `when.source`. All others are optional.

### Predicate language

The `when.match` block is an implicit AND of per-field predicates. Each predicate is one of:

| Predicate | Example | Semantics |
|---|---|---|
| `equals: V` | `equals: root` | Exact string match |
| `not_equals: V` | `not_equals: /System/...` | Negated exact match |
| `starts_with: V` | `starts_with: /tmp/` | Prefix match |
| `ends_with: V` | `ends_with: .dylib` | Suffix match |
| `contains: V` | `contains: temp` | Substring match |
| `matches: V` | `matches: '^[A-Z]{2}\d+$'` | NSRegularExpression-compatible regex |
| `in: [V1, V2, ...]` | `in: [bash, sh, zsh]` | Set membership |
| `exists: true` / `exists: false` | `exists: true` | Field is non-nil / nil |
| `is_true: true` / `is_false: true` | `is_true: true` | Boolean field is exactly true / false |

A field name maps to a property accessor on the data source's item type (declared per-source). The engine errors on unknown field names rather than silently skipping — typos in a rule should not become silent no-ops.

OR / NOT composition lands in a later slice if rule authors need it. M13.1 ships AND-only.

### Data sources

M13.1 ships three sources:

- `process` — iterates the `OWProcess.all(...)` snapshot. Fields: `pid`, `parent_pid`, `name`, `path`, `user_id`, `arguments`.
- `launch_service` — iterates `OWPersistence.launchServices()`. Fields: `plist_path`, `scope`, `label`, `executable_path`, `arguments`, `run_at_load`, `runs_as_root`, `is_disabled`.
- `login_item` — iterates `OWPersistence.loginItems()`. Fields: `identifier`, `developer_name`, `team_identifier`, `bundle_identifier`, `parent_identifier`, `url`, `is_enabled`.

Network, binary, signature, and log-correlation sources follow in M13.2–M13.4. Each new source extends the predicate vocabulary in the engine; the rule format stays unchanged.

### Distribution: bundled in the source tree, copied into the build

The rule library ships under `packages/Rules/` as one YAML file per rule. The CLI loads them from a configurable directory (default: a path discovered via `Bundle.module` for the SPM target, or `--rules <dir>` to override).

The library is **version-locked to the engine**: a release of `owlwatch 0.11.0-m13` ships with a specific snapshot of `packages/Rules/`. A future M13.x or M14 can introduce update channels; for M13.1 the rules are part of the same artifact as the engine.

### Validation: JSON Schema at parse time

A JSON Schema document at `docs/rules/rule-schema.json` defines the rule's structural contract. The loader validates every YAML rule against the schema and rejects malformed rules with a precise error message pointing at the offending field. The schema is the single source of truth for what a rule may contain — the in-Swift `Rule` decoder matches the schema exactly.

The schema lives in `docs/` (not `Sources/`) so that contributors browsing the repo find it without spelunking through Swift sources, and so that external tools (IDE YAML extensions, GitHub's YAML schema discovery) can reference it.

### YAML parser: Yams

Yams (1.6k★, MIT, maintained by the Realm team and the SwiftLint project) is the de-facto Swift YAML library. We add it as a single SPM dependency — Owlwatch's second non-Apple dependency after swift-argument-parser. Yams is implementation-stable, has no transitive dependencies, and is already the parser SwiftLint / SwiftFormat / Sourcery use, so its bus-factor concern is low.

## Consequences

**Buys:**

- Third-party rule contributions are a YAML pull request. No Swift toolchain, no rebuild.
- Schema validation rejects malformed rules at load time with structured errors — typos and missing fields can't reach the evaluator.
- MITRE ATT&CK tags are first-class fields, not free-form strings buried in code.
- Comments in rule files let contributors explain the *why* of a detection, not just the *what*.
- The rule library is auditable: a code review of new detections is a YAML diff, not a Swift diff.

**Costs:**

- One new SPM dependency (Yams). Future Owlwatch upgrades have to track Yams's release cadence.
- A predicate language re-invents what regular code expresses naturally. Complex detections that need imperative logic (multi-stage correlation, time-window joins) won't fit cleanly and will need engine-side support landing case-by-case.
- A schema-versioning story will be needed eventually. M13.1 ships schema v1; v2 is a future ADR.

**Reversibility:**

- Moving from YAML to JSON is mechanical (`yq -o=json` on the existing library).
- Moving from declarative to code-based is a one-way street: every existing rule has to be rewritten. The cost of that grows with the library size.
- The Yams dependency is replaceable in principle (any YAML 1.1 parser would work) but the swap would touch every load-site.

## Alternatives considered

### Swift-code rules

Rules as Swift functions over the data source types, registered into a global `RuleRegistry`. Compile-time safety, free use of Swift's type system, free refactoring.

Rejected because every rule change forces a Swift rebuild; third parties without a Swift toolchain are gated out; the rule library can't be edited at the deploy site (a customer can't ship one-off custom detections without rebuilding the binary); and code-shaped rules don't accept MITRE technique tags ergonomically. The compile-time safety is real but is recovered through schema validation in the chosen approach.

### Custom DSL

A purpose-built language for detections (e.g., `process where path startswith "/tmp/"`). Maximally expressive at the rule-author surface; minimally hostile to non-Swift contributors.

Rejected on bus-factor grounds. A custom DSL requires its own lexer, parser, type checker, error-message infrastructure, IDE support, and documentation. The engineering surface for that is larger than the entire engine. Industry precedent (YARA, Sigma) is to use a structured format that *looks* declarative and pushes complexity into the engine, not into a parser.

### JSON

Same in-memory shape as YAML, but JSON syntax. Foundation-only, no extra dependency, faster parser.

Rejected on authoring ergonomics. Rules carry multi-line `description:` fields and benefit from `#` comments explaining *why* a detection exists. JSON supports neither cleanly. The Yams dependency is a one-time cost; lifetime authoring friction is a daily cost.

### Lua / JavaScript / Starlark rules

Rules as scripts in a sandboxed embedded language. The most flexible option; matches Falco's choice.

Rejected for now. Embedding an interpreter adds an attack surface (a malformed rule shouldn't be able to crash the engine), a sandbox responsibility, and a substantial library footprint. The detection patterns M13.1–M13.4 cover are well-served by declarative predicates; the case for an interpreter would only arise if multi-stage correlation rules turn out to be load-bearing, at which point a future ADR can revisit.

### Plist / TOML

Plist is Apple-native and parsable with Foundation alone, but is not human-readable as a rule format (the verbose XML form is hostile; the binary form unreadable). TOML is friendly but lacks the structured `match` block ergonomics YAML provides. Neither matches the industry precedent (YARA/Sigma/Falco all use YAML-shaped structures).
