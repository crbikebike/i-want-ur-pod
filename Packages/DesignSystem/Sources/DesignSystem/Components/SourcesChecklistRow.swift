// Translated from design/kit/components/sources-checklist.html (.srclist / .srow / .src-ico / .switch / .pin / .tag-open / .addkey / .linkbtn + SHARED KIT EXTRAS).
// One row of the grouped "search sources" checklist: a gradient source icon
// (optionally lock-badged when unconfigured), a name with a solid-accent
// "Primary" badge and/or a mint "Open index" tag, subtitle + optional pitch,
// an iOS-style switch, a ghost "Add API key" button, a "Set as primary" link,
// and a drag handle when the row is reorderable.
//
// All structural color/spacing/radius/motion come only from the active
// ThemePalette and the Spacing/Radius/Typography/Elevation/Motion tokens.
// The single exception is the PodcastIndex icon gradient's blue stop: a
// decorative kit hue with no theme role, shared with `ArtworkTile.swift`'s
// `.a2` stop via `KitLiteralColors.podcastIndexBlue` (Theme.swift) rather than
// a hand-copied literal — brand-ramp tokens are reused for every stop that
// matches a brand hue.
import SwiftUI

// MARK: - iOS switch (.switch)

/// The kit's 51×31 iOS toggle: `--seg-track` when off, an `accent-2 → accent`
/// 135° gradient when on, with a 27pt white knob that springs 20pt right.
/// Rendered as a `ToggleStyle` so it keeps native switch accessibility.
private struct IOSSwitchStyle: ToggleStyle {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let isOn = configuration.isOn

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(track(isOn: isOn))
                .frame(width: 51, height: 31)

