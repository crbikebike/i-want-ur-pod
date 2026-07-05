// Translated from design/kit/components/subscribe-button.html (.sub / .sub.loading / .sub.done / .ring + SHARED KIT EXTRAS spinner).
// A compact 34pt icon-only circle with three states — idle (+), subscribing
// (spinner), subscribed (check) — a radiating pulse ring on subscribe, and a
// 44pt hit target. All color/radius/motion come only from the active
// ThemePalette and the Spacing/Radius/Typography/Elevation/Motion tokens.
import SwiftUI

// MARK: - State (owned by the component layer)

/// The three states of the subscribe control (kit: default `.sub`, `.sub.loading`,
/// `.sub.done`). The parent owns and mutates this; the button renders it and fires
/// `action` on tap.
public enum SubscribeState: Sendable, Hashable, CaseIterable {
    /// Not subscribed — filled accent circle with a `+` glyph.
    case idle
    /// In-flight — non-interactive, shows a spinner.
    case subscribing
    /// Subscribed — surface circle with an accent-2 check + inset ring.
    case subscribed
}

// MARK: - Icon shapes (from the kit's 13×13 inline SVG paths)

/// `.ico-plus` — the kit's `M6.5 1.5v10 M1.5 6.5h10` in a 13-unit viewBox.
private struct PlusShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 13
        var p = Path()
        p.move(to: CGPoint(x: 6.5 * s, y: 1.5 * s))
        p.addLine(to: CGPoint(x: 6.5 * s, y: 11.5 * s))
        p.move(to: CGPoint(x: 1.5 * s, y: 6.5 * s))
        p.addLine(to: CGPoint(x: 11.5 * s, y: 6.5 * s))
        return p
    }
}

/// `.ico-check` — the kit's `M2 7 l3 3 6-7` in a 13-unit viewBox.
private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 13
        var p = Path()
        p.move(to: CGPoint(x: 2 * s, y: 7 * s))
        p.addLine(to: CGPoint(x: 5 * s, y: 10 * s))
        p.addLine(to: CGPoint(x: 11 * s, y: 3 * s))
        return p
    }
}

// MARK: - Spinner (SHARED KIT EXTRAS .spinner)

/// A 12pt ring with a bright leading cap that rotates 360° every 0.7s (`spin`).
/// Collapses to a static ring under reduce-motion.
private struct SubscribeSpinner: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)                       // border ring w/ one gap (top cap)
            .stroke(
                color,
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) {
                    spinning = true
                }
            }
    }
}

// MARK: - Pulse ring (.sub .ring / ringOut)

/// The radiating ring that fires once per subscribe: `2px accent` border that
/// scales 1 → 1.7 while fading 0.8 → 0 over `--dur-row` on `--ease-soft`
/// (kit `@keyframes ringOut`). Re-created (via `.id`) on each subscribe so the
/// animation restarts. Invisible instantly under reduce-motion.
private struct PulseRing: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: 2)
            .frame(width: 34, height: 34)
            .scaleEffect(expanded ? 1.7 : 1.0)
            .opacity(expanded ? 0 : 0.8)
            .onAppear {
                if reduceMotion {
                    expanded = true                          // jump to hidden end-state
                } else {
                    withAnimation(Motion.easeSoft(duration: Motion.durRow)) {
                        expanded = true
                    }
                }
            }
            .allowsHitTesting(false)
    }
}

// MARK: - Press-scale style (.sub:active { scale .85 })

