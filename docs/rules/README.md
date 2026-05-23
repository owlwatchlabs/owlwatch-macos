# Owlwatch detection rules

This directory carries the **schema** that defines what a rule may contain. The **rules themselves** live in [`packages/Rules/`](../../packages/Rules/) — one YAML file per rule.

## Files

- [`rule-schema.json`](rule-schema.json) — JSON Schema (draft 2020-12) for the rule format. The loader in [`OWRules`](../../packages/Sources/OWRules/) validates every rule against this schema at parse time.

## Why YAML, why a schema, why here?

See [ADR-0004 — Rules engine format](../adr/0004-rules-engine-format.md) for the full rationale. Short version:

- **YAML** for authoring ergonomics (comments + multi-line strings beat JSON for rule descriptions).
- **JSON Schema** so malformed rules fail loudly at load time instead of silently mismatching at evaluation.
- **`docs/rules/`** (not `Sources/`) so the schema is discoverable by external tools (IDE YAML extensions, GitHub) and by contributors browsing the repo.

## Contributing a rule

1. Pick a MITRE ATT&CK technique ID. The id of your rule follows the convention `T<MITRE-ID>-<short-slug>` (e.g. `T1546.004-launchagent-in-downloads`).
2. Drop a `<id>.yml` file into `packages/Rules/`.
3. Validate it locally: `owlwatch scan --rules packages/Rules --dry-run` (parses + schema-checks the rule but doesn't evaluate it against the system).
4. Add a test fixture under `packages/Tests/OWRulesTests/Fixtures/` that exercises the rule against synthetic data, plus a unit test asserting the rule fires (or doesn't fire) against that fixture.

The schema is the source of truth for what a rule may contain. If you need a predicate or field that isn't in the schema yet, that's an engine change — propose it via an issue before the rule PR.
