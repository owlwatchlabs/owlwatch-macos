# Changelog

All notable user-visible and operational changes to Owlwatch are tracked here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Pre-1.0 entries are tagged with the milestone identifier (`v0.1.0-m0`, `v0.2.0-m1`, ...) to keep the link between milestones and tags explicit. The `[Unreleased]` section accumulates entries between tags; each PR that ships a user-visible or operational change adds a line under the relevant subsection.

## [Unreleased]

_No entries yet — M17 hasn't been planned._

## [v0.10.0-m16] — 2026-05-23

The macOS app UI integration milestone. M1–M11 each shipped their own data source and CLI surface; M16 brings every one of them into the GUI as a production-ready MVP. The Owlwatch app gains a status dashboard plus five new top-level windows (Processes, Network, Logs, Binary Inspector, on top of the M5.5 Persistence and M11.4 Devices windows) and a live menu-bar indicator that flips between idle, attention, and in-use states without ever opening a window.

No new data source. No new entitlement. M16 is a consolidation pass — every byte of code in this milestone reads from libraries M1–M11 already ship.

### Added

- **Status Dashboard (M16.1)** — new top-level window reachable from the MenuBarExtra via **Open Dashboard…** (⌘⇧H). Headline counts from every data source: processes (M1), launch services + login items (M5), network listeners + active connections (M4), cameras + microphones + in-use count (M11). Plus a "recent activity" panel showing TCC denials and Error/Fault log entries within the last 5 minutes (`OWLog.tccEvents()` + `OWLog.query()`, both off the main actor). Pull-on-demand refresh — the dashboard isn't a live console; per-source live streams stay in their dedicated windows. The Owlwatch app target gained dependencies on `OWProcess`, `OWNetwork`, `OWLog`, `OWBinary`, `OWCodeSigning` so every shipped data-source module is reachable from the app.

- **Processes window (M16.2)** — reachable from MenuBarExtra via **Open Processes View…** (⌘⇧S) and a Dashboard quick-action button. Two-tab sidebar (All Processes / Process Tree), filterable center list, full-detail right pane. The tree uses SwiftUI's `OutlineGroup` with a `ProcessNode` building the parent → children hierarchy from M1's `RunningProcess` snapshot. **Two-phase loading**: the initial `OWProcess.all(...)` call uses `includeArguments: false, includeOpenFiles: false` for speed; when the user selects a process, the view model re-fetches *that one process* via `OWProcess.snapshot(pid:, includeArguments: true, includeOpenFiles: true)` for the detail pane so the per-process libproc cost isn't paid across the whole table. Search filters on name / path / PID against the flat list.

- **Network window (M16.3)** — reachable from MenuBarExtra via **Open Network View…** (⌘⇧N) and a Dashboard quick-action button. Five sidebar tabs (All / Listeners / TCP / UDP / Unix-domain) with per-tab badges, filterable center list, color-coded TCP state badges (green for `ESTABLISHED`, blue for `LISTEN`, orange for WAIT states). At refresh time the view model fans out two parallel detached fetches — `OWNetwork.snapshot()` for the connection set and `OWProcess.all(includeArguments: false, includeOpenFiles: false)` for a PID-to-process-name lookup map — so every connection row renders with its owning process without per-row latency. Detail pane shows the parsed endpoints, TCP state, process name, PID, and file descriptor.

- **Logs window (M16.4)** — reachable from MenuBarExtra via **Open Logs View…** (⌘⇧L) and a Dashboard quick-action button. Three tabs over M6's `OWLog`:
  - **All Logs** — generic `OWLog.query()` over a user-chosen lookback window (1 min / 5 min / 15 min / 1 hr / 6 hr / 24 hr), with subsystem / process / message-contains filters and Info / Debug / Errors-only toggles.
  - **TCC Events** — typed `OWLog.tccEvents()` from M6.2, with denied-only filter and process scoping. Outcomes color-coded; selecting a row shows the full accessing / requesting process attribution and brokered-vs-direct flag.
  - **Live Tail** — `OWLog.stream()` AsyncThrowingStream backing a 2000-entry capped buffer, newest-first. Predicate filters apply forward only. Sidebar badge shows unseen-entry count while the user is on a snapshot tab.

  Filter UI sits in a custom toolbar above the list rather than in the search bar — `log show` is seconds, not milliseconds, so explicit submission is the right interaction model.

- **Binary Inspector window (M16.5)** — reachable from MenuBarExtra via **Open Binary Inspector…** (⌘⇧B) and a Dashboard quick-action button. Path is supplied by ⌘O (NSOpenPanel) or drag-drop on the content area. Sidebar carries six sections — **Overview**, **Load Commands**, **Segments**, **Symbols**, **Signature**, **Entitlements** — each mirroring a flag of the `owlwatch inspect` / `verify` CLI. Universal binaries get a segmented architecture picker in the header bar; per-slice panes follow the selection. Load Commands lists every `LC_LOAD_DYLIB`-family entry (required / weak / self) with current + compat versions; Segments show each segment's r/w/x bits (with `rwx` flagged red) and per-section Shannon entropy (sections > 7.0 flagged red as a packing signal). Symbols are gated behind an explicit Load button since `LC_SYMTAB` parsing is expensive on large binaries. Signature pane renders identity + certificate chain + `SecCodeSignatureFlags` + hardened-runtime version + notarization staple + designated requirement. Entitlements pane sorts the entitlements-dict alphabetically with `bool true` highlighted green.

- **Menu-bar live indicator (M16.6)** — the MenuBarExtra shield is no longer static. A new `MenuBarStatusModel` (`@MainActor @Observable`) streams `OWDevices.monitor()` and polls `OWLog.tccEvents()` once a minute; the icon switches between `shield` (idle), `shield.fill` in orange (recent TCC denials), and `shield.lefthalf.filled` in red (a camera or microphone is currently in use). The dropdown's header restates the same signal as text — "2 cameras + 1 mic in use", "3 TCC denial(s) in last 5 min", or "All quiet" — so the user can read the device-attention state without opening any window. Cleanup is automatic via the AsyncThrowingStream `onTermination` callback on the device monitor.

- **`owlwatch --version`** bumped to `0.10.0-m16`.

### Notes

- No new SPM products. The macOS app added five new dependency lines in `project.yml` (`OWProcess`, `OWNetwork`, `OWLog`, `OWBinary`, `OWCodeSigning`) — every shipped `OW*` library is now linked into the app target.
- All seven app windows share the same three-column `NavigationSplitView` shape (sidebar / center / detail) for visual consistency. Per-window view models are `@MainActor @Observable`; long-running work runs on detached `Task`s and routes results back to the main actor.
- TCC denials are polled, not streamed, in the menu-bar indicator. `log show` takes seconds — a tighter cadence would burn CPU for no perceptible benefit.

### What's next

**M13** — detection rules engine over the data sources M1–M11 already ship — is the next unblocked milestone. The four entitlement-gated milestones (M7 / M8 / M9 / M12) and the notarized release (M15) remain blocked on Apple's entitlement-provisioning queue.

### PRs in this milestone

- #55 feat(Owlwatch): status dashboard + M16 milestone slot (M16.1)
- #56 feat(Owlwatch): Processes window (M16.2)
- #57 feat(Owlwatch): Network window (M16.3)
- #58 feat(Owlwatch): Logs window (M16.4)
- #59 feat(Owlwatch): Binary Inspector window (M16.5)
- #60 feat(Owlwatch): menu-bar live indicator (M16.6)
- #61 feat(owlwatch): close M16 — version bump to 0.10.0-m16, CHANGELOG promotion, README tick

## [v0.9.0-m11] — 2026-05-23

The mic-and-webcam milestone. Lands `OWDevices` — the seventh non-stub `OW*` library — plus two CLI subcommands (`owlwatch devices`, `owlwatch watch-devices`) and a new standalone macOS app window dedicated to camera/microphone state and attribution.

Two unblocked-by-Apple-entitlements milestones now ship complete: M10 (real-time persistence) and M11 (mic/webcam). With M11 in, every data source M1–M6, M10, M11 has both a snapshot reader and a live-event stream, plus a typed-event extraction layer where it makes sense. M13's rules engine has everything it needs from the static side.

