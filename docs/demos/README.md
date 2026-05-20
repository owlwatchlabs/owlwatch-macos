# Demos

Source-controlled scripts that record Nightwatch's **command-line and terminal surfaces** — the event console and the `nwctl` CLI — to GIFs and MP4s. Every demo asset for these surfaces that appears in `README.md`, the project website, or release notes traces back to a script in this directory.

Demos of the **macOS menu-bar app** and **iOS companion** are recorded separately (screen recording, not terminal capture) — see the "GUI surfaces" section below.

## Why script-driven recordings

Hand-recorded demos drift. Someone records a polished take, ships it, and three releases later the menu items have moved, the prompt is different, and the GIF embeds a stale narrative. A scripted demo regenerates from a single command and stays current as long as someone runs the script before each release.

Scripted demos also let reviewers see the *script*, not just the artifact: a PR that updates a demo includes the diff of what changed, not an opaque binary swap.

## Tool: VHS (for CLI and TUI surfaces)

[`vhs`](https://github.com/charmbracelet/vhs) by Charm is the recorder. It reads a `.tape` file (a small DSL of `Type`, `Sleep`, `Enter`, `Show`, etc.), drives a headless terminal, and emits a GIF or MP4.

Install on macOS via Homebrew:

```bash
brew install vhs
```

`vhs` itself depends on `ttyd` and `ffmpeg`; both come along with the Homebrew formula.

**VHS only records terminals.** Everything driven through a `.tape` file must be a CLI command or a terminal-based TUI (TUI = full-screen terminal UI like `htop`, `k9s`, `lazygit`). VHS cannot drive AppKit windows, SwiftUI views, or anything else that lives outside the terminal.

## Convention (`.tape` files)

- One `.tape` file per CLI/TUI surface. Current files: `nwctl.tape`, `console.tape`. Add more as new terminal surfaces ship.
- Each `.tape` declares an explicit `Output` path under `docs/demos/out/` (gitignored — see below).
- `Set` directives at the top of each tape pin font, size, theme, and frame rate so output is reproducible across machines.
- A comment header on every `.tape` describes the user story the demo tells in one or two sentences and lists the regeneration command.

## Output handling

The generated GIFs and MP4s live under `docs/demos/out/` and **are not committed**. Reasons:

- Binary diffs in git blow up the repo size with every re-record.
- The point of script-driven demos is that the script is the source of truth; the artifact can always be regenerated.

When a demo is needed for a release, the release process runs `make demos` (added when M1 lands real behavior) which regenerates everything under `out/` and uploads the chosen artifacts to the GitHub Release.

Add `docs/demos/out/` to `.gitignore` the moment the first real recording lands — for now the directory does not exist on disk.

## GUI surfaces (menu-bar app, iOS companion)

VHS does not record GUI applications. The macOS menu-bar app (M2–M3 onward) and the iOS companion (M14) are recorded with screen capture, not tape scripts:

- **macOS menu-bar app** — record with **QuickTime Screen Recording** (`Cmd+Shift+5`), or programmatically with `screencapture -v` for short clips. A driver script under `docs/demos/menubar/` lands when M2 ships the first meaningful menu-bar surface.
- **iOS companion** — record with `xcrun simctl io booted recordVideo demo.mp4` against a running simulator. Lands when M14 ships.

Both are inherently less reproducible than VHS tapes — there's no "run a script, get the same recording" equivalent. The mitigation is a written *recording recipe* (which simulator, which menu items to click, in what order) committed alongside the resulting MP4, so a re-record is a checklist someone can follow.

## State at M0

The two `.tape` files in this directory are **placeholders**. They reference behavior that does not yet exist (`nwctl ps`, the event console) and will not produce useful recordings until the milestones that introduce that behavior ship:

| Tape | Surface type | Real behavior available at |
|---|---|---|
| `nwctl.tape` | CLI | M1 (`NWProcess` + `nwctl ps`) |
| `console.tape` | TUI (`nwctl console --follow`) | M6 (`NWLog` event console) |

Until then the tapes serve as a forcing function: each milestone PR that ships a CLI/TUI surface updates the matching tape so the demo is current the day the feature lands, not three releases later.
