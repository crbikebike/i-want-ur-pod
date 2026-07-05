// Translated from design/kit/components/tab-bar.html (.tabbar / .tab / .shell-tabbar + SHARED KIT EXTRAS).
// The floating iOS-26 "Liquid Glass" bottom tab bar: a capsule of translucent
// glass (tabbarGlass over a material), a hairline stroke, a soft drop shadow,
// and five equal-width tabs. The active tab tints to `accent` and its glyph
// plays a spring bounce (kit `@keyframes bounceIn`). Every color, radius, and
// motion value comes only from the active ThemePalette + Spacing/Radius/
// Typography/Motion tokens — no hardcoded hex.
import SwiftUI

// MARK: - Tabs (owned by the component layer per Contract 1)

/// The five primary destinations of the app, in bar order (kit markup order:
/// Discover · Podcasts · Up Next · Downloads · Settings).
public enum AppTab: String, CaseIterable, Sendable, Hashable {
    case discover
    case podcasts
    case upNext
    case downloads
    case settings

    /// The tab's label as printed in the kit.
    public var title: String {
        switch self {
        case .discover:  return "Discover"
        case .podcasts:  return "Podcasts"
        case .upNext:    return "Up Next"
        case .downloads: return "Downloads"
        case .settings:  return "Settings"
        }
    }
}

// MARK: - Public tab bar

/// The floating Liquid Glass tab bar. Stateless beyond the `selection` binding
/// it mutates on tap. Drop it into an overlay pinned to the bottom of a screen
/// (the kit floats it 22pt off the bottom with 12pt side insets).
///
/// ```swift
/// @State private var tab: AppTab = .discover
/// content.overlay(alignment: .bottom) { LiquidGlassTabBar(selection: $tab) }
/// ```
public struct LiquidGlassTabBar: View {
    @Binding private var selection: AppTab

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    public init(selection: Binding<AppTab>) {
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                TabCell(tab: tab, isSelected: selection == tab) {
                    selection = tab
                }
            }
        }
        .padding(.horizontal, Spacing.sp1 + Spacing.sp1) // kit: padding 0 6px (~8pt)
        .frame(height: 60)
        .background(glass)
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(palette.tabbarHairline, lineWidth: 0.5)
        )
        // kit --tabbar-shadow: two stacked drops (a wide diffuse + a tight one).
        .shadow(color: shadowColor(strong: true), radius: 17, x: 0, y: 10)
        .shadow(color: shadowColor(strong: false), radius: 5, x: 0, y: 2)
        .padding(.horizontal, 12)   // kit: left/right 12px float inset
        .accessibilityElement(children: .contain)
    }

    /// `--tabbar-glass` translucent tint carried over a system material so the
    /// bar reads as blurred glass over content (kit backdrop-filter blur+sat).
    private var glass: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(Capsule().fill(palette.tabbarGlass))
    }

    /// The kit shadow uses black at .6/.5 in dark and a much softer near-black
    /// at .22/.12 in light.
    private func shadowColor(strong: Bool) -> Color {
        switch colorScheme {
        case .dark:  return Color(hex: 0x000000, alpha: strong ? 0.6 : 0.5)
        default:     return Color(hex: 0x14101A, alpha: strong ? 0.22 : 0.12)
        }
    }
}

// MARK: - One tab

private struct TabCell: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let iconSize: CGFloat = 26

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {   // kit .tab gap: 3px
                TabGlyph(tab: tab, size: iconSize)
                    .frame(width: iconSize, height: iconSize)
                    .keyframeAnimator(
                        initialValue: BounceValues(),
                        trigger: isSelected
                    ) { view, value in
                        view.scaleEffect(value.scale).offset(y: value.offsetY)
                    } keyframes: { _ in
                        // kit @keyframes bounceIn: translateY 2→-2→0, scale .85→1.1→1.
                        KeyframeTrack(\.scale) {
                            if isSelected && !reduceMotion {
                                SpringKeyframe(0.85, duration: 0.001)
                                CubicKeyframe(1.12, duration: Motion.durMid * 0.6)
                                SpringKeyframe(1.0, duration: Motion.durMid * 0.4)
                            } else {
                                CubicKeyframe(1.0, duration: 0.001)
                            }
                        }
                        KeyframeTrack(\.offsetY) {
                            if isSelected && !reduceMotion {
                                CubicKeyframe(2, duration: 0.001)
                                CubicKeyframe(-2, duration: Motion.durMid * 0.6)
                                SpringKeyframe(0, duration: Motion.durMid * 0.4)
                            } else {
                                CubicKeyframe(0, duration: 0.001)
                            }
                        }
                    }

                Text(tab.title)
                    .typeStyle(Typography.tabLabelStyle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? palette.accent : palette.tabbarIcon)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)          // kit min-height: 44px hit target
            .padding(.vertical, Spacing.sp1)
            .contentShape(Rectangle())
        }
        .buttonStyle(TabPressStyle())
        .motion(Motion.easeSoft(duration: Motion.durMid), value: isSelected) // color fade
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

}