### Added

- **`OWDevices` library.** Public surface across the M11.1–M11.3 slices:

  ```swift
  OWDevices.cameras() -> [Camera]
  OWDevices.microphones() -> [Microphone]
  OWDevices.monitor() -> AsyncThrowingStream<DeviceStateChange, Error>
  OWDevices.attribute(_ change: DeviceStateChange,
                      lookbackSeconds: TimeInterval = 10.0) -> [ProcessCandidate]
  ```

- **Device snapshot (M11.1).** `Camera` (`id`, `name`, `manufacturer`, `modelID`, `isInUse`, `isExternal`, `isVirtual`) and `Microphone` (`id`, `name`, `manufacturer`, `isInUse`, `isExternal`). Cameras enumerate via `AVCaptureDevice.DiscoverySession` for metadata + CMIO HAL (`CoreMediaIO` framework) for the `kCMIODevicePropertyDeviceIsRunningSomewhere` "in use" bit. Microphones enumerate via CoreAudio HAL filtered to devices with at least one input channel (excludes speakers / headphones / AirPlay outputs), `kAudioDevicePropertyDeviceIsRunningSomewhere` for the in-use bit. `isVirtual` flags Apple's own virtual cameras (Continuity Camera, Desk View); third-party virtual cameras (OBS) aren't reliably detectable through public APIs.

- **Live state-change stream (M11.2).** `DeviceStateChange` (`kind`, `id`, `name`, `isInUse`, `timestamp`). The monitor snapshots the device set at startup and registers CMIO + CoreAudio property listeners on each — one per device per `IsRunningSomewhere` selector — with clean teardown on stream cancellation. Devices plugged in after the monitor starts are NOT picked up; recreate the stream to refresh the watch set.

- **Best-effort attribution (M11.3).** `ProcessCandidate` (`identifier`, `pid`, `source`, `confidence`, `evidence`) with `AttributionSource` (`.tccRecentRequest` / `.foregroundApplication`) and `AttributionConfidence` (`.high` / `.medium` / `.low`). Cross-references M6.2's typed TCC events (`OWLog.tccEvents(_:)`) for the matching `kTCCServiceCamera` / `kTCCServiceMicrophone` request within a configurable lookback window, plus `NSWorkspace.shared.frontmostApplication` as a weaker signal. **macOS deliberately doesn't expose which process is holding a device** — CMIO and `coreaudiod` logs redact PIDs / bundle IDs as `<private>` regardless of TCC permissions. The TCC + foreground-app approach is the public-API ceiling; background daemons holding long-standing TCC grants return no candidate.

- **Two new CLI subcommands.** `owlwatch devices` prints `TYPE NAME MANUFACTURER IN USE EXTERNAL ID` rows for every camera and microphone, with `--cameras`, `--microphones`, `--in-use-only` filters. `owlwatch watch-devices` live-tails state transitions, with `--kind camera|microphone`, `--on-only`, `--attribute` (run attribution on every ON event), and `--attribute-lookback <seconds>` flags.

- **macOS app Devices window (M11.4).** New standalone window separate from the Persistence viewer, reachable from the MenuBarExtra via "Open Devices View…" (⌘⇧D). Three-column `NavigationSplitView` with Cameras / Microphones / Live Events sidebar tabs, per-tab badges (snapshot counts; unseen event count on Events while on snapshot tabs; total accumulated while on Events). When a user selects a live event, the detail pane runs `OWDevices.attribute(_:)` lazily and renders ranked candidates with color-coded confidence badges (green/yellow/gray). The snapshot tabs update in-place when live events arrive — no manual refresh needed for "in use" state. Live monitor task lifecycle bound to the window's appearance.

- **`Package.swift` cross-module dep:** OWDevices declares an `OWLog` dependency because attribution calls `OWLog.tccEvents()`. The other modules in the package stay dependency-free; the closure-based dep mapping keeps the change surgical.

- **Owlwatch version bump** — `owlwatch --version` now prints `0.9.0-m11`.

### Notes

- 238 / 238 unit tests pass (14 OWDevices + 47 OWPersistence + 41 OWLog + 29 OWCodeSigning + 28 OWBinary + 15 OWProcess + 15 OWNetwork + others).
- End-to-end state-change firing and attribution accuracy aren't fully unit-testable — triggering mic/camera activity from a headless test process is silently denied by macOS TCC, and attribution depends on the test runner's foreground status. The argv-builder / value-type / lifecycle tests cover what's deterministic; the live paths are exercised through `owlwatch watch-devices` and the macOS app's Devices window during manual smoke.
- The `DeviceMonitorRunner` uses `@unchecked Sendable` because CMIO and CoreAudio property-listener callbacks fire on internal serial dispatch queues — only one writer at a time. Documented inline, same pattern as M6.3 (`LineBuffer`), M10.1 (`MonitorRunner`).

### Deferred

- **Hot-plug device detection.** New devices plugged in after the monitor starts aren't picked up. A future addition would subscribe to `kCMIOHardwarePropertyDevices` / `kAudioHardwarePropertyDevices` on the system object to detect new attachments and dynamically extend the listener set.
- **Third-party virtual-camera detection.** OBS Virtual Camera and similar register as `.external` with synthetic model IDs; the `isVirtual` flag only catches Apple's own virtual cameras today. A future heuristic could inspect the CMIO plug-in bundle backing each `.external` camera (`/Library/CoreMediaIO/Plug-Ins/DAL/`) and flag third-party plug-ins.
- **Background-daemon attribution.** A daemon with a long-standing TCC grant that opens the device without becoming frontmost returns no attribution candidate today. A future heuristic could rank running processes by "has TCC permission for the matching service" + "has CoreMediaIO / AVFoundation in its load list".
- **macOS app notifications when the Devices window is closed.** The monitor only runs while the window is open. `UserNotifications` integration for banner alerts on mic/camera transitions is a future addition.

### What's next

**M13 — Rules engine.** Detection rules in a Owlwatch-native YAML schema over the data sources implemented across M1–M11. First milestone whose work doesn't add a new data source — instead it composes the existing ones into matchable patterns ("alert if a new LaunchAgent appears in `~/Library/LaunchAgents` from an unsigned process", "alert if the camera turns on while no foreground app has TCC camera permission", etc.). The four entitlement-gated milestones (M7 / M8 / M9 / M12) remain blocked on Apple.

### PRs in this milestone

#50 feat(OWDevices, owlwatch): camera and microphone snapshot + in-use detection (M11.1)
#51 feat(OWDevices, owlwatch): live device-state stream + watch-devices CLI (M11.2)
#52 feat(OWDevices, owlwatch): best-effort process attribution for device events (M11.3)
#53 feat(Owlwatch, OWDevices): macOS app Devices window (M11.4)
#54 feat(owlwatch): close M11 — version bump to 0.9.0-m11, CHANGELOG promotion, README tick

## [v0.8.0-m10] — 2026-05-23

The real-time-persistence milestone. Lands the FSEvents-backed live counterpart to M5's snapshot reader: `OWPersistence.monitor()` for raw mutation events, `OWPersistence.monitorEnriched()` for events enriched with the parsed contents of the file that changed, plus the `owlwatch watch-persistence` CLI subcommand and a "Live Events" tab in the macOS app's persistence viewer.

First non-entitlement-gated milestone shipped after the unified-log milestone (M6). FSEvents is part of CoreServices and works unprivileged — no Apple entitlement provisioning required. This is the live half of the detection pipeline that pairs with M5's "what's installed right now?" snapshot to answer "what just changed?".

### Added

- **`OWPersistence.monitor()` (M10.1)** — `AsyncThrowingStream<PersistenceMutation, Error>` over `FSEventStreamCreate` with `kFSEventStreamCreateFlagFileEvents`. Each kernel filesystem event becomes a `PersistenceMutation`. Cancellation stops + invalidates the stream cleanly via the `onTermination` hook.