            Circle()
                .fill(Color.white)
                .frame(width: 27, height: 27)
                .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 2)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .padding(.leading, 2)
                .offset(x: isOn ? 20 : 0)   // 51 - 27 - 2 - 2
        }
        .frame(width: 51, height: 31)
        .contentShape(Capsule())
        .onTapGesture { configuration.isOn.toggle() }
        .animation(Motion.resolve(Motion.easeSpring(), reduceMotion: reduceMotion), value: isOn)
    }

    private func track(isOn: Bool) -> AnyShapeStyle {
        if isOn {
            // linear-gradient(135deg, accent-2, mix(accent-2 62%, accent))
            AnyShapeStyle(
                LinearGradient(
                    colors: [palette.accent2, palette.accent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            AnyShapeStyle(palette.segTrack)
        }
    }
}

// MARK: - Source icon tile (.src-ico + .src-lock)

/// The 46pt gradient source badge with an inset white ring and specular/shade
/// radials (mirrors `.src-ico::after`). A `.src-lock` circle overlaps the
/// bottom-right when the source is unconfigured.
private struct SourceIconTile: View {
    let icon: SourcesChecklistRow.Icon
    let locked: Bool

    @Environment(\.palette) private var palette

    private var gradient: [Color] {
        switch icon {
        // .ic-apple — linear-gradient(140deg, coral, grape)
        case .apple:        return [Brand.coral, Brand.grape]
        // .ic-pi — linear-gradient(140deg, mint, podcastIndexBlue) (decorative kit blue, no role)
        case .podcastIndex: return [Brand.mint, KitLiteralColors.podcastIndexBlue]
        }
    }

    private var symbolName: String {
        switch icon {
        case .apple:        return "applelogo"
        case .podcastIndex: return "dot.radiowaves.left.and.right"
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.rArt14, style: .continuous)

        shape
            .fill(
                LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay {
                RadialGradient(
                    colors: [Color.white.opacity(0.40), .clear],
                    center: UnitPoint(x: 0.30, y: 0.26),
                    startRadius: 0,
                    endRadius: 21
                )
            }
            .overlay {
                RadialGradient(
                    colors: [Color.black.opacity(0.20), .clear],
                    center: UnitPoint(x: 0.78, y: 0.82),
                    startRadius: 0,
                    endRadius: 25
                )
            }
            .overlay {
                Image(systemName: symbolName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .overlay { shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5) }
            .frame(width: 46, height: 46)
            .clipShape(shape)
            .shadow(color: Color.black.opacity(0.5), radius: 5, x: 0, y: 4)
            .overlay(alignment: .bottomTrailing) {
                if locked { lockBadge.offset(x: 4, y: 4) }
            }
            .accessibilityHidden(true)
    }

    private var lockBadge: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(palette.textDim)
            .frame(width: 20, height: 20)
            .background(palette.surface, in: Circle())
            .overlay(Circle().strokeBorder(palette.hairline, lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Badge + tag (.pin / .tag-open)

/// `.pin` — the solid-accent "Primary" badge.
private struct PrimaryBadge: View {
    @Environment(\.palette) private var palette
    var body: some View {
        Text("Primary")
            .typeStyle(Typography.badgeStyle)
            .foregroundStyle(palette.onAccent)
            .padding(.vertical, 3)
            .padding(.horizontal, Spacing.sp2)
            .background(palette.accent, in: Capsule())
    }
}

/// `.tag-open` — the tinted accent-2 "Open index" tag.
private struct OpenIndexTag: View {
    @Environment(\.palette) private var palette
    var body: some View {
        Text("Open index")
            .typeStyle(Typography.badgeStyle)
            .foregroundStyle(palette.accent2)
            .padding(.vertical, 3)
            .padding(.horizontal, Spacing.sp2)
            .background(palette.accent2.opacity(0.15), in: Capsule())
    }
}

// MARK: - Small press style (.btn:active / .linkbtn:active)

private struct PressScale: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(
                Motion.resolve(Motion.easeSpring(), reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

// MARK: - Add-key ghost button (.btn.btn-ghost.addkey) + link button (.linkbtn)

/// `.addkey` — a compact accent-outline ghost button with a key glyph.
private struct AddKeyButton: View {
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "key.fill").font(.system(size: 13, weight: .bold))
                Text("Add API key")
            }
            .font(Typography.subhead.weight(.heavy))
            .foregroundStyle(palette.accent)
            .padding(.horizontal, Spacing.sp4)
            .frame(minHeight: 38)
            .overlay(Capsule().strokeBorder(palette.accent.opacity(0.6), lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
    }
}

/// `.linkbtn` — a borderless accent link with a small up-arrow ("Set as primary").
private struct SetPrimaryLink: View {
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold))
                Text("Set as primary")
            }
            .font(Typography.subhead.weight(.bold))
            .foregroundStyle(palette.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
    }
}

// MARK: - Sources checklist row (public)

/// One row of the "search sources" grouped checklist. Stateless itself: the
/// parent supplies presentation flags and an optional enabled `Binding`, and
/// handles "Add API key" / "Set as primary" via the closures.
///
/// - Pass `isEnabled: nil` for an unconfigured source (no switch is shown —
///   pair with `isLocked: true`, `pitch:`/`keyHint:` and `onAddKey:`).
/// - Pass a `Binding` once the source is configured to show the iOS switch.
public struct SourcesChecklistRow: View {

    /// Which source this row represents (drives the gradient icon glyph).
    public enum Icon: Sendable, Hashable {
        case apple
        case podcastIndex
    }

    private let icon: Icon
    private let name: String
    private let subtitle: String
    private let isEnabled: Binding<Bool>?
    private let isPrimary: Bool
    private let isOpenIndex: Bool
    private let isLocked: Bool
    private let isFeatured: Bool
    private let pitch: String?
    private let keyHint: String?
    private let isReorderable: Bool
    private let onAddKey: (() -> Void)?
    private let onSetPrimary: (() -> Void)?

    @Environment(\.palette) private var palette

    public init(
        icon: Icon,
        name: String,
        subtitle: String,
        isEnabled: Binding<Bool>?,
        isPrimary: Bool = false,
        isOpenIndex: Bool = false,
        isLocked: Bool = false,
        isFeatured: Bool = false,
        pitch: String? = nil,
        keyHint: String? = nil,
        isReorderable: Bool = false,
        onAddKey: (() -> Void)? = nil,
        onSetPrimary: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.name = name
        self.subtitle = subtitle
        self.isEnabled = isEnabled
        self.isPrimary = isPrimary
        self.isOpenIndex = isOpenIndex
        self.isLocked = isLocked
        self.isFeatured = isFeatured
        self.pitch = pitch
        self.keyHint = keyHint
        self.isReorderable = isReorderable
        self.onAddKey = onAddKey
        self.onSetPrimary = onSetPrimary
    }

    /// A tall row (`.srow-tall`, top-aligned) whenever it carries stacked
    /// pitch/hint/action content beneath the subtitle.
    private var isTall: Bool {
        pitch != nil || keyHint != nil || onAddKey != nil || onSetPrimary != nil
    }

    public var body: some View {
        HStack(alignment: isTall ? .top : .center, spacing: Spacing.sp3) {
            SourceIconTile(icon: icon, locked: isLocked)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.sp2) {
                    Text(name)
                        .typeStyle(Typography.rowTitleStyle)
                        .foregroundStyle(palette.text)
                    if isPrimary { PrimaryBadge() }
                    if isOpenIndex { OpenIndexTag() }
                }

                Text(subtitle)
                    .typeStyle(Typography.subheadStyle)
                    .foregroundStyle(palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)

                if let pitch {
                    Text(pitch)
                        .typeStyle(Typography.subheadStyle)
                        .foregroundStyle(palette.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }

                if onAddKey != nil || onSetPrimary != nil || keyHint != nil {
                    keyActions.padding(.top, Spacing.sp3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.vertical, Spacing.sp3)
        .padding(.horizontal, Spacing.sp4)
        .background {
            if isFeatured {
                // .srow-featured — color-mix(accent-2 7%, transparent)
                palette.accent2.opacity(0.07)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: Key-actions row (.key-actions)

    @ViewBuilder private var keyActions: some View {
        HStack(spacing: Spacing.sp3) {
            if let onAddKey { AddKeyButton(action: onAddKey) }
            if let onSetPrimary { SetPrimaryLink(action: onSetPrimary) }
            if let keyHint {
                Label {
                    Text(keyHint).font(Typography.subhead)
                } icon: {
                    Image(systemName: "lock.fill").font(.system(size: 11, weight: .semibold))
                }
                .labelStyle(.titleAndIcon)
                .foregroundStyle(palette.textFaint)
            }
        }
    }

    // MARK: Trailing controls (switch + drag handle)

    @ViewBuilder private var trailing: some View {
        HStack(spacing: Spacing.sp3) {
            if let isEnabled {
                Toggle(isOn: isEnabled) { Text(name) }
                    .labelsHidden()
                    .toggleStyle(IOSSwitchStyle())
                    .accessibilityLabel("Enable \(name)")
            }
            if isReorderable {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textFaint)
                    .accessibilityLabel("Reorder \(name)")
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
private struct SourcesChecklistPreviewHost: View {
    @Environment(\.palette) private var palette

    @State private var appleOn = true
    @State private var piOn = true
    @State private var appleOn2 = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sp5) {
            Text("Not yet configured (default)")
                .typeStyle(Typography.groupLabelStyle)
                .foregroundStyle(palette.textFaint)

            list {
                SourcesChecklistRow(
                    icon: .apple,
                    name: "Apple Podcasts",
                    subtitle: "iTunes directory · No key needed",
                    isEnabled: $appleOn,
                    isPrimary: true
                )
                separator
                SourcesChecklistRow(
                    icon: .podcastIndex,
                    name: "PodcastIndex",
                    subtitle: "The independent, community-run podcast directory.",
                    isEnabled: nil,
                    isOpenIndex: true,
                    isLocked: true,
                    isFeatured: true,
                    pitch: "Indie-first and free. Add your own API key (key + secret) to switch it on.",
                    keyHint: "Inactive until a key is added",
                    onAddKey: {}
                )
            }
            footnote("Primary is searched first; other enabled sources are fallback. Results are never merged.")

            Text("PodcastIndex key added")
                .typeStyle(Typography.groupLabelStyle)
                .foregroundStyle(palette.textFaint)
                .padding(.top, Spacing.sp2)

            list {
                SourcesChecklistRow(
                    icon: .apple,
                    name: "Apple Podcasts",
                    subtitle: "iTunes directory · No key needed",
                    isEnabled: $appleOn2,
                    isPrimary: true
                )
                separator
                SourcesChecklistRow(
                    icon: .podcastIndex,
                    name: "PodcastIndex",
                    subtitle: "Connected · key ending ••3F",
                    isEnabled: $piOn,
                    isOpenIndex: true,
                    isReorderable: true,
                    onSetPrimary: {}
                )
            }
            footnote("With two sources on, drag or \"Set as primary\" to choose which one leads; the other becomes fallback.")
        }
        .padding(Spacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.groupedBg)
    }

    private func list<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous))
            .elevList(hairline: palette.hairline)
    }

    private var separator: some View {
        Rectangle()
            .fill(palette.separator)
            .frame(height: 0.5)
            .padding(.leading, Spacing.sp4 + 46 + Spacing.sp3)  // .srow::after inset
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(Typography.subhead)
            .foregroundStyle(palette.textFaint)
            .padding(.horizontal, Spacing.sp2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Sources checklist — light") {
    SourcesChecklistPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .light)
}

#Preview("Sources checklist — dark") {
    SourcesChecklistPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}
#endif