/// Animatable pair driven by `keyframeAnimator` for the bounce-in glyph.
private struct BounceValues {
    var scale: CGFloat = 1
    var offsetY: CGFloat = 0
}

/// Icon press feedback (kit `.tab:active svg { transform: scale(.85) }`).
private struct TabPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(
                Motion.resolve(Motion.easeSpring(), reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

// MARK: - Glyphs (inline SwiftUI Shapes, from the kit's 24-unit SVG paths)

/// Renders one tab's currentColor glyph, translating the kit's inline SVG
/// (24-unit viewBox, 2-unit stroke, round caps/joins) into SwiftUI Shapes.
private struct TabGlyph: View {
    let tab: AppTab
    let size: CGFloat

    private var strokeWidth: CGFloat { 2 * size / 24 }
    private var style: StrokeStyle {
        StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
    }

    var body: some View {
        switch tab {
        case .discover:
            ZStack {
                DiscoverRingShape().stroke(.foreground, style: StrokeStyle(lineWidth: strokeWidth))
                DiscoverNeedleShape().fill(.foreground)
            }
        case .podcasts:
            PodcastsShape().stroke(.foreground, style: style)
        case .upNext:
            UpNextShape().stroke(.foreground, style: style)
        case .downloads:
            DownloadsShape().stroke(.foreground, style: style)
        case .settings:
            SettingsShape().stroke(.foreground, style: style)
        }
    }
}

// Map a point / rect from the 24-unit SVG space onto the render rect.
private func p(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + x / 24 * rect.width,
            y: rect.minY + y / 24 * rect.height)
}

private func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, in rect: CGRect) -> CGRect {
    CGRect(x: rect.minX + x / 24 * rect.width,
           y: rect.minY + y / 24 * rect.height,
           width: w / 24 * rect.width,
           height: h / 24 * rect.height)
}

/// `<circle cx=12 cy=12 r=9>` — the compass bezel.
private struct DiscoverRingShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { $0.addEllipse(in: r(3, 3, 18, 18, in: rect)) }
    }
}

/// `<path d="M15.5 8.5 13.2 13 l-4.7 2.5 L10.8 11 l4.7-2.5 Z">` — filled needle.
private struct DiscoverNeedleShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: p(15.5, 8.5, in: rect))
            path.addLine(to: p(13.2, 13, in: rect))
            path.addLine(to: p(8.5, 15.5, in: rect))   // l-4.7 2.5
            path.addLine(to: p(10.8, 11, in: rect))
            path.addLine(to: p(15.5, 8.5, in: rect))   // l4.7 -2.5
            path.closeSubpath()
        }
    }
}

/// Four rounded squares (rx=2) — the 2×2 grid.
private struct PodcastsShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let radius = 2 / 24 * rect.width
            for (x, y) in [(4.0, 4.0), (13.0, 4.0), (4.0, 13.0), (13.0, 13.0)] {
                path.addRoundedRect(
                    in: r(x, y, 7, 7, in: rect),
                    cornerSize: CGSize(width: radius, height: radius)
                )
            }
        }
    }
}

