# Architecture Decision Records (ADRs)

ADRs capture significant architectural decisions for Owlwatch — what was decided, why, and what the alternatives were. They form the durable record of why the project is shaped the way it is.

## Filename format

Each ADR is a single Markdown file named `NNNN-short-slug.md`, where `NNNN` is a zero-padded 4-digit sequence (`0001`, `0002`, ...). Numbers are assigned in the PR that introduces the ADR and never reused.

## Sections

Use these headings, in this order:

1. **Status** — `Proposed`, `Accepted — YYYY-MM-DD`, `Superseded by ADR-NNNN`, or `Deprecated`.
2. **Context** — what forced the decision; what would happen if no decision were made.
3. **Decision** — the decision itself, in actionable detail.
4. **Consequences** — what this buys, what it costs, reversibility.
5. **Alternatives considered** — what else was on the table and why each was not chosen.

The "Alternatives considered" section is load-bearing: an ADR without it is a press release, not a decision record. Reviewers should be able to read it and understand why the rejected paths were rejected — not just that they were.

## Lifecycle

- A new ADR opens in the PR that makes the decision. It is never written after the fact for already-merged work.
- An ADR is **never edited** after merging except to flip its **Status** to `Superseded by ADR-NNNN` or `Deprecated`. The body stays as written so the record is honest about what was decided at the time.
- When a decision changes, write a new ADR that supersedes the old one and update the old ADR's Status to point at the new one.

## Index

- [0001 — Tech stack lock-in](0001-tech-stack-lock-in.md)
- [0002 — License: Apache 2.0](0002-license.md)
- [0003 — Rename project to Owlwatch and adopt `com.owlwatchlabs.owlwatch.*` bundle IDs](0003-rename-to-owlwatch.md)
- [0004 — Rules engine format: declarative YAML with JSON Schema validation](0004-rules-engine-format.md)
