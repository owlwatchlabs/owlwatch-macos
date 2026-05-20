# Demos

Source-controlled scripts that record Nightwatch's user-visible surfaces — the menu-bar app, the console view, and the `nwctl` command-line — to GIFs and MP4s. Every demo asset that appears in `README.md`, the project website, or release notes traces back to a script in this directory.

## Why script-driven recordings

Hand-recorded demos drift. Someone records a polished take, ships it, and three releases later the menu items have moved, the prompt is different, and the GIF embeds a stale narrative. A scripted demo regenerates from a single command and stays current as long as someone runs the script before each release.

Scripted demos also let reviewers see the *script*, not just the artifact: a PR that updates a demo includes the diff of what changed, not an opaque binary swap.

## Tool: VHS

[`vhs`](https://github.com/charmbracelet/vhs) by Charm is the recorder. It reads a `.tape` file (a small DSL of `Type`, `Sleep`, `Enter`, `Show`, etc.), drives a headless terminal, and emits a GIF or MP4.

Install on macOS via Homebrew:

```bash
brew install vhs
```

`vhs` itself depends on `ttyd` and `ffmpeg`; both come along with the Homebrew formula.

## Convention

- One `.tape` file per surface: `menubar.tape`, `console.tape`, `nwctl.tape`. Add more as new surfaces ship.
- Each `.tape` declares an explicit `Output` path under `docs/demos/out/` (gitignored — see below).
- `Set` directives at the top of each tape pin font, size, theme, and frame rate so output is reproducible across machines.
- Comments at the top of each `.tape` describe the user story the demo tells in one or two sentences.

## Output handling

The generated GIFs and MP4s live under `docs/demos/out/` and **are not committed**. Reasons:

- Binary diffs in git blow up the repo size with every re-record.
- The point of script-driven demos is that the script is the source of truth; the artifact can always be regenerated.

When a demo is needed for a release, the release process runs `make demos` (added when M1 lands real behavior) which regenerates everything under `out/` and uploads the chosen artifacts to the GitHub Release.

Add `docs/demos/out/` to `.gitignore` the moment the first real recording lands — for now the directory does not exist on disk.

## State at M0

The three `.tape` files in this directory are **placeholders**. They reference behavior that does not yet exist (`nwctl ps`, the menu-bar app's event console, etc.) and will not produce useful recordings until the milestones that introduce that behavior ship:

| Tape | Real behavior available at |
|---|---|
| `nwctl.tape` | M1 (`NWProcess` + `nwctl ps`) |
| `menubar.tape` | M2–M3 (when the menu-bar app surfaces something beyond Quit) |
| `console.tape` | M6 (`NWLog` event console) |

Until then the tapes serve as a forcing function: each milestone PR that ships a user-visible surface updates the matching tape so the demo is current the day the feature lands, not three releases later.