- **Value types (M10.1):**
  - `PersistenceMutation` (`path`, `kind`, `scope`, `timestamp`, `eventID`)
  - `MutationKind` — `.added` / `.modified` / `.removed` / `.renamed` / `.xattrChanged` / `.metadataChanged`. The classifier collapses one event's multi-flag bitfield into the single most-descriptive kind — `removed > renamed > added > modified > xattrChanged > metadataChanged` — so detection rules don't have to disambiguate. `xattrChanged` specifically surfaces `com.apple.quarantine` removal as a Gatekeeper-bypass signal.
  - `MutationScope` — `.platformLaunchd` / `.systemLaunchd` / `.userLaunchd` / `.systemExtensionsRegistry` / `.kernelExtensions` / `.loginwindowPlist` / `.other`. Classified from path prefix.
  - `OWPersistenceMonitorError` — `.unableToCreateStream(paths:)` / `.streamFailedToStart`.
  - All three enums gained `String` raw value conformance in M10.3 for SwiftUI text rendering.

- **`OWPersistence.defaultMonitorPaths`** — pre-baked watch set covering every M5 source (LaunchAgents + LaunchDaemons in all three locations, the System Extensions registry, both kext directories, and the system + user loginwindow preference plists). Callers can override.

- **`OWPersistence.monitorEnriched()` (M10.2)** — enrichment layer over the raw stream. `AsyncThrowingStream<EnrichedMutation, Error>` yields each `PersistenceMutation` with the *parsed payload* attached — a `LaunchService` for LaunchAgent / LaunchDaemon mutations, a `[LoginLogoutHook]` for `com.apple.loginwindow.plist` mutations. Removed-file events have no readable content; payload stays `nil`. Enrichment runs synchronously on the FSEvents dispatch queue — plist parsing is hundreds of microseconds, well inside the latency window.

- **`EnrichedMutation` value type** (M10.2) — `mutation`, `launchService`, `hooks`, computed `hasPayload`.

- **`owlwatch watch-persistence` (M10.1 + M10.2)** — eleventh subcommand. Default output is enriched: `TIMESTAMP KIND SCOPE LABEL/HOOK PROGRAM/SCRIPT PATH`, surfacing the most-detection-relevant fields (the `Label` and `Program` of a newly-dropped LaunchAgent, the kind and `scriptPath` of a hook change). `--raw` falls back to the four-column layout (`TIMESTAMP KIND SCOPE PATH`). Other flags: `--kind <comma-list>`, `--scope <scope>`, `--latency <seconds>`.

- **Live Events tab in the macOS app (M10.3)** — sixth sidebar entry in the persistence viewer window (M5.5). Subscribes to `OWPersistence.monitorEnriched()` for the lifetime of the window; new mutations appear newest-first in the center list. The sidebar badge shows *unseen* event count while the user is on a snapshot tab, *total* count while on Live; selecting Live clears the unseen counter. Detail pane shows the raw mutation fields plus the parsed payload (Label / Program / Run-at-Load / Keep-Alive for LaunchAgents; per-hook script paths for hook changes). History caps at 500 events to bound memory.

- **`fflush(stdout)` for streaming subcommands** — M6.3 used `FileHandle.standardOutput.synchronizeFile()` to flush between rows, which throws `NSFileHandleOperationException` (`"Invalid argument"`) when stdout is a pipe or regular file. M6.3 only got away with it because `log stream` emitted data faster than the exception could terminate the process; M10's quieter `watch-persistence` exposed the bug immediately. Replaced with C-level `fflush(stdout)` in both `owlwatch logs --follow` and `owlwatch watch-persistence`.

- **Owlwatch version bump** — `owlwatch --version` now prints `0.8.0-m10`.

### Notes

- 218 / 218 unit tests pass (14 PersistenceMonitorTests + 9 EnrichedMutationTests + 41 OWLog + 47 OWPersistence + 29 OWCodeSigning + 28 OWBinary + 15 OWProcess + 15 OWNetwork + others).
- `FSEventStream` subscription itself isn't unit-tested — needs real filesystem events with async timing and a live dispatch queue, which is non-deterministic under XCTest. The classifier helpers (`classifyKind`, `classifyScope`, `defaultMonitorPaths` coverage) cover everything deterministic; the live path is exercised through `owlwatch watch-persistence` and the macOS app Live tab during manual smoke testing.
- The `MonitorRunner` and `LineBuffer` classes both use `@unchecked Sendable` because the underlying Foundation primitives (FSEvents callback queue, `Pipe.fileHandleForReading.readabilityHandler`) serialize invocations onto a single dispatch queue — there's only ever one writer touching the internal state. Documented inline so future contributors don't innocently add a parallel writer path.

### Deferred

- **Disabled-state refresh on every event** — the enrichment parser passes an empty central disabled map; `~/var/db/com.apple.xpc.launchd/disabled.<uid>.plist` isn't re-read per event. The mutation event reports "this file was just written", so the file's own `Disabled` key is what we surface. Detection rules that need live disabled state call `OWPersistence.launchServices(...)` for the current snapshot.
- **Notifications when the persistence window is closed** — the Live monitor only runs while the window is open. A `UserNotifications` integration that surfaces banners regardless of window state is a future addition; deliberately not in M10's scope.
- **Persistent event log on disk** — closing the persistence window discards the in-memory event history. M13 (rules engine) will need disk-backed storage of qualifying events; M10 deliberately stays in memory.
- **System Extensions registry + kext payload extraction** — enrichment for `db.plist` mutations and `.kext` bundle changes would need richer correlation (one `db.plist` change reflects many extensions; a kext bundle change can be deep). Surfaces the raw mutation with no payload today; callers cross-reference `OWPersistence.systemExtensions()` / `kernelExtensions()` for the snapshot.

### What's next

The two remaining non-entitlement-gated milestones are **M11** (`OWDevices` — mic and webcam access attribution via the existing AVCaptureDevice and CoreAudio APIs) and **M13** (rules engine over the data sources already implemented across M1–M6, M10). The four entitlement-gated milestones (M7 Network Extension, M8 Endpoint Security, M9 ES auth/muting, M12 DNS proxy) stay blocked on Apple's entitlement-provisioning queue, tracked at [docs/apple-developer/entitlement-requests.md](docs/apple-developer/entitlement-requests.md).

### PRs in this milestone

#46 feat(OWPersistence, owlwatch): real-time persistence monitor via FSEvents (M10.1)
#47 feat(OWPersistence, owlwatch): enriched persistence-mutation stream (M10.2)
#48 feat(Owlwatch, OWPersistence): macOS app Live tab (M10.3)
#49 feat(owlwatch): close M10 — version bump to 0.8.0-m10, CHANGELOG promotion, README tick

## [v0.7.0-m6] — 2026-05-22

The unified-log milestone. Lands `OWLog` — the sixth non-stub `OW*` library — plus three new `owlwatch` subcommands: a generic historical query (`logs`), a live tail (`logs --follow`), and a typed TCC privacy-decision view (`tcc-events`).

This is the first milestone to draw data from Apple's unified logging system (`os_log` archives under `/var/db/diagnostics/`). The detection value is large despite the indirect data path: every TCC privacy decision, Gatekeeper assessment, code-signing verification, Keychain unlock, and LaunchServices launch flows through `os_log`. M6 makes that surface queryable from Swift, and M6.2's TCC event reconstruction shows the pattern future M8 (Endpoint Security) integration will reuse.

The library is also the first OW* module to expose an async API: `OWLog.stream(_:)` returns an `AsyncThrowingStream<LogEntry, Error>` for live tail. Wiring that into the CLI required upgrading the root `Owlwatch` command and `LogsCommand` to `AsyncParsableCommand`; the existing ten sync subcommands kept their sync `run()` unchanged.

### Added

