// Shared "gear pushes Settings" affordance (E8-S4): "A gear glyph in the
// top-right corner of Home/Shows/Up Next pushes the Settings screen." Home
// (`HomeScreen.swift`) originated this exact treatment translating
// `home.html`'s `.util-gear` — a 40pt chip-fill circle floating over the
// scroll content; this extracts that shape so Shows (`PodcastsScreen`) and Up
// Next (`UpNextScreen`) present it identically rather than re-describing it.
import SwiftUI
import DesignSystem

/// A distinct route type pushed onto a screen's `NavigationPath` alongside
/// whatever else it pushes (e.g. `URL` for Podcast Detail) — a `NavigationPath`
/// holds multiple `Hashable` types, each resolved by its own
/// `navigationDestination(for:)`.
enum SettingsRoute: Hashable {
    case settings
}

/// The top-right gear button itself. Callers place it in a `ZStack(alignment:
/// .topTrailing)` overlay over their scroll content (matching `home.html`'s
/// `position: absolute; top: 58px; right: var(--gutter)`) and supply the
/// action that pushes `SettingsRoute.settings` onto their own path.
struct SettingsGearButton: View {
    let action: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.text)
                .frame(width: 40, height: 40)
                .background(palette.chip, in: Circle())
                .overlay(Circle().strokeBorder(palette.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }
}
