import SwiftUI

/// Owlwatch design tokens — colors and font roles. Single source of
/// truth in `docs/DESIGN.md` (sections 1 and 3); this file is a
/// verbatim Swift transcription so callers can write
/// `.foregroundStyle(.owlAmber)` and `.font(.owlMono(13))` without
/// re-deriving values.
///
/// Dark-mode only — no light-theme variants. See `DESIGN.md` §0.

// MARK: - Color tokens (§1)

extension Color {
    // Surfaces
    static let owlBg        = Color(owlHex: 0x0B0E11)
    static let owlSurface   = Color(owlHex: 0x13171C)
    static let owlSurfaceHi = Color(owlHex: 0x1C2128)
    static let owlBorder    = Color(owlHex: 0x2A313A)

    // Text
    static let owlText      = Color(owlHex: 0xE8E6DF)
    static let owlTextMuted = Color(owlHex: 0x9BA1A8)
    static let owlTextDim   = Color(owlHex: 0x5A616A)

    // Brand + signal — apply ONLY where the color carries meaning
    // (signing status, network, capture state). Decoration use is
    // a design-system violation.
    static let owlAmber     = Color(owlHex: 0xE8C95A)  // brand / signed
    static let owlAmberDim  = Color(owlHex: 0x8A7A3E)  // idle status
    static let owlGreen     = Color(owlHex: 0x3FBF95)  // verified / capturing
    static let owlRed       = Color(owlHex: 0xF0726F)  // unsigned / capture live
    static let owlBlue      = Color(owlHex: 0x6FA8E0)  // network / links
}

extension Color {
    /// sRGB hex constructor. Named `owlHex` (not `hex`) to avoid
    /// colliding with any future SwiftUI / Foundation init.
    init(owlHex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((owlHex >> 16) & 0xff) / 255,
            green: Double((owlHex >> 8)  & 0xff) / 255,
            blue:  Double( owlHex        & 0xff) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Font roles (§3)

extension Font {
    /// Space Grotesk 500 — display / wordmark / large headings.
    /// Falls back to the system font if the bundled face fails to
    /// load.
    static func owlDisplay(_ size: CGFloat) -> Font {
        .custom("SpaceGrotesk-Medium", size: size)
    }

    /// Inter 400 — body prose for onboarding / help paragraphs.
    /// Inter is not yet bundled; SwiftUI's `Font.custom` falls back
    /// to the system body face when the name doesn't resolve, so
    /// this still renders something sensible.
    static func owlBody(_ size: CGFloat) -> Font {
        .custom("Inter-Regular", size: size)
    }

    /// JetBrains Mono 400 — the default voice for the entire app.
    /// Data tables, hashes, paths, logs, labels. Fixed-width is
    /// what makes columns of PIDs and hashes align for free.
    static func owlMono(_ size: CGFloat) -> Font {
        .custom("JetBrainsMono-Regular", size: size)
    }
}

// MARK: - Number formatting (§10.13)

/// Locale-grouped integer for counts and totals
/// (`1,200 processes`, `8,503 log entries`). **Never** for
/// identifiers — see ``raw(_:)`` for those.
func grouped(_ value: Int) -> String {
    value.formatted(.number.grouping(.automatic))
}

/// Raw integer with no thousands separators. Use for PIDs, ports,
/// file descriptors, and any identifier the audience reads as a
/// raw value (`pid 9600`, not `pid 9,600`).
func raw<T: BinaryInteger>(_ value: T) -> String {
    String(value)
}