- **`OWLog` library.** Three public APIs across the slices:

  ```swift
  OWLog.query(_ query: LogQuery = LogQuery()) throws -> [LogEntry]
  OWLog.stream(_ query: LogQuery = LogQuery()) -> AsyncThrowingStream<LogEntry, Error>
  OWLog.tccEvents(_ query: LogQuery = .tccDefault) throws -> [TCCEvent]
  ```

  Backed by `/usr/bin/log show --style ndjson` and `/usr/bin/log stream --style ndjson`. The `OSLogStore` Swift API would be cleaner but requires the private `com.apple.logging.local-store` entitlement to read the system store; `log show` / `log stream` have the entitlement built in. Same trade-off as M5.2's `sfltool dumpbtm` shell-out, same approach every off-the-shelf macOS log tool takes.

- **`LogEntry` value type** with fields: `timestamp`, `processName`, `processPath`, `processID`, `userID`, `threadID`, `subsystem`, `category`, `level`, `eventType`, `message`, `activityID`. The verbose internal fields (backtrace frames, image UUIDs, trace IDs, format strings) are dropped — useful for kernel debugging but bloat the snapshot value type.

- **`LogLevel`** (`.default` / `.info` / `.debug` / `.error` / `.fault`) and **`LogEventType`** (`.log` / `.state` / `.userAction` / `.signpost` / `.trace` / `.other(rawValue:)`).

- **`LogQuery` filter struct** with shorthand fields (`subsystem`, `category`, `process`, `messageContains`) that compose via `AND` plus a free-form NSPredicate `predicate` appended to the same chain. `since` / `until` map to `--start` / `--end`; `limit` (default 200) maps to `--last`. `includeInfo` / `includeDebug` opt into the corresponding levels (Error / Fault are always included).

- **`TCCEvent` typed extraction (M6.2)** — correlates the 6-line transactions `tccd` emits per privacy-permission request into a single value (`REQUEST` + `AUTHREQ_CTX` + `AUTHREQ_ATTRIBUTION` + `AUTHREQ_SUBJECT` + `AUTHREQ_RESULT` + `REPLY`). Records: `service`, `isPreflight`, `accessingProcess`, `requestingProcess`, `outcome`, `authValueRaw`, `authReasonRaw`, computed `isDirectRequest`. `TCCService` covers 26 well-known `kTCCService*` strings; `TCCOutcome` covers `.denied` (`authValue == 0`) / `.allowed` (`2`) / `.allowedLimited` (`3`) / `.unknown(rawValue:)`. Forward-compat via `.other(rawValue:)` so detection rules can still match new services Apple adds.

- **`owlwatch logs`** — generic historical query subcommand. Flags: `--subsystem`, `--category`, `--process`, `--message-contains`, `--predicate` (raw NSPredicate), `--since`, `--until`, `--lookback <seconds>`, `--last <N>`, `--info`, `--debug`, `--errors-only`. Time-based filtering accepts ISO-8601 and the simpler `"YYYY-MM-DD HH:MM:SS"` form.

- **`owlwatch logs --follow` (M6.3)** — live-tail mode wrapping `log stream`. Prints the header once, then streams new entries as they arrive; `--errors-only` composes with `--follow`; historical-only flags are ignored. Root `Owlwatch` + `LogsCommand` upgraded to `AsyncParsableCommand`; the other ten subcommands continue as sync `ParsableCommand` (swift-argument-parser supports mixed roots seamlessly).

- **`owlwatch tcc-events`** — typed TCC-decision subcommand. Flags: `--denied-only`, `--hide-preflight`, `--service <kTCC...>`, `--process <substring>` (matches accessing *or* requesting identifier), plus the standard `--lookback` / `--since` / `--until`.

- **Sentinel-value handling.** Some kernel-side log records carry sentinel `processID` / `userID` values like `4294967294` (UID `-2` = "nobody"). Plain `Int32(value)` casts crash with *"Not enough bits to represent the passed value"*. The parser uses `pid_t(truncatingIfNeeded:)` / `uid_t(truncatingIfNeeded:)` instead; regression test pins the behavior.

- **`LineBuffer`** — accumulates chunked stdout reads into complete newline-terminated lines. Marked `@unchecked Sendable` because Foundation serializes `readabilityHandler` invocations onto one dispatch queue.

- **Owlwatch version bump** — `owlwatch --version` now prints `0.7.0-m6`.

### Notes

- 195 / 195 unit tests pass (41 OWLog + 47 OWPersistence + 29 OWCodeSigning + 28 OWBinary + 15 OWProcess + 15 OWNetwork + others).
- Captured fixture in `Tests/OWLogTests/Fixtures/log-show-sample.ndjson` happens to contain a real WhatsApp/camera-denial chain via `ContinuityCaptureAgent` — pinned as the canonical "preflight denial chain" detection shape.
- The `log show` / `log stream` shell-out is again a meaningful coupling. The unified-log NDJSON format is not contractually stable across macOS versions; the parser is intentionally tolerant (blank lines + non-JSON banners skipped, unparseable-timestamp records dropped, raw enum values preserved via `.other(rawValue:)`) so format drift degrades gracefully.

### Deferred

- **Typed event extraction for other subsystems** — SecurityServer (code signing decisions, Keychain unlocks), LaunchServices (`LSOpen*` invocations), spctl / syspolicy (Gatekeeper verdicts), AMFI (load-time signature validation). M6.2's TCC infrastructure (regex helpers, msgID-style group correlation, `.other(rawValue:)` forward-compat) extends to these without re-design; lands as follow-up PRs when M13's rules engine actually needs them.
- **`OSLogStore`-based reader** — would avoid the subprocess overhead but requires the private `com.apple.logging.local-store` entitlement. Re-examined when Apple's entitlement-provisioning yields anything.
- **Live integration test for `log stream`** — the subprocess never self-terminates and any timing-sensitive Task kill depends on launchd. Argv builder + LineBuffer cover everything deterministic; live exercise is via `owlwatch logs --follow` manual smoke.

### What's next

**M7 — `OwlwatchNetwork`.** Network Extension filter provider — the first milestone to ship a System Extension target with real-time per-flow visibility. Gated on Apple's entitlement-provisioning queue (tracked at [docs/apple-developer/entitlement-requests.md](docs/apple-developer/entitlement-requests.md)). If the entitlement isn't ready, M8 (Endpoint Security) or M10 (FSEvents persistence monitor) may land first depending on which entitlement Apple approves.

### PRs in this milestone

#41 feat(OWLog, owlwatch): unified-log query + `owlwatch logs` (M6.1)
#42 feat(OWLog, owlwatch): typed TCC events + `owlwatch tcc-events` (M6.2)
#43 feat(OWLog, owlwatch): live-tail mode via `log stream` (M6.3)
#44 feat(owlwatch): close M6 — version bump to 0.7.0-m6, CHANGELOG promotion, README tick

## [v0.6.0-m5] — 2026-05-22

The persistence-enumeration milestone. Lands `OWPersistence` — the fifth non-stub `OW*` library — plus five new `owlwatch` subcommands and **the first interactive UI surface in the macOS app**: a 3-column persistence viewer reachable from the existing MenuBarExtra.

Together M5's slices cover every macOS persistence mechanism that's both worth surfacing and accessible without restricted entitlements: LaunchAgents and LaunchDaemons across all five standard scopes, the Background Task Management (BTM) database (apps, login items, helper agents, Spotlight importers, QuickLook extensions, legacy SMLoginItem-era persistence), modern System Extensions (DriverKit / Network Extension / Endpoint Security), legacy Kernel Extensions, and the deprecated-but-still-honored login/logout hooks. The malware studies of the last 5+ years (XCSSET, Silver Sparrow, AdLoad, KeRanger, WindTail, ChromeLoader, Atomic Stealer / AMOS) overwhelmingly use these surfaces — usually `~/Library/LaunchAgents` and `~/Library/Application Support/...` login items, which need no admin authentication.

This is the milestone every later detection rule branches on for "what's set to auto-start on this box?". M10's persistence monitor (FSEvents-backed, real-time) and M13's rules engine both consume the value types `OWPersistence` exposes here.

### Added