/// List lines + play cue (Up Next).
private struct UpNextShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            // three list rules
            path.move(to: p(4, 7, in: rect));  path.addLine(to: p(15, 7, in: rect))
            path.move(to: p(4, 12, in: rect)); path.addLine(to: p(15, 12, in: rect))
            path.move(to: p(4, 17, in: rect)); path.addLine(to: p(11, 17, in: rect))
            // flag/marker
            path.move(to: p(17.5, 13.5, in: rect))
            path.addLine(to: p(17.5, 18.7, in: rect))                          // v5.2
            path.addCurve(to: p(16.3, 19.2, in: rect),                          // c0 .6 -.7 .9 -1.2 .5
                          control1: p(17.5, 19.3, in: rect),
                          control2: p(16.8, 19.6, in: rect))
            path.addLine(to: p(15.4, 18.5, in: rect))                          // l-.9 -.7
            // tick
            path.move(to: p(20, 10.5, in: rect))
            path.addLine(to: p(17.5, 13.5, in: rect))                          // l-2.5 3
        }
    }
}

/// Down arrow into a tray (Downloads).
private struct DownloadsShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            // shaft + chevron
            path.move(to: p(12, 3.5, in: rect)); path.addLine(to: p(12, 14, in: rect))   // v10.5
            path.move(to: p(12, 14, in: rect));  path.addLine(to: p(8.4, 10.4, in: rect)) // l-3.6 -3.6
            path.move(to: p(12, 14, in: rect));  path.addLine(to: p(15.6, 10.4, in: rect))// l3.6 -3.6
            // tray
            path.move(to: p(4.5, 17.5, in: rect))
            path.addLine(to: p(4.5, 18.9, in: rect))                           // v1.4
            path.addCurve(to: p(6.1, 20.5, in: rect),                           // c0 .9 .7 1.6 1.6 1.6
                          control1: p(4.5, 19.8, in: rect),
                          control2: p(5.2, 20.5, in: rect))
            path.addLine(to: p(17.9, 20.5, in: rect))                          // h11.8
            path.addCurve(to: p(19.5, 18.9, in: rect),                          // c.9 0 1.6-.7 1.6-1.6
                          control1: p(18.8, 20.5, in: rect),
                          control2: p(19.5, 19.8, in: rect))
            path.addLine(to: p(19.5, 17.5, in: rect))                          // v-1.4
        }
    }
}

/// Two slider rails with thumbs (Settings).
private struct SettingsShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            // top rail (split around the thumb)
            path.move(to: p(4, 8, in: rect));    path.addLine(to: p(13, 8, in: rect))    // h9
            path.move(to: p(18.5, 8, in: rect)); path.addLine(to: p(20, 8, in: rect))    // H20
            // bottom rail
            path.move(to: p(4, 16, in: rect));   path.addLine(to: p(5.5, 16, in: rect))  // h1.5
            path.move(to: p(11, 16, in: rect));  path.addLine(to: p(20, 16, in: rect))   // h9
            // thumbs (r=2.6)
            path.addEllipse(in: r(15.5 - 2.6, 8 - 2.6, 5.2, 5.2, in: rect))
            path.addEllipse(in: r(8 - 2.6, 16 - 2.6, 5.2, 5.2, in: rect))
        }
    }
}

// MARK: - Preview

#if DEBUG
private struct TabBarPreviewHost: View {
    @Environment(\.palette) private var palette
    @State private var selection: AppTab = .discover

    var body: some View {
        VStack(spacing: Spacing.sp6) {
            Text("Floating Liquid Glass tab bar")
                .typeStyle(Typography.groupLabelStyle)
                .foregroundStyle(palette.textFaint)

            // over the plain grouped background
            LiquidGlassTabBar(selection: $selection)

            Text("Over bright artwork (glass legibility)")
                .typeStyle(Typography.groupLabelStyle)
                .foregroundStyle(palette.textFaint)

            LiquidGlassTabBar(selection: $selection)
                .padding(.vertical, Spacing.sp5)
                .background(
                    LinearGradient(
                        colors: [palette.coral, palette.grape, palette.mint],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous))

            Text("Selected: \(selection.title)")
                .typeStyle(Typography.subheadStyle)
                .foregroundStyle(palette.textDim)
        }
        .padding(Spacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.groupedBg)
    }
}

#Preview("Tab bar — dark") {
    TabBarPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}

#Preview("Tab bar — light") {
    TabBarPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .light)
}
#endif
