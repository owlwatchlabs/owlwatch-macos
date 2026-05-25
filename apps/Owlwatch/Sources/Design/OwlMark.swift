import SwiftUI

/// The Owlwatch mark — a gold disc with a solid dark pupil.
/// Doubles as the live status indicator: passing a status color as
/// `iris` makes the same view that brands the app also surface the
/// runtime capture state. See `docs/DESIGN.md` §2 and §4.
///
/// Geometry: pupil diameter is 38% of disc diameter, per spec.
/// Pupil is ``Color/owlBg`` — a solid black eye, never transparent.
struct OwlMark: View {
    /// Disc color. Defaults to the brand amber; pass a
    /// ``CaptureState`` color to make the mark double as the live
    /// status light.
    var iris: Color = .owlAmber

    var body: some View {
        Circle()
            .fill(iris)
            .overlay(
                Circle()
                    .fill(Color.owlBg)
                    .scaleEffect(0.38)
            )
            .accessibilityLabel("Owlwatch")
    }
}