- **`OWPersistence` library.** Public surface across all five slices:

  ```swift
  OWPersistence.launchServices() -> [LaunchService]
  OWPersistence.launchServices(in: LaunchScope) -> [LaunchService]
  OWPersistence.loginItems() -> [LoginItem]
  OWPersistence.systemExtensions() -> [SystemExtension]
  OWPersistence.kernelExtensions() -> [KernelExtension]
  OWPersistence.kernelExtensions(in: KernelExtensionScope) -> [KernelExtension]
  OWPersistence.loginLogoutHooks() -> [LoginLogoutHook]
  ```

  Each kind is its own value type with the full per-kind field surface; `LoginItemKind` / `SystemExtensionCategory` / `SystemExtensionState` enums preserve raw values for forward-compatibility when Apple introduces new BTM types or extension categories.

- **Five new `owlwatch` subcommands** (after `ps` / `inspect` / `verify` / `netstat`):

  ```
  owlwatch persistence            # LaunchAgents + LaunchDaemons
  owlwatch login-items            # BTM records via sfltool dumpbtm
  owlwatch system-extensions      # /Library/SystemExtensions/db.plist
  owlwatch kernel-extensions      # /System/Library/Extensions + /Library/Extensions
  owlwatch login-hooks            # LoginHook / LogoutHook keys
  ```

  Each takes scoped filter flags (`--user-only`, `--enabled-only`, `--scope`, `--kind`, `--running-only`, `--third-party-only`, `--bundle-id`, `--team-id`, etc.).

- **First interactive UI surface in the macOS app.** New `Window` scene with a 3-column `NavigationSplitView`: sidebar with badge counts per kind, center list with live search-bar filtering, detail pane with per-kind field surface and "Reveal in Finder" affordance on path fields. Reached from the existing `MenuBarExtra` via "Open Persistence View…" (⌘⇧P). View-model refresh dispatches each kind via `Task.detached` so the slow BTM read (5–60s on first invocation) doesn't block the UI.

- **App entitlements** updated to opt out of the App Sandbox (was `com.apple.security.app-sandbox = true` since M0). An EDR cannot operate inside the app sandbox — it needs to read `/Library/LaunchAgents`, `/Library/LaunchDaemons`, `/Library/SystemExtensions`, the loginwindow preference plists, and spawn `/usr/bin/sfltool`. Documented in `Owlwatch.entitlements` as an XML comment so future contributors don't accidentally re-enable sandbox.

- **Drive-by `Hashable` conformance** on `LaunchService` / `KeepAlive` / `KeepAliveConditions` so SwiftUI's `NavigationSplitView` selection can address them by identity. Additive change; no behavior diff for existing callers.

- **Owlwatch version bump** — `owlwatch --version` now prints `0.6.0-m5`.

### Notes

- 154/154 unit tests pass (47 OWPersistence + 29 OWCodeSigning + 28 OWBinary + 15 OWProcess + 15 OWNetwork + others). Tested against real Apple-shipped plists (`/System/Library/LaunchDaemons`), captured fixtures for `sfltool dumpbtm` output (15 BTM records spanning app / login-item / quicklook / spotlight / legacy-agent kinds), synthetic `db.plist` for System Extensions (3 records covering activated_enabled / awaiting_user_approval / activated_disabled states), live `/System/Library/Extensions` traversal, temp loginwindow plists.

- **`sfltool dumpbtm` is non-deterministic under XCTest** (5–60s observed for the same input on the same machine, likely launchd back-pressure / subprocess sandboxing). A live-system smoke test for `OWPersistence.loginItems()` is intentionally NOT included in the test suite. The fixture coverage is deterministic; the live path is exercised via `owlwatch login-items` and the macOS app during manual smoke testing.

- **The `sfltool` shell-out is a meaningful coupling.** The BTM database under `/var/db/com.apple.backgroundtaskmanagementagent/` is owned by root and not readable by ordinary users; Apple's `sfltool dumpbtm` is the canonical user-mode reader. Every macOS persistence tool worth using (KnockKnock, Objective-See's BlockBlock, etc.) takes the same approach. The parser preserves raw bitfield values + raw type names, so most format drift will degrade gracefully.

### Deferred

- **Configuration Profiles** — originally planned for M5.3. `/var/db/ConfigurationProfiles/Store/` requires Full Disk Access (TCC), and most of what we'd surface there is already covered by System Extensions + Login Items + Launch Services. Reconsidered when a real detection rule actually needs the raw profile payload data.
- **cron / periodic / emond / at jobs** — originally planned for M5.4. `/etc/periodic/` no longer exists on macOS 26; `/var/at/tabs/` requires root for other users' crontabs; emond is deprecated. The realistic detection moments for cron-style persistence (write of a new crontab, exec of an unexpected command from a cron-launched shell) are M10 (FSEvents) and M8 (Endpoint Security) territory. Reconsidered when a real detection rule asks.
- **Runtime kext loaded-status** — `kextstat` / `IOKit` territory. Static inspection from disk is enough for the M5 surface; live load state matters for M10's persistence monitor.
- **Privileged-write actions on persistence items** — no revoke / disable buttons in the UI. Requires entitlements we don't have yet and is properly a Settings-action surface rather than a snapshot viewer.

### What's next

M6 — `OWLog`. `os_log` ingestion and structured log event filters. First milestone to draw data from Apple's unified logging system (via the `OSLog` framework / `log show` subprocess) rather than the libproc / Mach-O / Security framework / kernel-network / filesystem / sfltool sources M1–M5 used. Sets up the data path M8's Endpoint Security events will share.

### PRs in this milestone

#34 feat(OWPersistence, owlwatch): launch services enumeration + `owlwatch persistence` (M5.1)
#35 feat(OWPersistence, owlwatch): login items + Background Task Management (M5.2)
#36 feat(OWPersistence, owlwatch): System Extensions + Kernel Extensions (M5.3)
#37 feat(OWPersistence, owlwatch): login/logout hooks (M5.4)
#38 feat(Owlwatch, OWPersistence): macOS app persistence viewer (M5.5)
#39 fix(Owlwatch): activate app when opening persistence window from menu bar
#40 feat(owlwatch): close M5 — version bump to 0.6.0-m5, CHANGELOG promotion, README tick

## [v0.5.0-m4] — 2026-05-22

The host-network-state milestone. Lands `OWNetwork` — the fourth non-stub `OW*` library — plus `owlwatch netstat`, the fourth subcommand. Together they enumerate every IP and Unix-domain socket held by a visible process, with the same posture as `lsof -i`: unprivileged callers see only their own processes; root sees everything.

This is a snapshot library, not a stream. For real-time visibility of new connection attempts the M7 Network Extension filter is the right tool — `OWNetwork` answers point-in-time questions: "is this process connected to anything right now?", "who's listening on port 5432?", "which processes are talking to `com.apple.tccd`?". Detection rules in M13 will branch on its output, and M7's Network Extension will enrich live flows with the same shape of metadata.

### Added

- **`OWNetwork` library**. Public surface:

  ```swift
  OWNetwork.snapshot() throws -> [Connection]
  OWNetwork.snapshot(pid: pid_t) throws -> [Connection]
  ```

  Backed by `proc_pidinfo(PROC_PIDLISTFDS)` + `proc_pidfdinfo(PROC_PIDFDSOCKETINFO)` — same data path as `lsof -i`. No entitlements required; no kernel-extension hooks.

