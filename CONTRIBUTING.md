# Contributing to Nightwatch

Nightwatch accepts focused contributions that improve the macOS EDR, iOS posture agent, build system, documentation, or detection library.

## Workflow

1. Open or reference an issue before starting non-trivial work.
2. Create a short-lived branch from `main`.
3. Keep changes scoped to one reviewable unit.
4. Add or update tests with the change.
5. Update documentation when behavior, APIs, rules, or operational requirements change.
6. Open a pull request and complete the PR template.

## Branch Names

- Features: `feat/m{milestone}-{slug}`
- Fixes: `fix/{slug}`
- Refactors: `refactor/{slug}`
- Documentation: `docs/{slug}`
- CI/build: `ci/{slug}` or `build/{slug}`
- Rules: `rules/{category}-{slug}`

## Commits

Use Conventional Commits:

```text
feat(process): map sockets to PIDs via proc_pidinfo
```

Commit messages and public artifacts describe the product change, not personal learning process.

## Pull Requests

PRs should explain:

- What changed
- Why it changed
- Approach
- How it was tested
- Risk and rollback
- Screenshots or recordings for UX changes

Keep PRs under 400 changed lines when practical. Split work before it becomes difficult to review.

## Contributing Detection Rules

Rules live under `rules/{category}/` and must include:

- Nightwatch-native YAML schema version
- Immutable rule ID
- Name, description, category, severity, and verdict
- MITRE ATT&CK mapping when applicable
- References when public documentation supports the behavior
- At least one fixture under `rules/tests/{rule-id-slug}/`

Rules must not include live malware, proprietary feed data, customer-identifying values, or undisclosed attacker techniques that would aid evasion.

## Testing

Run the relevant local checks before opening a PR. The M0 command surface is planned as:

```bash
make test
make lint
```

Rule PRs must pass `rulectl test ./rules` once `rulectl` lands in M13.

