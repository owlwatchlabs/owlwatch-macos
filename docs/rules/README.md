# Owlwatch detection rules

This directory carries the **schema** that defines what a rule may contain. The **rules themselves** live in [`packages/Rules/`](../../packages/Rules/) — one YAML file per rule.

## Files

- [`rule-schema.json`](rule-schema.json) — JSON Schema (draft 2020-12) for the rule format. The loader in [`OWRules`](../../packages/Sources/OWRules/) enforces every constraint in this schema at parse time.

## Why YAML, why a schema, why here?

See [ADR-0004 — Rules engine format](../adr/0004-rules-engine-format.md) for the full rationale. Short version:

- **YAML** for authoring ergonomics (comments + multi-line strings beat JSON for rule descriptions).
- **JSON Schema** so malformed rules fail loudly at load time instead of silently mismatching at evaluation.
- **`docs/rules/`** (not `Sources/`) so the schema is discoverable by external tools (IDE YAML extensions, GitHub) and by contributors browsing the repo.

## Rule anatomy

```yaml
id: T1546.004-launchagent-in-downloads      # required, [A-Za-z0-9._-]+
name: Launch agent installed in ~/Downloads  # required, non-empty
description: |                                # optional, free-form
  A LaunchAgent plist installed in a user-writable download path...
mitre: T1546.004                              # optional, T<NNNN>[.<NNN>]
severity: high                                # required: info | low | medium | high | critical
when:
  source: launch_service                      # required, see Data sources below
  match:                                      # optional, ANDed predicates
    executable_path:
      starts_with: /Users/
    plist_path:
      contains: /Downloads/
evidence:                                     # optional, fields copied into findings
  - plist_path
  - executable_path
```

**Strict at load time.** Unknown root keys, unknown `when:` keys, malformed MITRE IDs, IDs with spaces, duplicate evidence fields, and field names outside the source's vocabulary are all rejected with structured errors. The loader fails the whole file rather than silently dropping the unknown bits.

## Predicate vocabulary

Inside `when.match.<field>:`, each field's value is a predicate. A bare scalar is shorthand for `equals`.