- **`Connection` value type** with fields: `pid`, `fd`, `family`, `protocol`, `localAddress`, `localPort`, `remoteAddress`, `remotePort`, `tcpState`. Computed convenience: `isListener` (TCP `LISTEN`, UDP bound without peer, Unix socket bound without peer).
- **`AddressFamily` enum** — `.ipv4` / `.ipv6` / `.unix`. For Unix sockets, `Connection.localAddress` carries the bound filesystem path rather than an IP.
- **`TransportProtocol` enum** — `.tcp` / `.udp` (over IP) / `.unixStream` (`SOCK_STREAM`) / `.unixDatagram` (`SOCK_DGRAM`). Raw values are `"tcp"` / `"udp"` / `"unix-stream"` / `"unix-dgram"` so the CLI can use them directly.
- **`TCPState` enum** — 11 cases mirroring `TCPS_*` from `<netinet/tcp_fsm.h>`: `closed`, `listen`, `synSent`, `synReceived`, `established`, `closeWait`, `finWait1`, `closing`, `lastAck`, `finWait2`, `timeWait`. `displayName` renders the standard uppercase-underscored form (`"ESTABLISHED"`, `"FIN_WAIT_1"`, `"SYN_RCVD"`).
- **`OWNetworkError`** — `.unreachable(pid:errno:)` when the caller lacks permission to enumerate a process's descriptors.
- **`owlwatch netstat` subcommand** — fourth subcommand after `ps` / `inspect` / `verify`. Prints `PROTO LOCAL REMOTE STATE PID PROCESS` rows for every captured socket. Flags compose: `--listen` / `-l`, `--tcp` / `-t`, `--udp` / `-u`, `--unix`, `--ipv4`, `--ipv6`, `--port <PORT>` (matches local *or* remote), `--pid <PID>`. IPv6 addresses render with `[...]` brackets; wildcard IP endpoints render as `*:*`; anonymous Unix sockets render as `(anonymous)`.
- **Port byte-order decode** documented and pinned: `insi_lport` is declared `int` but the kernel stores the port value in network byte order in the low 16 bits. Decode is `UInt16(rawPort & 0xFFFF).byteSwapped`. Live-socket round-trip test guards against a future "simplification" that would silently break.
- **Owlwatch version bump** — `owlwatch --version` now prints `0.5.0-m4`.

### Notes

- 91/91 unit tests pass (15 OWNetwork + 29 OWCodeSigning + 28 OWBinary + 15 OWProcess + others). Tests open real TCP, UDP, and Unix sockets on loopback / temp paths in setup and round-trip them through `OWNetwork.snapshot(pid: getpid())`, asserting on every field.
- Smoke-tested against the live system: detects rapportd / mDNSResponder / Spotify / Chrome / identityservicesd IP sockets correctly with ESTABLISHED states and full peer endpoints; detects ssh-agent listeners, VS Code's IPC sockets, Chrome's singleton socket, syslog and mDNSResponder client connections from system daemons for Unix sockets.
- `SOCKINFO_UN = 3` on macOS (not 4 as the struct ordering inside `soi_proto` would suggest). Confirmed against `<sys/proc_info.h>` and runtime probe; the M4.2 PR refactored M4.1's magic-number kind constants to use Darwin's exported `SOCKINFO_*` values.

### Deferred

- **Protocol stats** (bytes / packets sent and received). Not exposed by `proc_pidfdinfo` — would require the separate `nstat` framework, which is a parallel data pipeline for an inferior result vs M7's Network Extension where flow stats are first-class. Reconsidered with M7 rather than added to M4.
- **Online connection diffing** — i.e. "what's new since the last snapshot?". Snapshot library by design; M7 covers live observation.

### What's next

M5 — `OWPersistence`. Auto-start item enumeration: LaunchAgents, LaunchDaemons, login items, configuration profiles, kernel extensions. First milestone to draw data from the filesystem (`/Library/LaunchAgents`, `/Library/LaunchDaemons`, `~/Library/LaunchAgents`, `/Library/Application Support/com.apple.TCC/`) rather than the libproc / Mach-O / Security framework / kernel-network data sources M1 / M2 / M3 / M4 used. Also the first milestone to have a user-facing surface in the macOS app — a view of installed persistence items.

### PRs in this milestone

#31 feat(OWNetwork, owlwatch): host network state + `owlwatch netstat` (M4.1)
#32 feat(OWNetwork, owlwatch): Unix-domain sockets (M4.2)
#33 feat(owlwatch): close M4 — version bump to 0.5.0-m4, CHANGELOG promotion, README tick

## [v0.4.0-m3] — 2026-05-22

The code-signing milestone. Lands `OWCodeSigning` — the third non-stub `OW*` library — plus `owlwatch verify`, the third subcommand. Together they expose every static-inspectable property of a macOS code signature: signature presence and structural validity, signing-identity classification, Team ID and identifier, CDHash, certificate chain, `SecCodeSignatureFlags`, designated requirement, stapled notarization ticket, hardened-runtime version, and parsed entitlements. Wrapper over Apple's Security framework (`SecStaticCode*`) — Owlwatch inherits CMS / CDHash / authority extraction rather than re-implementing it, which gains correctness and forward-compatibility with new signing-format versions for free.

This is the milestone every later detection rule branches on. M9's AUTH-event allow/block decisions, M10's persistence-monitor identity checks, and M13's detection rules all start from "what does the signature say?", which is exactly the question this milestone answers.

### Added

- **`OWCodeSigning` module** — public surface: `OWCodeSigning.inspect(at: URL) throws -> CodeSignature`. Backed by `SecStaticCodeCreateWithPath` + `SecCodeCopySigningInformation` + `SecStaticCodeCheckValidity` + `SecCodeCopyDesignatedRequirement` + `SecRequirementCopyString`. Unsigned inputs return a populated `CodeSignature` with `isSigned: false` rather than throwing — matches `codesign -dvvv` posture so callers in M9 / M13 can branch on signature presence without `try`/`catch`.
- **`CodeSignature` value type** with fields: `url`, `isSigned`, `isValid` (structural), `signatureType`, `identifier`, `teamIdentifier`, `cdHash` + `cdHashHex`, `authorities` (leaf-first CN chain), `flags`, `format`, `designatedRequirement`, `stapledNotarizationTicket`, `hardenedRuntimeVersion`, `entitlements`. Computed convenience: `isStapledForNotarization`, `hasHardenedRuntime`.
- **`SignatureType` enum** — `.unsigned` / `.adhoc` / `.developerID` / `.appleDeveloper` / `.appStore` / `.apple` (first-party) / `.unknown`. Derived from the `kSecCodeSignatureAdhoc` flag and the leaf-certificate Common Name.
- **`SignatureFlags` `OptionSet`** over `SecCodeSignatureFlags` bits: `host`, `adhoc`, `forceHard`, `forceKill`, `forceExpiration`, `restrict`, `enforcement`, `libraryValidation`, `runtime`, `linkerSigned`. Stable `symbolicForm` rendering (e.g. `"library-validation runtime"`).
- **`Entitlement` enum** — `.bool` / `.integer` / `.string` / `.data` / `.array` / `.dictionary` covering every plist value type entitlements can carry. `CFBoolean` and `NSNumber(Int)` are distinguished via `CFGetTypeID` so integer entitlements don't collapse into `.bool`. Convenience: `boolValue`, `stringValue` for the overwhelming-majority cases.
- **`OWCodeSigningError`** — `.unreadable(url:status:message:)` / `.malformedSignature(url:status:message:)`.
- **`owlwatch verify <path>` subcommand** — third subcommand after `ps` and `inspect`. One-shot summary of every `CodeSignature` field. Accepts Mach-O binaries, `.app` bundles, frameworks — anything `SecStaticCodeCreateWithPath` recognizes.
- **Three-state semantics** preserved across the new optional fields (`nil` = not present, `[:]` / `[]` = present but empty, populated = data available). Specifically called out: `stapledNotarizationTicket == nil` does **not** mean "not notarized" — VS Code is the canonical example of an online-notarized-but-unstapled app. `entitlements == [:]` (Rectangle.app) is distinct from `entitlements == nil` (`/bin/ls`).
- **Owlwatch version bump** — `owlwatch --version` now prints `0.4.0-m3`.

### Notes

- 76/76 unit tests pass (29 OWCodeSigning + 28 OWBinary + 15 OWProcess + others). Tested against `/bin/ls` (Apple first-party), `/usr/lib/dyld` (Apple first-party), `/Applications/Rectangle.app` (Developer ID + hardened runtime + stapled notarization, empty entitlements blob), `/Applications/Visual Studio Code.app` (Developer ID + hardened runtime + online-notarized-but-unstapled + populated entitlements), `/Applications/Xcode.app` (Apple first-party with Team ID + library-validation). Output matches `codesign -dvvv` and `codesign -d --entitlements -` for the data they share.
- Deliberately did not implement LC_CODE_SIGNATURE blob parsing in-process. The Security framework already handles CMS / CDHash / authority extraction; re-implementing that surface would be net-negative.

