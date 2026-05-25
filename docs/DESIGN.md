# Owlwatch — Design System (macOS app handoff)

> Single source of truth for the Owlwatch macOS app's visual and UX decisions.
> Keep this file in the repo (e.g. `docs/DESIGN.md`). Everything here is final unless
> this file changes. Two facts govern the whole system:
>
> 1. **Dark mode only.** There is no light theme. Lock the app appearance to dark.
> 2. **One minimal mark.** A gold disc with a knockout pupil — no ring, no blades, no gloss.
>
> If you are a coding agent: the tokens, SVG, and Swift below are copy-paste ready.
> Generate the `Color`/`Font` extensions and the asset catalog from them verbatim
> rather than re-deriving values.

---

## 0. Non-negotiables

- Dark mode only — do not implement, expose, or auto-switch to a light theme.
- The mark is a gold disc with a dark/transparent pupil. Nothing else. (`owlwatch-mark.svg` is the master.)
- Monospace is the primary voice for all data and most UI chrome. The product **states facts; it never sells.**
- Use the audience's real vocabulary verbatim: `Mach-O`, `TCC`, `CDHash`, `load command`, `dylib`, `entitlement`. No dumbing-down, no tooltips defining terms the user already knows.
- Sentence case everywhere. Never Title Case, never ALL CAPS, no exclamation points.

---

## 1. Color tokens

The substrate is a calibrated near-black, not pure black. Text is paper-on-slate, never pure white.
Saturated color is **rationed** — it only appears when it carries meaning (signing status, network, capture state).

| Token | Hex | Role |
|---|---|---|
| `owlBg` | `#0B0E11` | Primary window background |
| `owlSurface` | `#13171C` | Raised surface (sidebars, headers, menu bar) |
| `owlSurfaceHi` | `#1C2128` | Higher surface (cards, popovers, selected rows) |
| `owlBorder` | `#2A313A` | Borders, dividers, hairlines |
| `owlText` | `#E8E6DF` | Primary text |
| `owlTextMuted` | `#9BA1A8` | Secondary text, column headers |
| `owlTextDim` | `#5A616A` | Tertiary text, hints, disabled |
| `owlAmber` | `#E8C95A` | **Brand** + signed / known-good |
| `owlAmberDim` | `#8A7A3E` | Idle status dot |
| `owlGreen` | `#3FBF95` | Verified / active / capturing |
| `owlRed` | `#F0726F` | Unsigned / camera or mic live / danger |
| `owlBlue` | `#6FA8E0` | Network / outbound connections / links |

> Note: `#B8881C` (a deeper amber) exists only as a light-background fallback for the **pitch deck**.
> It is **not used in the app** — do not add it to the app palette.

```swift
import SwiftUI

extension Color {
    // Surfaces
    static let owlBg        = Color(hex: 0x0B0E11)
    static let owlSurface   = Color(hex: 0x13171C)
    static let owlSurfaceHi = Color(hex: 0x1C2128)
    static let owlBorder    = Color(hex: 0x2A313A)
    // Text
    static let owlText      = Color(hex: 0xE8E6DF)
    static let owlTextMuted = Color(hex: 0x9BA1A8)
    static let owlTextDim   = Color(hex: 0x5A616A)
    // Brand + signal (use only where the color MEANS something)
    static let owlAmber     = Color(hex: 0xE8C95A) // brand / signed
    static let owlAmberDim  = Color(hex: 0x8A7A3E) // idle status
    static let owlGreen     = Color(hex: 0x3FBF95) // verified / capturing
    static let owlRed       = Color(hex: 0xF0726F) // unsigned / capture live
    static let owlBlue      = Color(hex: 0x6FA8E0) // network / links
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8)  & 0xff) / 255,
                  blue:  Double( hex        & 0xff) / 255,
                  opacity: alpha)
    }
}
```

**Lock the app to dark.** Pick one:

```swift
// SwiftUI: on the root scene
WindowGroup { RootView().preferredColorScheme(.dark) }

// AppKit / app launch
NSApp.appearance = NSAppearance(named: .darkAqua)
```

---

## 2. Status indicator — the mark IS the live indicator

The same mark used as the logo doubles as the runtime status light, in the menu bar and in-app.
Only the **disc color** changes; the pupil is always a **solid black eye, never transparent**.

| State | Disc color | Token |
|---|---|---|
| Idle / nothing capturing | dim gold | `owlAmberDim` |
| Something is capturing data | green | `owlGreen` |
| Camera or microphone is live | red | `owlRed` |

