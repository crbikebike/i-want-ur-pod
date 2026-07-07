// Translated from design/kit/components/tab-bar.html (.tabbar / .tab / .shell-tabbar
// + the search-takeover state + SHARED KIT EXTRAS).
// The floating iOS-26 "Liquid Glass" bottom tab bar: a capsule of translucent
// glass (tabbarGlass over a material), a hairline stroke, a soft drop shadow,
// and (2026-07-05 dock IA revision) four equal-width tabs — Home · Shows ·
// Up Next · Search. The active tab tints to `accent` and its glyph plays a
// spring bounce (kit `@keyframes bounceIn`). Tapping Search turns the same
// glass capsule into a search-takeover field (kit `.tabbar.takeover` /
// `.tb-home` / `.tb-field` / `.tb-cancel`): a pinned Home glyph on the left,
// a `--field`-styled text field in the middle, and a ✕ cancel on the right.
// Every color, radius, and motion value comes only from the active
// ThemePalette + Spacing/Radius/Typography/Motion tokens — no hardcoded hex.
//
// Contract 1 (frozen): this component owns no app/search state beyond what's
// passed in — `selection`/`searchQuery` are bindings, `onCancelSearch` is a
// callback the app supplies to restore whatever tab was active before Search
// was tapped. No app-target imports here, so this stays previewable in the
// package in isolation.
import SwiftUI

// MARK: - Tabs (owned by the component layer per Contract 1)

/// The app's primary destinations, in dock order (2026-07-05 IA revision:
/// Home · Shows · Up Next · Search — replacing the prior five-item bar).
/// Search has no standalone screen of its own in the bar; tapping it drives
/// the takeover below instead of switching to a plain content screen.
public enum AppTab: String, CaseIterable, Sendable, Hashable {
    case home
    case shows
    case upNext
    case search

    /// The tab's label as printed in the kit.
    public var title: String {
        switch self {
        case .home:   return "Home"
        case .shows:  return "Shows"
        case .upNext: return "Up Next"
        case .search: return "Search"
        }
    }
}

// MARK: - Public tab bar

/// The floating Liquid Glass tab bar / search takeover. Stateless beyond the
/// bindings it mutates on tap. Drop it into an overlay pinned to the bottom
/// of the shell (the kit floats it 22pt off the bottom with 12pt side insets).
///
/// ```swift
/// @State private var tab: AppTab = .home
/// @State private var query = ""
/// content.overlay(alignment: .bottom) {
///     LiquidGlassTabBar(selection: $tab, searchQuery: $query) {
///         tab = previousTab
///     }
/// }
/// ```
///
/// Selecting `.search` (either by tapping the Search icon, or because the
/// caller sets `selection` to `.search` directly) puts the bar into takeover:
/// the four icons collapse into a pinned Home glyph, a search field bound to
/// `searchQuery`, and a ✕ that calls `onCancelSearch`. Tapping the pinned
/// Home glyph sets `selection = .home` directly (self-contained — it always
/// means "go to Home"); the ✕ defers to the caller via `onCancelSearch` since
/// only the caller knows which tab was active before the takeover began.
public struct LiquidGlassTabBar: View {
    @Binding private var selection: AppTab
    @Binding private var searchQuery: String
    private let onCancelSearch: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFieldFocused: Bool

    /// - Parameters:
    ///   - selection: The active tab. Setting it to `.search` (from a tap or
    ///     externally) enters the takeover.
    ///   - searchQuery: The takeover field's text, bound to the caller's
    ///     search state (e.g. a view model's `query`).
    ///   - onCancelSearch: Called when ✕ is tapped — the caller restores
    ///     whichever tab was active before Search.
    public init(
        selection: Binding<AppTab>,
        searchQuery: Binding<String> = .constant(""),
        onCancelSearch: @escaping () -> Void = {}
    ) {
        self._selection = selection
        self._searchQuery = searchQuery
        self.onCancelSearch = onCancelSearch
    }

    private var isTakeoverActive: Bool { selection == .search }

    public var body: some View {
        HStack(spacing: 0) {
            if isTakeoverActive {
                takeoverContent
            } else {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    TabCell(tab: tab, isSelected: selection == tab) {
                        selection = tab
                    }
                }
            }
        }
        .padding(.horizontal, isTakeoverActive ? Spacing.sp2 : Spacing.sp1 + Spacing.sp1) // kit: takeover padding 0 8px, else ~8pt
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
        .onChange(of: isTakeoverActive) { _, active in
            isSearchFieldFocused = active
        }
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

