/// Pure derivations the macOS app uses for at-a-glance triage: a
/// triage-oriented signer classification (Apple recedes, third-party
/// stands out, unsigned alarms), a network-scope classifier that
/// turns a raw IP into one of internet/lan/localhost/ipc/unknown, a
/// well-known-port → service guess, and a tunable "suspicious path"
/// predicate.
///
/// Module is no-I/O, no-Foundation-string-localization. The types
/// here are inputs to the app's color/label rendering (Color comes
/// from a SwiftUI extension on the app side) — see DESIGN.md M18 §1.
public enum OWTriage {}