| Predicate | Example | Semantics |
|---|---|---|
| `equals: V` (or bare `V`) | `name: bash` | Exact string match |
| `not_equals: V` | `path: { not_equals: /usr/bin/ssh }` | Negated exact match (missing fields don't match) |
| `starts_with: V` | `path: { starts_with: /tmp/ }` | String prefix |
| `ends_with: V` | `path: { ends_with: .dylib }` | String suffix |
| `contains: V` | `arguments: { contains: --no-verify }` | Substring (also works against `arguments` arrays — element values are joined with `' '` for matching) |
| `matches: V` | `path: { matches: '^(/tmp/\|/var/tmp/)' }` | `NSRegularExpression`-compatible regex, including lookahead / lookbehind |
| `in: [V1, V2, ...]` | `name: { in: [sh, bash, zsh] }` | Set membership |
| `exists: true \| false` | `developer_name: { exists: false }` | Field is non-nil / nil (or non-empty / empty for array fields) |
| `is_true: true` / `is_false: true` | `is_enabled: { is_true: true }` | Boolean field equals exactly `true` / `false` |
| `greater_than: N` | `max_section_entropy: { greater_than: 7.5 }` | Strict `>` over numeric fields |
| `less_than: N` | `local_port: { less_than: 1024 }` | Strict `<` over numeric fields |

**ANDed.** All predicates in one `match:` block must hold for the rule to fire. OR / NOT composition is deferred to a future slice.

**Case-sensitive.** All string predicates are case-sensitive. For case-insensitive matching, use `matches` with an `(?i)` prefix.

## Data sources

The `when.source` value picks which dataset the rule iterates. Each source has a fixed field vocabulary — referencing a field outside it is a load-time error.

### `process`

Iterates `OWProcess.all(...)`.

| Field | Type | Notes |
|---|---|---|
| `pid` | integer | Process ID |
| `parent_pid` | integer | PPID |
| `name` | string | Last path component, or kernel-supplied name |
| `path` | string? | Executable path. May be missing for processes the user can't `proc_pidpath` |
| `user_id` | integer | Effective UID |
| `arguments` | string[]? | argv. Captured only when at least one loaded rule references `arguments` |

### `launch_service`

Iterates `OWPersistence.launchServices()`.

| Field | Type | Notes |
|---|---|---|
| `plist_path` | string | Absolute path to the .plist |
| `scope` | string | `platform_daemon` / `platform_agent` / `system_daemon` / `system_agent` / `user_agent` |
| `label` | string? | `Label` key from the plist |
| `executable_path` | string? | First entry of `Program` or `ProgramArguments` |
| `arguments` | string[] | `ProgramArguments` (or empty) |
| `run_at_load` | bool | `RunAtLoad` |
| `runs_as_root` | bool | True when scope is a `*_daemon` |
| `is_disabled` | bool | `Disabled` |

### `login_item`

Iterates `OWPersistence.loginItems()`.

| Field | Type | Notes |
|---|---|---|
| `identifier` | string? | BTM identifier |
| `developer_name` | string? | Display name from the developer-signed bundle |
| `team_identifier` | string? | Apple Developer Team ID |
| `bundle_identifier` | string? | `CFBundleIdentifier` |
| `parent_identifier` | string? | Parent bundle for embedded login items |
| `url` | string? | `LaunchPath` / file URL |
| `is_enabled` | bool | From the `Disposition` bitfield |

### `network`

Iterates `OWNetwork.snapshot()`.

| Field | Type | Notes |
|---|---|---|
| `pid` | integer | Owning process |
| `fd` | integer | File descriptor |
| `family` | string | `ipv4` / `ipv6` / `unix` |
| `protocol_name` | string | `tcp` / `udp` / `unix_stream` / `unix_datagram` |
| `local_address` | string? | Bind address (`0.0.0.0`, `::`, `127.0.0.1`, …) |
| `local_port` | integer? | Bind port |
| `remote_address` | string? | Peer address (nil for listeners) |
| `remote_port` | integer? | Peer port |
| `tcp_state` | string? | `listen` / `established` / `close_wait` / … |
| `is_listener` | bool | True for any socket in `LISTEN` state |

### `kernel_extension`

Iterates `OWPersistence.kernelExtensions()`.

| Field | Type | Notes |
|---|---|---|
| `bundle_path` | string | Absolute path to the .kext bundle |
| `bundle_identifier` | string? | `CFBundleIdentifier` |
| `short_version` | string? | `CFBundleShortVersionString` |
| `bundle_version` | string? | `CFBundleVersion` |
| `executable_name` | string? | `CFBundleExecutable` |
| `executable_path` | string? | Resolved path to the kext's Mach-O |
| `scope` | string | `platform` (Apple, `/System/Library/Extensions`) / `system` (third-party, `/Library/Extensions`) |

### `binary`

Iterates `BinarySummary`s built by parsing each unique executable in the process snapshot via `OWBinary.parse(at:)`. Heavy — gated by `--scope` in the CLI.

| Field | Type | Notes |
|---|---|---|
| `path` | string | Executable path |
| `is_universal` | bool | Universal (fat) binary |
| `slice_count` | integer | Number of Mach-O slices |
| `architectures` | string[] | Per-slice arch names |
| `linked_dylibs` | string[] | `LC_LOAD_DYLIB`-family install names (deduped across slices) |
| `rpaths` | string[] | `LC_RPATH` entries |
| `has_rwx_segment` | bool | True if any segment in any slice has VM_PROT_WRITE + VM_PROT_EXECUTE |
| `max_section_entropy` | double | Highest section Shannon entropy (0..8) |

### `signature`

Iterates `SignatureSummary`s built by inspecting each unique executable via `OWCodeSigning.inspect(at:)`. Heavy — gated by `--scope` in the CLI.

| Field | Type | Notes |
|---|---|---|
| `path` | string | Executable path |
| `is_signed` | bool | A code signature is present |
| `is_valid` | bool | Structural validity (CDHash matches sealed code) |
| `signature_type` | string | `unsigned` / `adhoc` / `developer_id` / `apple_developer` / `app_store` / `apple` / `unknown` |
| `identifier` | string? | Signing identifier (`com.apple.ls`, …) |
| `team_identifier` | string? | Apple Developer Team ID |
| `cd_hash` | string? | Hex form of the CDHash |
| `authorities` | string? | Certificate-chain common names, joined with ` \| ` |
| `flags` | string? | `SecCodeSignatureFlags` symbolic form (`runtime library-validation`, …) |
| `has_hardened_runtime` | bool | `runtime` flag set |
| `hardened_runtime_version` | string? | Decoded from `runtime-version` (only when hardened runtime present) |
| `is_stapled_for_notarization` | bool | Embedded notarization ticket present |
| `entitlements_count` | integer | Number of entries in the entitlements blob |

## Bounded scanning

By default, `owlwatch scan` parses every running executable's Mach-O + signature — minutes on a typical macOS host. Use `--scope` to restrict the binary and signature passes to specific path prefixes:

```
owlwatch scan --scope /Users/ --scope /Applications/
```

The `process`, `launch_service`, `login_item`, `network`, and `kernel_extension` sources always see the full snapshot regardless of `--scope`. Sources whose rules never get loaded are skipped entirely.

## Contributing a rule

1. Pick a MITRE ATT&CK technique ID. The id of your rule follows the convention `T<MITRE-ID>-<short-slug>` (e.g. `T1546.004-launchagent-in-downloads`).
2. Drop a `<id>.yml` file into [`packages/Rules/`](../../packages/Rules/).
3. Validate it locally: `owlwatch scan --rules packages/Rules --dry-run` (parses + schema-checks every rule but doesn't evaluate them against the system).
4. Add a positive-case golden test to [`packages/Tests/OWRulesTests/OWRulesGoldenTests.swift`](../../packages/Tests/OWRulesTests/OWRulesGoldenTests.swift): a synthetic snapshot designed to fire your rule plus the expected finding count / target ID. The clean-baseline test in the same file will fail if your rule accidentally also fires on benign system state.

The schema is the source of truth for what a rule may contain. If you need a predicate or field that isn't there yet, that's an engine change — open an issue or PR against `OWRules` before the rule PR.