### Deferred

- **Online notarization check** — distinguishing "no stapled ticket but online-notarized" from "never notarized" requires `SecAssessment` (network call). Lands as either a future M3.x or in M9 when AUTH-event decisions need a Gatekeeper-equivalent verdict.
- **Designated-requirement evaluation** — i.e. "does this binary satisfy *this specific* requirement string?" — uses `SecStaticCodeCheckValidity(_, _, requirement)`. Detection rules in M13 will want this; M3 only ships the text-form extraction.

### What's next

M4 — `OWNetwork`. Host network state: open sockets and active connections with process attribution. The first M-numbered milestone to draw data from the kernel via `sysctl(CTL_NET, PF_INET, IPPROTO_TCP, TCPCTL_PCBLIST)` rather than the libproc / Mach-O / Security framework data sources M1 / M2 / M3 used.

### PRs in this milestone

#27 feat(OWCodeSigning, owlwatch): code-signature inspection + `owlwatch verify` (M3.1)
#28 feat(OWCodeSigning, owlwatch): designated requirement + notarization + hardened-runtime version (M3.2)
#29 feat(OWCodeSigning, owlwatch): entitlements parsing (M3.3)
#30 feat(owlwatch): close M3 — version bump to 0.4.0-m3, CHANGELOG promotion, README tick

## [v0.3.0-m2] — 2026-05-21

The binary-parser milestone. Lands `OWBinary` — the second non-stub `OW*` library — plus `owlwatch inspect`, the second subcommand. Together they parse Mach-O and Universal binaries and expose six dimensions of binary inspection (dependencies, runtime search paths, identity, symbols, segment / section layout, per-section entropy) through a single composable CLI. The companion library is the static-analysis foundation every later milestone builds on: M3 (`OWCodeSigning`) reads `LC_CODE_SIGNATURE` from the segment data; M13 (`OWRules`) can match detection rules against linked dylibs, imported symbol names, segment protection bits, and entropy thresholds.

### Added

- **`OWBinary` module** — public surface: `OWBinary.parse(at: URL, includeSymbols: Bool = false) throws -> BinaryFile`, `OWBinary.entropy(of: URL, fileOffset: UInt64, length: UInt64) throws -> Double`, `OWBinary.sectionEntropies(of: BinaryFile) throws -> [SectionEntropy]`. Value types: `BinaryFile` (with `linkedDylibs` convenience deduplicating LC_LOAD_DYLIB-family entries across slices), `Slice` (architecture, fileType, flags, fileOffsetInBinary, loadCommands, optional symbols), `Architecture` enum (`.i386`/`.x86_64`/`.arm`/`.arm64`/`.arm64_32`/`.unknown(cpuType:)`), `FileType` enum (`.executable`/`.dylib`/`.dynamicLinker`/`.bundle`/`.object`/...), `LoadCommand` enum (`.dylib(Dylib)`/`.rpath(path:)`/`.uuid(_:)`/`.main(entryOffset:stackSize:)`/`.segment(Segment)`/`.other(rawType:)`), `Segment` and `Section` (with `SegmentProtection` `OptionSet` rendering `r-x` / `rw-` / `rwx` symbolic forms), `Symbol` with `Kind` enum and `nmCode` (`nm(1)`-style type code), `SectionEntropy`. `OWBinaryError` covers the four failure modes (`unreadable`, `unrecognizedMagic`, `malformed`, `truncated`).
- **Load-command coverage**: `LC_LOAD_DYLIB`, `LC_LOAD_WEAK_DYLIB`, `LC_REEXPORT_DYLIB`, `LC_LAZY_LOAD_DYLIB`, `LC_LOAD_UPWARD_DYLIB`, `LC_ID_DYLIB`, `LC_RPATH`, `LC_UUID`, `LC_MAIN`, `LC_SEGMENT`, `LC_SEGMENT_64`, `LC_SYMTAB` (captured for symbol-table parsing; not surfaced as its own variant). Everything else lands in `LoadCommand.other(rawType:)` with the raw 32-bit `cmd` value preserved.
- **`owlwatch inspect <path>`** — second subcommand. Default output: file path, format (Universal vs thin), per-slice architecture / type / flags / load-command count. Flags:
  - `-l` / `--libs` — list every linked dynamic library with `[required\|weak\|self]` tag.
  - `-r` / `--rpaths` — list every `LC_RPATH` entry.
  - `--identity` — print `LC_UUID` and `LC_MAIN` (entry offset + stack size) per slice.
  - `-s` / `--symbols` — list every symbol in `nm(1)`-style format. `--external-only` narrows to imports + exports.
  - `--segments` — list every segment with its sections, sizes, and VM protection (`r-x` / `rw-` / `rwx`).
  - `--entropy` — compute Shannon entropy per section; flag sections above 7.0 bits/byte as `[HIGH]`.
  All flags compose.
- **Shannon entropy primitive** — Single-pass 256-bucket histogram → entropy calculation. Used by `--entropy` and exposed to callers via `OWBinary.entropy(of:fileOffset:length:)` for arbitrary file ranges. Zero-fill sections (`S_ZEROFILL` / `S_GB_ZEROFILL` / `S_THREAD_LOCAL_ZEROFILL`) are skipped in `sectionEntropies` since they have no on-disk bytes.
- **Owlwatch version bump** — `owlwatch --version` now prints `0.3.0-m2`.

## [v0.2.0-m1] — 2026-05-21

The process-inspector milestone. First runnable Owlwatch binary: `owlwatch ps` lists every process visible to the caller as a table or `pstree`-style hierarchy, with optional argv / executable-path / FD-count / per-PID-focus modifiers. The companion library `OWProcess` is the project's first non-stub `OW*` module and is the data foundation every later milestone builds on.

### Added

- **`OWProcess` module** — public surface: `RunningProcess` value type (`pid`, `parentPid`, `name`, `path`, `userId`, `arguments`, `openFiles`); `OpenFile` enum (`.file`/`.socket`/`.pipe`/`.other`); `OWProcess.all(includeArguments:includeOpenFiles:)` and `OWProcess.snapshot(pid:includeArguments:includeOpenFiles:)` static APIs. Backed by libproc (`proc_listpids`, `proc_pidinfo` PROC_PIDTBSDINFO / PROC_PIDLISTFDS / PROC_PIDFDVNODEPATHINFO / PROC_PIDFDSOCKETINFO, `proc_pidpath`) and `sysctl(KERN_PROCARGS2)`. No entitlements required.
- **`owlwatch` executable target** — first shipping binary. Built on Apple's `swift-argument-parser`.
- **`owlwatch ps`** — print the current process table.
  - Default: fixed-width table with `PID`, `PPID`, `USER`, `NAME`.
  - `-p` / `--paths`: append `PATH` column with the executable path.
  - `-a` / `--args`: append `ARGS` column (or inline annotation in tree mode) with `argv[1..]`.
  - `-f` / `--files`: append `FDS` column (or `[N fds]` annotation) with open-file-descriptor count.
  - `-t` / `--tree`: render as a `pstree`-style hierarchy. Processes whose parent is invisible to the caller group under a synthetic `[unavailable](<ppid>)` header.
  - `--pid <PID>`: focus on a single process. In table mode, returns just the matching process. In tree mode, returns the subtree rooted at that PID (without the synthetic-parent header).
- **`owlwatch --version`** — prints `0.2.0-m1`.
- **`Makefile`** — convenience entry points: `build`, `release`, `test`, `install` (places `owlwatch` at `$PREFIX/bin/owlwatch`, default `PREFIX=/usr/local`), `uninstall`, `clean`. Honors `DESTDIR` for packaging.
- **ADR-0003** at `docs/adr/0003-rename-to-owlwatch.md` documenting the post-M0 project rename, superseding the bundle-identifier subsection of ADR-0001.

### Changed