```swift
enum CaptureState { case idle, capturing, cameraOrMicLive }

func statusColor(_ s: CaptureState) -> Color {
    switch s {
    case .idle:             return .owlAmberDim
    case .capturing:        return .owlGreen
    case .cameraOrMicLive:  return .owlRed
    }
}
```

### Menu bar (AppKit)

The menu bar item is an `NSStatusItem`. **Do not use a template image** — macOS forces template
images to monochrome and auto-tints them, which would flatten the gold/green/red states to one gray.
Set `isTemplate = false` and draw the mark in color. Drawing it in code (rather than shipping a
static asset) means the same function produces every state by swapping the tint.

```swift
extension NSColor {
    convenience init(hex: UInt) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff)/255,
                  green:   CGFloat((hex >> 8)  & 0xff)/255,
                  blue:    CGFloat( hex        & 0xff)/255,
                  alpha: 1)
    }
}

/// Owlwatch mark sized for the menu bar. Disc is tinted by capture state;
/// the pupil is a SOLID BLACK eye (never transparent).
func owlStatusImage(tint: NSColor, size: CGFloat = 18) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        tint.setFill()
        NSBezierPath(ovalIn: rect).fill()

        let d = rect.width * 0.38                       // pupil = 38% of diameter
        let pupil = NSRect(x: rect.midX - d/2, y: rect.midY - d/2, width: d, height: d)
        NSColor(hex: 0x0B0E11).setFill()                // solid black pupil — a real eye
        NSBezierPath(ovalIn: pupil).fill()
        return true
    }
    image.isTemplate = false                            // critical: keep our colors
    return image
}

let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.image = owlStatusImage(tint: NSColor(hex: 0x8A7A3E)) // idle

func updateStatus(_ state: CaptureState) {
    let color: NSColor
    switch state {
    case .idle:            color = NSColor(hex: 0x8A7A3E)  // dim gold
    case .capturing:       color = NSColor(hex: 0x3FBF95)  // green
    case .cameraOrMicLive: color = NSColor(hex: 0xF0726F)  // red
    }
    statusItem.button?.image = owlStatusImage(tint: color)
}
```

Red takes precedence over green when both apply (camera/mic live is the most important signal).
Replace the placeholder shield icon with this — and never re-introduce the security-shield cliché.

---

## 3. Typography

Three faces, all open-source (SIL OFL — safe to bundle). Roles are strict.

| Role | Face | Weight | Used for |
|---|---|---|---|
| Display / wordmark | Space Grotesk | 500 | App name, large headings |
| Headings / section titles | Space Grotesk | 500 | Pane titles, sentence case |
| Body prose (rare) | Inter | 400 | Onboarding/help paragraphs only |
| **Data / tables / code / most UI** | JetBrains Mono | 400 | Process rows, hashes, paths, logs, labels — the default |
| Captions / column headers | JetBrains Mono | 400 | 11px muted labels |

Suggested scale (points): display 30 · h1 19 · h2 16 · body 14 · data 13 · caption 11.
Most of the app is **JetBrains Mono 13**; fixed-width is what makes columns of PIDs/hashes align for free.

**Fallbacks** if a face fails to load: data → `SF Mono`, then `Menlo`. Display/body → system.

```swift
extension Font {
    static func owlDisplay(_ size: CGFloat) -> Font {
        .custom("SpaceGrotesk-Medium", size: size)   // verify PostScript name after bundling
    }
    static func owlBody(_ size: CGFloat) -> Font {
        .custom("Inter-Regular", size: size)
    }
    static func owlMono(_ size: CGFloat) -> Font {
        .custom("JetBrainsMono-Regular", size: size)
    }
}
```

**Bundling:** add the `.ttf`/`.otf` files to the target's *Copy Bundle Resources*, then set
`ATSApplicationFontsPath` in `Info.plist` to the folder containing them (e.g. `"Fonts"` or `"."`).
Confirm the exact PostScript names with `fc-scan` or Font Book — the file name is not always the PostScript name.

---

## 4. The mark

Geometry: a filled disc with a centered pupil. **Pupil diameter = 38% of disc diameter.** No ring, no blades, no highlight. The pupil is a **solid black eye** (`#0B0E11`) — never transparent — so the mark reads as a real eye on every surface; everything outside the disc is transparent so it drops onto any dark background.

Master assets: `owlwatch-mark.svg` (transparent background — for in-app and menu-bar use) and `owlwatch-icon.svg` (the mark on a dark tile — the app-icon source). Export the icon to PNGs at the standard macOS sizes.