    // MARK: - Search takeover (.tb-home / .tb-field / .tb-cancel)

    private var takeoverContent: some View {
        HStack(spacing: Spacing.sp2) {
            Button {
                selection = .home
            } label: {
                TabGlyph(tab: .home, size: 22)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(TabPressStyle())
            .foregroundStyle(palette.tabbarIcon)
            .accessibilityLabel("Home")

            searchField

            Button {
                searchQuery = ""
                onCancelSearch()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(TabPressStyle())
            .foregroundStyle(palette.textFaint)
            .accessibilityLabel("Cancel search")
        }
    }

    /// `.tb-field` — reuses the `--field`/`--r-field` token styling
    /// `SearchField` already carries, sized to fit inline in the bar.
    private var searchField: some View {
        HStack(spacing: Spacing.sp2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.textFaint)

            TextField("", text: $searchQuery, prompt: Text("Shows, people, topics").foregroundStyle(palette.textDim))
                .focused($isSearchFieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(palette.text)
                .submitLabel(.search)
        }
        .padding(.horizontal, Spacing.sp3)
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(palette.field, in: RoundedRectangle(cornerRadius: Radius.rField11, style: .continuous))
        .animation(nil, value: isTakeoverActive)
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

/// Icon press feedback (kit `.tab:active svg { transform: scale(.85) }`,
/// `.tb-home:active`/`.tb-cancel:active` in takeover).
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
        case .home:
            HomeShape().stroke(.foreground, style: style)
        case .shows:
            ShowsShape().stroke(.foreground, style: style)
        case .upNext:
            UpNextShape().stroke(.foreground, style: style)
        case .search:
            SearchShape().stroke(.foreground, style: style)
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

/// `<path d="M3.5 11.2 12 4l8.5 7.2"...>` roofline + walls + door — the
/// kit's new Home glyph (tab-bar.html's `.tab` sample, Home active).
private struct HomeShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            // roofline
            path.move(to: p(3.5, 11.2, in: rect))
            path.addLine(to: p(12, 4, in: rect))
            path.addLine(to: p(20.5, 11.2, in: rect))
            // walls (v9.5, rounded corners approximated as straight — close enough
            // at glyph scale; the kit itself uses simple line segments here)
            path.move(to: p(5.8, 9.7, in: rect))
            path.addLine(to: p(5.8, 19.2, in: rect))
            path.addLine(to: p(16, 19.2, in: rect))
            path.addLine(to: p(16, 9.7, in: rect))
            // door
            path.move(to: p(9.6, 20.3, in: rect))
            path.addLine(to: p(9.6, 15.2, in: rect))
            path.addLine(to: p(13.5, 15.2, in: rect))
            path.addLine(to: p(13.5, 20.3, in: rect))
        }
    }
}

/// Four rounded squares (rx=2) — the 2×2 grid (Shows, née Podcasts).
private struct ShowsShape: Shape {
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

/// A magnifying glass — the kit's new Search glyph (circle r=6.5 + handle).
private struct SearchShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.addEllipse(in: r(11 - 6.5, 11 - 6.5, 13, 13, in: rect))
            path.move(to: p(15.8, 15.8, in: rect))
            path.addLine(to: p(20.5, 20.5, in: rect))
        }
    }
}

// MARK: - Preview

#if DEBUG
private struct TabBarPreviewHost: View {
    @Environment(\.palette) private var palette
    @State private var selection: AppTab = .home
    @State private var query = ""
    @State private var previousTab: AppTab = .home

    var body: some View {
        VStack(spacing: Spacing.sp6) {
            Text("Floating Liquid Glass tab bar")
                .typeStyle(Typography.groupLabelStyle)
                .foregroundStyle(palette.textFaint)

            // over the plain grouped background
            LiquidGlassTabBar(selection: tabBinding, searchQuery: $query) {
                selection = previousTab
            }

            Text("Over bright artwork (glass legibility)")
                .typeStyle(Typography.groupLabelStyle)
                .foregroundStyle(palette.textFaint)

            LiquidGlassTabBar(selection: tabBinding, searchQuery: $query) {
                selection = previousTab
            }
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

    private var tabBinding: Binding<AppTab> {
        Binding(
            get: { selection },
            set: { newValue in
                if newValue == .search && selection != .search { previousTab = selection }
                selection = newValue
            }
        )
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