- **Project renamed from `Nightwatch` to `Owlwatch`** per [ADR-0003](docs/adr/0003-rename-to-owlwatch.md). Bundle ID namespace moved from `dev.xorxorjmp.nightwatch.*` to `com.owlwatchlabs.owlwatch.*`; Swift module prefix moved from `NW*` to `OW*`; CLI binary renamed from `nwctl` to `owlwatch`. The `OwlWatch Labs` publisher identity backs `owlwatchlabs.com` (registered). The `v0.1.0-m0` tag retains the old names as a historical artifact; this release is the first under the new identity.
- **Repository transferred to the `owlwatchlabs` GitHub organization** and renamed to `owlwatch-macos`. New URL: `https://github.com/owlwatchlabs/owlwatch-macos`. GitHub auto-redirects every prior URL (`xorxorjmp/nightwatch`, `xorxorjmp/owlwatch`, `owlwatchlabs/owlwatch`) to the current one. External consumers do not need to act; the redirects are permanent.

### Deferred to M2

- **Linked-library enumeration.** Originally listed under M1's "libraries" deliverable. Listing libraries loaded into another process at runtime requires either `task_for_pid` (privileged Mach API restricted on modern macOS) or `proc_pidinfo(PROC_PIDREGIONPATHINFO)` with extension-based filtering of memory-mapped regions. Static analysis of the process binary's `LC_LOAD_DYLIB` load commands is cleaner and lives naturally in the `OWBinary` module, which is M2's home. The deliverable folds into M2 with a real Mach-O backing.

### Notes

- **First runnable binary.** Build with `make release`; install with `sudo make install`. The release binary lands at `/usr/local/bin/owlwatch` by default.
- **Visibility.** `owlwatch ps` from an unprivileged user shell sees ~370 of the host's ~540 processes — the gap is root-owned and SIP-protected processes that `proc_pidinfo` refuses to expose. Running with `sudo` collapses the gap. This is a macOS-level constraint; the tool is honest about what it can and can't see.

## [v0.1.0-m0] — 2026-05-20

The foundation milestone. Establishes the repository, build system, CI, governance, and supporting documentation that every later milestone depends on. No user-visible runtime behavior yet — the macOS menu-bar app and iOS companion are empty SwiftUI shells, and the `owlwatch` CLI does not exist.

> **Historical note.** This tag was published under the project's original name `Nightwatch`, with module prefix `NW*`, bundle ID namespace `dev.xorxorjmp.nightwatch.*`, and CLI name `nwctl`. The project was renamed to Owlwatch shortly after the tag landed (see [ADR-0003](docs/adr/0003-rename-to-owlwatch.md)). The bullets below are written in the post-rename vocabulary; `git checkout v0.1.0-m0` produces the original tree with the prior names intact.

### Added

- **Repository scaffolding** (`apps/`, `extensions/`, `packages/`, `rules/`, `scripts/`, `tools/`, `docs/`) plus the meta files `README.md`, `ROADMAP.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`.
- **Swift 6 SPM package** at `packages/` with 17 library targets (`OWAttest`, `OWBinary`, `OWCodeSigning`, `OWCore`, `OWDNS`, `OWDevices`, `OWEndpoint`, `OWLog`, `OWNetwork`, `OWNetworkExt`, `OWPersistence`, `OWPosture`, `OWProcess`, `OWProtocol`, `OWRules`, `OWStore`, `OWUIKit`) and 17 matching test targets. All compile under `swiftLanguageModes: [.v6]` (strict concurrency).
- **Xcode workspace** (`Owlwatch.xcworkspace`) integrating the SPM package, a macOS menu-bar app target (`apps/Owlwatch/`), and an iOS companion target (`apps/OwlwatchMobile/`). XcodeGen `project.yml` specs are the source of truth; generated `.xcodeproj` files are committed so CI does not need XcodeGen installed.
- **Bundle ID namespace** `com.owlwatchlabs.owlwatch.*` for every current and future target. Documented in ADR-0001.
- **GitHub Actions CI** on `macos-15` runners with six required status checks: `build`, `test`, `lint` (SwiftLint), `codeql` (security-extended queries), `gitleaks`, `rules-validate` (stub until M13).
- **Branch protection on `main`**: PR required, 1 approval, signed commits, linear history, no force pushes, no deletions, no admin bypass (except the documented solo-maintainer review-rule bypass).
- **Pull request template**, `CODEOWNERS`, signed-commit configuration (SSH signing with `allowedSignersFile` for local verification).
- **LICENSE** — Apache License 2.0 at repo root.
- **ADR-0001** at `docs/adr/0001-tech-stack-lock-in.md` — locks Swift 6, SPM, Xcode + XcodeGen, macOS 14 / iOS 17 floors, AppKit + SwiftUI, Endpoint Security and Network Extension framework choices, XCTest, bundle ID namespace, signing posture, and CI runner image.
- **ADR-0002** at `docs/adr/0002-license.md` — records the Apache 2.0 decision, the SPDX-only source-file header convention (`// SPDX-License-Identifier: Apache-2.0`), and "inbound = outbound" contribution model (no separate CLA).
- **ADR conventions** at `docs/adr/README.md` — filename format, section order, never-edit-after-merge rule.
- **Apple restricted-entitlement request scaffold** at `docs/apple-developer/entitlement-requests.md` — drafted justifications for Endpoint Security client (M8), Network Extension content-filter-provider (M7), and Network Extension dns-proxy (M12). Ready to submit once paid Apple Developer Program enrollment completes.
- **Demo infrastructure** at `docs/demos/` — VHS tape placeholders for the CLI/TUI surfaces (`owlwatch.tape` for M1, `console.tape` for M6) and documented screen-capture approach for menu-bar (M2/M3) and iOS (M14) surfaces.
- **Repository configuration spec** at `docs/repo-config.md` — canonical record of intended GitHub settings; the GitHub UI is the source of truth for *applied* configuration, this document is the source of truth for *intended* configuration.

### Governance

- **Conventional Commits** enforced by convention (Commitlint not yet wired; lands when M1 first has many small commits to enforce against).
- **Solo-maintainer review path** documented in `docs/repo-config.md`: until a second maintainer joins, the "Require approvals: 1" rule is satisfied via a documented bypass-list addition; every other branch-protection rule still applies.
- **Private repo posture** documented in `docs/repo-config.md`: the three GitHub Advanced Security features (Secret scanning, Push protection, Private vulnerability reporting) are paid on private repos and deferred until the repository flips public at or before M15. `gitleaks` in CI is the de-facto secret scanner meanwhile.

### Notes

- **No user-installable artifact ships with this tag.** The next runnable binary lands at M1 (`owlwatch ps`); the next visible app surface lands at M2/M3.
- The four planned system extensions — Endpoint Security (M8), Network Extension filter (M7), DNS proxy (M12), Persistence monitor (M10) — exist as placeholder directories under `extensions/` but have no target shells yet. Each lands in its own milestone PR with the appropriate Apple-restricted entitlement (assuming Apple approval has landed by then).

[Unreleased]: https://github.com/owlwatchlabs/owlwatch-macos/compare/v0.9.0-m11...HEAD
[v0.9.0-m11]: https://github.com/owlwatchlabs/owlwatch-macos/releases/tag/v0.9.0-m11
[v0.8.0-m10]: https://github.com/owlwatchlabs/owlwatch-macos/releases/tag/v0.8.0-m10
[v0.7.0-m6]: https://github.com/owlwatchlabs/owlwatch-macos/releases/tag/v0.7.0-m6
[v0.6.0-m5]: https://github.com/owlwatchlabs/owlwatch-macos/releases/tag/v0.6.0-m5
[v0.5.0-m4]: https://github.com/owlwatchlabs/owlwatch-macos/releases/tag/v0.5.0-m4
[v0.4.0-m3]: https://github.com/owlwatchlabs/owlwatch-macos/releases/tag/v0.4.0-m3
[v0.3.0-m2]: https://github.com/owlwatchlabs/owlwatch-macos/releases/tag/v0.3.0-m2
[v0.2.0-m1]: https://github.com/owlwatchlabs/owlwatch-macos/releases/tag/v0.2.0-m1
[v0.1.0-m0]: https://github.com/owlwatchlabs/owlwatch-macos/releases/tag/v0.1.0-m0