```swift
struct OwlMark: View {
    /// Disc color. Pass a status color to make the mark double as the live indicator.
    var iris: Color = .owlAmber

    var body: some View {
        Circle()
            .fill(iris)
            .overlay(
                Circle()
                    .fill(Color.owlBg)   // solid black eye — a real pupil, never transparent
                    .scaleEffect(0.38)   // pupil = 38% of mark diameter
            )
            .accessibilityLabel("Owlwatch")
    }
}
```

**App icon:** centered `OwlMark` (amber `#E8C95A`) on a flat `#0B0E11` rounded tile, following Apple's
macOS icon grid. Provide a 1024×1024 master; the mark should occupy roughly the inner 60% of the canvas.

**Favicon / smallest sizes:** the same disc — at 16px the pupil may close up slightly, which is fine.
There is no separate small-size mark because the mark is already minimal.

---

## 5. Layout & spacing

- 4px base grid. Common steps: 4 · 8 · 12 · 16 · 24.
- Corner radius: 8pt for controls and rows, 12pt for cards/popovers.
- Borders: hairline `0.5`pt strokes in `owlBorder`. Never heavy 1–2pt borders.
- Data row height: 24–28pt. Keep rows dense — this audience prefers information density over whitespace.
- Sentence case for every label, heading, button, and column header.

---

## 6. Components & patterns

- **Data tables** are the core surface: JetBrains Mono, left-aligned text columns, right-aligned numeric columns. Columns align naturally because the face is fixed-width.
- **Signing / TCC columns** are color-coded by meaning: `owlAmber` signed, `owlGreen` verified, `owlRed` unsigned/ad-hoc, `owlTextDim` for "not applicable". Never color a row purely for decoration.
- **Network column** uses `owlBlue` for outbound connections.
- **Empty states are factual, never celebratory.** `No persistence items found.` — not "All clear! 🎉". No emoji, no reassurance.
- **Uncertainty is stated plainly.** `Signature could not be verified.` — not "This might be unsafe."
- **Camera/mic live** surfaces the red mark plus a plain banner: `Camera active — com.example.app (pid 887)`.
- Selection/hover uses `owlSurfaceHi` fills, not accent-colored highlights.

---

## 7. Voice & copy rules

The voice reports what is true and trusts the reader to draw conclusions.

- No marketing adjectives: avoid "powerful", "seamless", "effortless", "secure".
- No exclamation points. No celebratory or congratulatory copy.
- Prefer the precise noun: `unsigned binary`, not "unknown app".
- Don't define terms the audience knows. State `CDHash`, don't explain it inline.
- When something is uncertain, say so; don't reassure or alarm.
- Tagline (for chrome/about/empty hero): **`See what's running.`**

---

## 8. Implementation checklist

- [ ] App appearance locked to dark (`.darkAqua` / `.preferredColorScheme(.dark)`).
- [ ] `Color` + `Font` extensions added from sections 1 and 3.
- [ ] Space Grotesk, Inter, JetBrains Mono bundled; `ATSApplicationFontsPath` set; PostScript names verified.
- [ ] `OwlMark` view added; `owlwatch-mark.svg` imported as the app icon source.
- [ ] Menu bar `NSStatusItem` renders `OwlMark` tinted by `statusColor`; red precedes green.
- [ ] Data tables use JetBrains Mono 13 with color-coded signing/TCC/network columns.
- [ ] Empty/error states reviewed against section 7 (factual, no celebration, real terminology).

---

## 9. Navigation architecture

The app is **one window**. No per-feature windows. Use `NavigationSplitView`: a single sidebar of
top-level sections on the left, the selected section's content on the right. Sub-categories
(All Connections / Listeners / TCP…, Launch Services / Login Items / Kexts…) do **not** get their
own sidebar — they live as a segmented control + filter in the section header. The menu bar
dropdown does **not** open windows; each item selects a section in the one window.

### Sections

`Dashboard · Processes · Network · Persistence · Devices · Logs · Inspector`

```swift
enum AppSection: String, CaseIterable, Identifiable {
    case dashboard, processes, network, persistence, devices, logs, inspector
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: "Dashboard"; case .processes: "Processes"
        case .network: "Network"; case .persistence: "Persistence"
        case .devices: "Devices"; case .logs: "Logs"; case .inspector: "Inspector"
        }
    }
    var icon: String {  // SF Symbols
        switch self {
        case .dashboard: "square.grid.2x2"; case .processes: "cpu"
        case .network: "globe"; case .persistence: "play.circle"
        case .devices: "camera"; case .logs: "doc.text"
        case .inspector: "doc.text.magnifyingglass"
        }
    }
}
```