private struct SubscribePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .animation(
                Motion.resolve(Motion.easeSpring(), reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

// MARK: - Subscribe button (public)

/// The compact icon-only subscribe circle from the kit. Stateless itself — the
/// parent supplies `state` and handles the toggle in `action`. A pulse ring
/// fires automatically when `state` transitions into `.subscribed`.
///
/// Visual: 34pt circle inside a 44pt hit target. Idle/subscribing use the
/// accent→accent-2 gradient with an inset white ring; subscribed flips to a
/// `--surface` fill with an accent-2 check and an accent-2 inset ring.
public struct SubscribeButton: View {
    private let state: SubscribeState
    private let action: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Bumped whenever we enter `.subscribed`; keys a fresh `PulseRing`.
    @State private var pulseToken = 0

    public init(state: SubscribeState, action: @escaping () -> Void) {
        self.state = state
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                if pulseToken > 0 {
                    PulseRing(color: palette.accent)
                        .id(pulseToken)
                }
                circle
            }
            .frame(width: 44, height: 44)          // hit target (kit .sub::before inset -5px)
            .contentShape(Circle())
        }
        .buttonStyle(SubscribePressStyle())
        .disabled(state == .subscribing)
        .motion(Motion.easeSpring(), value: state)
        .onChange(of: state) { oldValue, newValue in
            if newValue == .subscribed && oldValue != .subscribed {
                pulseToken += 1
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(state == .subscribed ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Circle visual

    private var isDone: Bool { state == .subscribed }

    @ViewBuilder private var circle: some View {
        icon
            .frame(width: 34, height: 34)
            .background(background)
            .clipShape(Circle())
            .overlay(insetRing)
            .shadow(
                color: Color(hex: 0x000000, alpha: 0.4),
                radius: 6,
                x: 0,
                y: 4
            )
    }

    @ViewBuilder private var icon: some View {
        Group {
            switch state {
            case .idle:
                PlusShape()
                    .stroke(style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .foregroundStyle(palette.onAccent)
                    .frame(width: 15, height: 15)
            case .subscribing:
                SubscribeSpinner(color: palette.onAccent)
            case .subscribed:
                CheckShape()
                    .stroke(style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(palette.accent2)
                    .frame(width: 15, height: 15)
            }
        }
        .transition(.scale.combined(with: .opacity))
    }

    @ViewBuilder private var background: some View {
        if isDone {
            // .sub.done — flat surface fill.
            Circle().fill(palette.surface)
        } else {
            // .sub — 135° accent → accent-2 gradient.
            Circle().fill(
                LinearGradient(
                    colors: [palette.accent, palette.accent2],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    @ViewBuilder private var insetRing: some View {
        if isDone {
            // inset 1.5px accent-2 @ 55%
            Circle().strokeBorder(palette.accent2.opacity(0.55), lineWidth: 1.5)
        } else {
            // inset .5px white @ 28%
            Circle().strokeBorder(Color(hex: 0xFFFFFF, alpha: 0.28), lineWidth: 0.5)
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle:        return "Subscribe"
        case .subscribing: return "Subscribing"
        case .subscribed:  return "Subscribed"
        }
    }
}

// MARK: - Preview

#if DEBUG
private struct SubscribeButtonPreviewHost: View {
    @Environment(\.palette) private var palette

    // Interactive sample so the pulse ring + icon transition are visible.
    @State private var live: SubscribeState = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sp6) {
            Text("States")
                .typeStyle(Typography.groupLabelStyle)
                .foregroundStyle(palette.textFaint)

            HStack(spacing: Spacing.sp6) {
                labeled("Default") { SubscribeButton(state: .idle) {} }
                labeled("Subscribing") { SubscribeButton(state: .subscribing) {} }
                labeled("Subscribed") { SubscribeButton(state: .subscribed) {} }
            }

            Text("Interactive")
                .typeStyle(Typography.groupLabelStyle)
                .foregroundStyle(palette.textFaint)

            labeled(liveTitle) {
                SubscribeButton(state: live) { toggle() }
            }

            Text("In context — floats on artwork")
                .typeStyle(Typography.groupLabelStyle)
                .foregroundStyle(palette.textFaint)

            HStack(spacing: Spacing.sp4) {
                artworkCorner(seed: 2, initial: "A", state: .idle)
                artworkCorner(seed: 5, initial: "9", state: .subscribed)
            }
        }
        .padding(Spacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.groupedBg)
    }

    private var liveTitle: String {
        switch live {
        case .idle:        return "Tap to subscribe"
        case .subscribing: return "Subscribing…"
        case .subscribed:  return "Subscribed"
        }
    }

    private func toggle() {
        switch live {
        case .idle:
            live = .subscribing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { live = .subscribed }
        case .subscribed:
            live = .idle
        case .subscribing:
            break
        }
    }

    private func labeled(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: Spacing.sp2) {
            content()
            Text(title)
                .typeStyle(Typography.tagStyle)
                .foregroundStyle(palette.textDim)
        }
    }

    private func artworkCorner(seed: Int, initial: String, state: SubscribeState) -> some View {
        ArtworkTile(seed: seed, initial: initial)
            .frame(width: 96, height: 96)
            .overlay(alignment: .bottomTrailing) {
                SubscribeButton(state: state) {}
                    .padding(6)
            }
    }
}

#Preview("Subscribe button — light") {
    SubscribeButtonPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .light)
}

#Preview("Subscribe button — dark") {
    SubscribeButtonPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}
#endif
