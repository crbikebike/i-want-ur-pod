// Translated from design/kit/components/buttons.html (SHARED KIT EXTRAS: .btn / .btn-primary / .btn-secondary / .btn-tertiary).
// Three pill buttons on the locked token set: Primary (filled), Secondary (accent
// outline), Ghost (soft accent-tint fill). Colors come only from the active
// ThemePalette; sizing/radius/motion from Spacing/Radius/Typography/Motion.
import SwiftUI

// MARK: - Shared style

/// The three button roles from the kit's SHARED KIT EXTRAS block.
/// `ghost` maps to the kit's `.btn-tertiary` (tinted) look.
private enum PillVariant {
    case primary   // .btn-primary  — filled accent (gradient on dark, solid on light)
    case secondary // .btn-secondary — accent outline on transparent
    case ghost     // .btn-tertiary  — soft accent-tint fill
    case neutral   // .btn-secondary on the state screens — chip fill, text-colored label
}

/// One `ButtonStyle` driving all three roles. Matches `.btn`: min-height 44,
/// horizontal gutter padding, pill radius, heavy label, and a spring press
/// scale (0.95) that collapses under reduce-motion.
private struct PillButtonStyle: ButtonStyle {
    let variant: PillVariant

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.rPill999, style: .continuous)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.body.weight(.heavy))   // .95rem / 800
            .tracking(0.152)                          // letter-spacing .01em
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.sp5)        // 0 20px
            .frame(minHeight: 44)
            .background(background)
            .overlay(border)
            .clipShape(shape)
            .modifier(PillShadow(variant: variant, accent: palette.accent))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(
                Motion.resolve(Motion.easeSpring(), reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }

    private var foreground: Color {
        switch variant {
        case .primary:              return palette.onAccent
        case .secondary, .ghost:    return palette.accent
        case .neutral:              return palette.text
        }
    }

    @ViewBuilder private var background: some View {
        switch variant {
        case .primary:
            // Dark: soft accent gradient — `linear-gradient(135deg, accent,
            // color-mix(in srgb, accent 55%, accent-2))` (buttons.html:474).
            // The end stop is accent mixed 45% toward accent-2, NOT full
            // accent-2 (that reads far too green). Light: solid accent (the
            // gradient reads harsh there, per the kit's light override).
            if colorScheme == .dark {
                shape.fill(
                    LinearGradient(
                        colors: [palette.accent, palette.accent.mixed(with: palette.accent2, by: 0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            } else {
                shape.fill(palette.accent)
            }
        case .secondary:
            shape.fill(Color.clear)
        case .ghost:
            shape.fill(palette.accent.opacity(0.14))
        case .neutral:
            // `.btn-secondary` on the state screens: `background: var(--chip)`
            // (search-noresults.html:477).
            shape.fill(palette.chip)
        }
    }

    @ViewBuilder private var border: some View {
        if variant == .secondary {
            // inset 0 0 0 1.5px accent @ 55%
            shape.strokeBorder(palette.accent.opacity(0.55), lineWidth: 1.5)
        }
    }
}

/// Applies the `--elev-sub` coral glow to the primary role only.
private struct PillShadow: ViewModifier {
    let variant: PillVariant
    let accent: Color

    func body(content: Content) -> some View {
        if variant == .primary {
            content.elevSub(color: accent)
        } else {
            content
        }
    }
}

// MARK: - Public buttons

/// Filled accent pill — the kit's `.btn-primary`. Highest-emphasis action.
/// An optional leading SF Symbol matches the kit's `.btn svg` + `gap: 8`.
public struct PrimaryButton: View {
    private let title: String
    private let systemImage: String?
    private let action: () -> Void

    public init(title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            if let systemImage {
                HStack(spacing: 8) {   // .btn gap: 8
                    Image(systemName: systemImage)
                    Text(title)
                }
            } else {
                Text(title)
            }
        }
        .buttonStyle(PillButtonStyle(variant: .primary))
    }
}

/// Accent-outline pill on transparent — the kit's `.btn-secondary`.
public struct SecondaryButton: View {
    private let title: String
    private let action: () -> Void

    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(title, action: action)
            .buttonStyle(PillButtonStyle(variant: .secondary))
    }
}

/// Neutral chip pill with a text-colored label — the kit's `.btn-secondary`
/// as used on the large state screens (search-noresults / search-error), a
/// filled `--chip` rather than the accent outline of `SecondaryButton`.
public struct NeutralButton: View {
    private let title: String
    private let action: () -> Void

    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(title, action: action)
            .buttonStyle(PillButtonStyle(variant: .neutral))
    }
}

/// Soft accent-tint fill — the kit's `.btn-tertiary`. Lowest-emphasis action.
public struct GhostButton: View {
    private let title: String
    private let action: () -> Void

    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(title, action: action)
            .buttonStyle(PillButtonStyle(variant: .ghost))
    }
}

// MARK: - Preview

#Preview("Buttons · Light + Dark") {
    func gallery() -> some View {
        VStack(alignment: .leading, spacing: Spacing.sp4) {
            Text("Primary").typeStyle(Typography.groupLabelStyle)
            HStack(spacing: Spacing.sp3) {
                PrimaryButton(title: "Subscribe all") {}
                PrimaryButton(title: "Play latest") {}
            }

            Text("Secondary").typeStyle(Typography.groupLabelStyle)
            HStack(spacing: Spacing.sp3) {
                SecondaryButton(title: "Share") {}
                SecondaryButton(title: "Add to Up Next") {}
            }

            Text("Ghost").typeStyle(Typography.groupLabelStyle)
            HStack(spacing: Spacing.sp3) {
                GhostButton(title: "See all") {}
                GhostButton(title: "Filters") {}
            }
        }
        .padding(Spacing.sp5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    return VStack(spacing: 0) {
        gallery()
            .background(ThemePalette.dark.groupedBg)
            .environment(\.colorScheme, .dark)
            .environment(\.palette, .dark)

        gallery()
            .background(ThemePalette.light.groupedBg)
            .environment(\.colorScheme, .light)
            .environment(\.palette, .light)
    }
    .ignoresSafeArea()
}