### Shared model + menu bar wiring

One observable model holds the active section (and the capture state from §2). The AppKit
status-item menu calls into it instead of opening windows.

```swift
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var section: AppSection = .dashboard
    @Published var captureState: CaptureState = .idle
    @Published var focus: FocusTarget? = nil          // pending cross-link selection

    /// Bring the single window forward and switch to a section.
    func show(_ section: AppSection) {
        self.section = section
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.identifier?.rawValue == "main" }?.makeKeyAndOrderFront(nil)
    }
}

enum FocusTarget { case process(Int32), socket(UInt64), binary(URL) }  // extend as needed
```

```swift
@main
struct OwlwatchApp: App {
    @StateObject private var model = AppModel.shared
    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(model)
                .tint(.owlAmber)            // selection highlight = amber, NOT system blue
                .preferredColorScheme(.dark)
        }
    }
}
```

Menu bar item (extends §2 — the status item now drives navigation, never opens windows):

```swift
// while building the NSMenu for the status item:
for section in AppSection.allCases {
    let item = NSMenuItem(title: "Open \(section.title)",
                          action: #selector(MenuRouter.open(_:)), keyEquivalent: "")
    item.representedObject = section
    item.target = MenuRouter.shared
    menu.addItem(item)
}

final class MenuRouter: NSObject {
    static let shared = MenuRouter()
    @objc func open(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? AppSection else { return }
        AppModel.shared.show(s)
    }
}
```

### Root view

```swift
struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $model.section) { section in
                SidebarRow(section: section, count: count(for: section)).tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            switch model.section {
            case .dashboard:   DashboardView()
            case .processes:   ProcessesView()
            case .network:     NetworkView()
            case .persistence: PersistenceView()
            case .devices:     DevicesView()
            case .logs:        LogsView()
            case .inspector:   InspectorView()
            }
        }
    }
    func count(for s: AppSection) -> Int? { nil /* wire to live counts */ }
}
```

### Cross-linking (the comfort win)

Detail panels expose **Linked** jumps that switch section and pre-select a target — so a process
links to its sockets, its binary, its TCC history. Route everything through `AppModel`; each
section view reads `model.focus` on appear and clears it.

```swift
// inside a process detail panel:
LinkedRow(icon: "globe", label: "Network · \(socketCount) sockets", tint: .owlBlue) {
    model.focus = .process(pid)
    model.section = .network
}
// inside NetworkView:
.onAppear { if case .process(let pid)? = model.focus { applyProcessFilter(pid); model.focus = nil } }
```

Dashboard summary cards are buttons that drill in the same way (e.g. the TCC card → `.logs` with the
TCC sub-filter applied).

---

## 10. Component styles

One spec + one reusable view per UI object. Sizes in points; colors are §1 tokens; type per §3.
Selection highlight is amber everywhere via the window `.tint(.owlAmber)` — never the system blue.

### 10.1 Sidebar nav row
Icon + label + right-aligned count. Label JBM 13; count JBM 11 `owlTextDim`. Color follows selection.
```swift
struct SidebarRow: View {
    let section: AppSection
    var count: Int?
    var body: some View {
        Label {
            HStack {
                Text(section.title).font(.owlMono(13))
                Spacer()
                if let count { Text(grouped(count)).font(.owlMono(11)).foregroundStyle(.owlTextDim) }
            }
        } icon: { Image(systemName: section.icon) }
    }
}
```

### 10.2 Section header
Title Space Grotesk 16 `owlText`; sub-nav + filter + refresh trailing; 0.5pt `owlBorder` bottom rule.
```swift
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.owlDisplay(16)).foregroundStyle(.owlText)
            trailing
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.owlBorder).frame(height: 0.5) }
    }
}
```

### 10.3 Segmented sub-nav (replaces the per-window sub-sidebars)
Pills JBM 12. Inactive: `owlTextMuted`, border `owlBorder`. Active: fill `owlSurfaceHi`, text
`owlAmber`, border `owlAmberDim`.
```swift
struct SubnavPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.0) { value, label in
                let on = value == selection
                Text(label).font(.owlMono(12))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .foregroundStyle(on ? Color.owlAmber : .owlTextMuted)
                    .background(on ? Color.owlSurfaceHi : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(on ? Color.owlAmberDim : .owlBorder, lineWidth: 0.5))
                    .onTapGesture { selection = value }
            }
        }
    }
}
```

### 10.4 Filter field
Search field JBM 12; placeholder `owlTextDim`; fill `owlSurfaceHi`; radius 7; leading glass.
```swift
struct FilterField: View {
    @Binding var text: String
    var placeholder = "Filter…"
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.owlTextDim)
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(.owlMono(12))
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Color.owlSurfaceHi, in: RoundedRectangle(cornerRadius: 7))
    }
}
```

### 10.5 Data list row
Two-line. Line 1: identifier `owlTextDim` + name `owlText` + trailing StatusPill. Line 2: path
`owlTextDim`, truncate middle. JBM 13/11. Selected row → `owlSurfaceHi`. Padding 8×12.
```swift
struct DataRow: View {
    let id: String            // pass a RAW identifier (see 10.13)
    let name: String
    let path: String?
    let status: SigningStatus?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(id).foregroundStyle(.owlTextDim)
                Text(name).foregroundStyle(.owlText)
                Spacer()
                if let status { StatusPill(status) }
            }.font(.owlMono(13))
            if let path {
                Text(path).font(.owlMono(11)).foregroundStyle(.owlTextDim)
                    .truncationMode(.middle).lineLimit(1)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
    }
}
```

### 10.6 Signing status (colored text, not a heavy chip)
signed → `owlAmber`; verified/active → `owlGreen`; unsigned/danger → `owlRed`; n/a → `owlTextDim`.
```swift
enum SigningStatus {
    case signed(String), verified, unsigned, na
    var label: String {
        switch self { case .signed(let s): s; case .verified: "verified"
                      case .unsigned: "unsigned"; case .na: "n/a" }
    }
    var color: Color {
        switch self { case .signed: .owlAmber; case .verified: .owlGreen
                      case .unsigned: .owlRed; case .na: .owlTextDim }
    }
}
struct StatusPill: View {
    let status: SigningStatus
    init(_ s: SigningStatus) { status = s }
    var body: some View { Text(status.label).font(.owlMono(11)).foregroundStyle(status.color) }
}
```

### 10.7 Enabled/disabled badge (Persistence)
Subtle pill, JBM 11. enabled → `owlGreen` on 12% green; disabled → `owlTextDim` on 12% dim.
```swift
struct StateBadge: View {
    let on: Bool
    var body: some View {
        Text(on ? "enabled" : "disabled").font(.owlMono(11))
            .foregroundStyle(on ? Color.owlGreen : .owlTextDim)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background((on ? Color.owlGreen : Color.owlTextDim).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 5))
    }
}
```

### 10.8 Detail: Linked cross-link row
Icon + label + trailing arrow, tinted by target type. Border `owlBorder`, radius 7, JBM 12.
```swift
struct LinkedRow: View {
    let icon: String; let label: String; let tint: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon); Text(label).font(.owlMono(12)); Spacer()
                Image(systemName: "arrow.right")
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.owlBorder, lineWidth: 0.5))
        }.buttonStyle(.plain)
    }
}
```

### 10.9 Key–value table (Binary Inspector, detail panels)
Label `owlTextMuted` (fixed 120pt column) + value `owlText`, both JBM 12. Parse-error line `owlRed`.
```swift
struct KeyValueRow: View {
    let key: String; let value: String; var valueColor: Color = .owlText
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).foregroundStyle(.owlTextMuted).frame(width: 120, alignment: .leading)
            Text(value).foregroundStyle(valueColor)
            Spacer()
        }.font(.owlMono(12))
    }
}
```

### 10.10 Empty state (quiet — replaces the giant "Select a …" headlines)
Small symbol `owlTextDim` + one muted line JBM 13. Never a large headline. Consistent wording:
"Select a {noun} to see its details."
```swift
struct EmptyState: View {
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet").font(.system(size: 22)).foregroundStyle(.owlTextDim)
            Text(text).font(.owlMono(13)).foregroundStyle(.owlTextMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

### 10.11 Refresh control + timestamp
"last refresh HH:mm:ss · N items" in JBM 11 `owlTextDim`; refresh is a plain
`arrow.clockwise` button in `owlTextMuted`.

### 10.12 List container
Use `List(selection:)` with `.listStyle(.inset)`; set `.listRowSeparatorTint(.owlBorder)` and clear
row insets so `DataRow` controls its own padding. Selection color comes from the window `.tint`.

### 10.13 Number formatting (correctness fix)
**PIDs, ports, and any identifier are never grouped.** Counts/totals are grouped by locale.
```swift
func grouped(_ n: Int) -> String { n.formatted(.number.grouping(.automatic)) } // counts/totals
func raw<T: BinaryInteger>(_ n: T) -> String { String(n) }                      // PIDs, ports
```
