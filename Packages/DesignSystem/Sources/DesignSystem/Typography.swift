// Type scale. Design source: docs/design/direction.md §3 (type scale table).
// Display roles use IBM Plex Mono (brand display face); everything else uses
// Roboto — which is NOT bundled (see FontRegistration.swift), so UI/body roles
// fall back to the system font. rem→pt uses the web root of 16pt (1rem = 16pt).
// Tracking below is precomputed in points (em × size). Weights map:
// 800→.heavy, 700→.bold, 600→.semibold, 500→.medium.
import SwiftUI

/// A resolved type token: font + letter tracking + optional uppercasing.
/// Apply with `.typeStyle(_:)` so tracking and case (which `Font` alone cannot
/// carry) are honored on the rendered `Text`/`View`.
public struct TypeStyle: Sendable {
    public let font: Font
    public let tracking: CGFloat
    public let uppercase: Bool

    public init(font: Font, tracking: CGFloat = 0, uppercase: Bool = false) {
        self.font = font
        self.tracking = tracking
        self.uppercase = uppercase
    }
}

/// Font + type-token helpers matching the direction.md §3 table verbatim.
/// The `Font` accessors are the primary API (named per spec); the matching
/// `*Style` tokens additionally carry tracking/case for `.typeStyle(_:)`.
public enum Typography {

    // MARK: Font family names

    /// Bundled brand display face (IBM Plex Mono, Regular only — see FontRegistration).
    public static let displayFontName = FontRegistration.displayFontName

    private static func display(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        // Only the Regular weight of IBM Plex Mono is bundled; a heavier
        // `weight` is requested for forward-compat but renders Regular until
        // the extra faces ship, then falls back to the system mono/display.
        Font.custom(displayFontName, size: size).weight(weight)
    }

    private static func ui(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        // Roboto is not bundled — use the system font at the target weight.
        Font.system(size: size, weight: weight)
    }

    // MARK: Roles (Font accessors — exact spec names)

    /// Large title — 2.32rem / 800 / -0.02em. Display face.
    public static var displayLargeTitle: Font { display(37.12, .heavy) }
    /// Section (h2) — 1.34rem / 800 / -0.015em. Display face.
    public static var section: Font { display(21.44, .heavy) }
    /// Nav title (inline) — 1.06rem / 800 / -0.01em. Display face.
    public static var navTitle: Font { display(16.96, .heavy) }
    /// Shelf header (result-row.html `.sh-title`) — 1.18rem / 800 / -0.015em.
    /// Display face, per direction.md §3's prose ("shelf headers" use
    /// `--font-display`) — filling a gap the type-scale table itself omitted.
    public static var shelfTitle: Font { display(18.88, .heavy) }
    /// Row title — 1rem / 700 / -0.01em. UI face.
    public static var rowTitle: Font { ui(16, .bold) }
    /// Body / input — 1rem / 500. UI face.
    public static var body: Font { ui(16, .medium) }
    /// Subhead / author — 0.82rem / 500. UI face.
    public static var subhead: Font { ui(13.12, .medium) }
    /// Settings group label — 0.72rem / 800 / 0.06em, uppercase. UI face.
    public static var groupLabel: Font { ui(11.52, .heavy) }
    /// Badge / tag (Primary, Open index) — 0.62rem / 800 / 0.04em, uppercase. UI face.
    public static var badge: Font { ui(9.92, .heavy) }
    /// Eyebrow — 0.72rem / 800 / 0.12em, uppercase. UI face.
    public static var eyebrow: Font { ui(11.52, .heavy) }
    /// Tag — 0.64rem / 800 / 0.02em, uppercase. UI face.
    public static var tag: Font { ui(10.24, .heavy) }
    /// Tab label — 0.62rem / 600 / 0.01em. UI face.
    public static var tabLabel: Font { ui(9.92, .semibold) }

    // MARK: Roles — search + Podcast Detail reconciliation
    // Exact kit values verified against design/kit/screens/{search-results,
    // podcast-detail-*}.html; see docs/design/token-audit.md. All UI face
    // (Roboto/system) — none carry `--font-display`.

    /// Story-arc card title (`.arc-name`) — 0.92rem / 800 / -0.01em.
    public static var arcCardTitle: Font { ui(14.72, .heavy) }
    /// Story-arc card meta / "N episodes" (`.arc-parts`) — 0.76rem / 600.
    public static var arcCardMeta: Font { ui(12.16, .semibold) }
    /// Season badge over an arc cover (`.arc-season`) — 0.68rem / 800.
    public static var seasonBadge: Font { ui(10.88, .heavy) }
    /// Filled pill-button label (`.sub` subscribe pill / `.arc-add`) — 0.8rem / 800.
    /// (`.sub` adds 0.01em tracking; `.arc-add` carries none — see the two styles.)
    public static var pillButtonLabel: Font { ui(12.8, .heavy) }
    /// Top-result hero title (`.tr-title`) — 1.08rem / 800 / -0.01em.
    public static var heroTitle: Font { ui(17.28, .heavy) }
    /// Top-result hero author (`.tr-author`) — 0.84rem / 500 (distinct from subhead's 0.82).
    public static var heroAuthor: Font { ui(13.44, .medium) }
    /// Section count pill (`.sec-head .count`) — 0.74rem / 800.
    public static var countBadge: Font { ui(11.84, .heavy) }
    /// Episode row title (`.ep-title`) — 0.98rem / 700 / -0.01em.
    public static var episodeTitle: Font { ui(15.68, .bold) }
    /// Episode row meta line (`.ep-meta`) — 0.78rem / 600.
    public static var episodeMeta: Font { ui(12.48, .semibold) }
    /// Emphasised meta segment (`.ep-arc` — the arc name inside a meta line):
    /// the meta size at 800, paired with an accent-2 color at the call site.
    public static var metaEmphasis: Font { ui(12.48, .heavy) }
    /// "Played" marker (`.ep-played`) — 0.72rem / 800, accent-2 at the call site.
    public static var shelfBadge: Font { ui(11.52, .heavy) }
    /// Podcast Detail header title (`.pd-title`) — 1.28rem / 800 / -0.02em.
    /// UI face (explicitly NOT the mono `--font-display` title role).
    public static var podcastDetailTitle: Font { ui(20.48, .heavy) }
    /// Podcast Detail author (`.pd-author`) — 0.88rem / 600.
    public static var detailAuthor: Font { ui(14.08, .semibold) }
    /// Podcast Detail category (`.pd-cat`) — 0.72rem / 800 / 0.07em, uppercase.
    public static var categoryLabel: Font { ui(11.52, .heavy) }
    /// Podcast Detail description body (`.pd-desc`) — 0.88rem / 400.
    public static var detailBody: Font { ui(14.08, .regular) }
    /// Expand / "More" affordance (`.pd-more`) — 0.82rem / 800.
    public static var expandLabel: Font { ui(13.12, .heavy) }
    /// Centered footer note (`.foot`) — 0.76rem / 500, `--text-faint` at the
    /// call site. Same size as `.arc-parts` but a lighter (medium) weight.
    public static var footnote: Font { ui(12.16, .medium) }

    // MARK: Roles — Shows tab (poster grid) reconciliation
    // Exact kit values verified against design/kit/screens/shows.html's
    // `.pod-title` / `.pod-studio`. Distinct from `arcCardTitle`/`episodeMeta`
    // despite matching sizes — those are 800/600 weight, these are 700/500 —
    // so they're their own tokens rather than reused near-misses.

    /// Poster card title (`.pod-title`) — 0.92rem / 700 / -0.01em, 2-line clamp.
    public static var showCardTitle: Font { ui(14.72, .bold) }
    /// Poster card studio/author (`.pod-studio`) — 0.78rem / 500, 1-line ellipsis.
    public static var showCardStudio: Font { ui(12.48, .medium) }

    // MARK: Roles — Home rails reconciliation (Up Next / New episodes)
    // Exact kit values verified against design/kit/screens/home.html's
    // `.pn-title` / `.pn-time` / `.ep-title` / `.ep-podcast` / `.ep-date` /
    // `.tag` (lines ~547-630).

    /// Up Next tile title (`.pn-title`) — 0.86rem / 700 / -0.01em.
    public static var upNextTileTitle: Font { ui(13.76, .bold) }
    /// Up Next tile remaining time (`.pn-time`) — 0.76rem / 500.
    public static var upNextTileTime: Font { ui(12.16, .medium) }
    /// New-episode card title (`.ep-title`) — 0.98rem / 700 / -0.01em.
    public static var newEpisodeTitle: Font { ui(15.68, .bold) }
    /// New-episode card podcast name (`.ep-podcast`) — 0.8rem / 500.
    public static var newEpisodePodcast: Font { ui(12.8, .medium) }
    /// New-episode card date (`.ep-date`) — 0.74rem / 600.
    public static var newEpisodeDate: Font { ui(11.84, .semibold) }
    /// Standalone chip (`.tag` / `.tag.hot`) — 0.64rem / 800 / +0.02em, uppercase.
    public static var tagChip: Font { ui(10.24, .heavy) }

    // MARK: Roles — Add Feed by URL sheet reconciliation
    // Exact kit values verified against design/kit/screens/add-feed-url.html's
    // `.afu-title` / `.afu-lede` / `.afu-paste` / `.afu-note` / `.afu-add` /
    // `.afu-success .s-title` / `.s-sub`. None of the existing roles above
    // land on these exact size/weight/tracking combinations, so they're new
    // tokens rather than near-miss reuses.

    /// Sheet header title (`.afu-title`) — 1.12rem / 700 / -0.01em. Display face.
    public static var sheetTitle: Font { display(17.92, .bold) }
    /// Sheet lede copy (`.afu-lede`) — 0.92rem / 500, no tracking. UI face.
    public static var sheetLede: Font { ui(14.72, .medium) }
    /// Paste pill label (`.afu-paste`) — 0.82rem / 800, no tracking. UI face.
    public static var pasteLabel: Font { ui(13.12, .heavy) }
    /// Inline hint/error note (`.afu-note`) — 0.8rem / 500. UI face.
    public static var noteText: Font { ui(12.8, .medium) }
    /// Full-width Add button label (`.afu-add`) — 1rem / 800 / 0.01em. UI face.
    public static var addButtonLabel: Font { ui(16, .heavy) }
    /// Success title (`.afu-success .s-title`) — 1.14rem / 700 / -0.015em. Display face.
    public static var successTitle: Font { display(18.24, .bold) }
    /// Success subtitle (`.afu-success .s-sub`) — 0.9rem / 500. UI face.
    public static var successSubtitle: Font { ui(14.4, .medium) }

    // MARK: Roles — Search "Add a podcast by URL" CTA reconciliation
    // Exact kit value verified against design/kit/screens/search-start.html's
    // `.urlcta` (line 649) — 0.92rem / 700, no tracking. Distinct from
    // `showCardTitle` (14.72/700 but carries -0.01em tracking) and
    // `arcCardTitle` (14.72/800), so it's its own token rather than a
    // near-miss reuse of either.

    /// Search's "Have a podcast URL?" CTA row label (`.urlcta`) — 0.92rem / 700, no tracking. UI face.
    public static var urlCTALabel: Font { ui(14.72, .bold) }

    // MARK: Roles (full TypeStyle tokens — carry tracking + case)

    public static var displayLargeTitleStyle: TypeStyle { .init(font: displayLargeTitle, tracking: -0.742) }
    public static var sectionStyle: TypeStyle { .init(font: section, tracking: -0.322) }
    public static var navTitleStyle: TypeStyle { .init(font: navTitle, tracking: -0.170) }
    public static var shelfTitleStyle: TypeStyle { .init(font: shelfTitle, tracking: -0.283) }
    public static var rowTitleStyle: TypeStyle { .init(font: rowTitle, tracking: -0.160) }
    public static var bodyStyle: TypeStyle { .init(font: body) }
    public static var subheadStyle: TypeStyle { .init(font: subhead) }
    public static var groupLabelStyle: TypeStyle { .init(font: groupLabel, tracking: 0.691, uppercase: true) }
    public static var badgeStyle: TypeStyle { .init(font: badge, tracking: 0.397, uppercase: true) }
    public static var eyebrowStyle: TypeStyle { .init(font: eyebrow, tracking: 1.382, uppercase: true) }
    public static var tagStyle: TypeStyle { .init(font: tag, tracking: 0.205, uppercase: true) }
    public static var tabLabelStyle: TypeStyle { .init(font: tabLabel, tracking: 0.099) }

    // Search + Podcast Detail reconciliation styles (tracking = em × px).
    public static var arcCardTitleStyle: TypeStyle { .init(font: arcCardTitle, tracking: -0.147) }   // -0.01em
    public static var arcCardMetaStyle: TypeStyle { .init(font: arcCardMeta) }
    public static var seasonBadgeStyle: TypeStyle { .init(font: seasonBadge) }
    /// `.sub` subscribe pill — 0.01em tracking.
    public static var pillButtonLabelStyle: TypeStyle { .init(font: pillButtonLabel, tracking: 0.128) }
    /// `.arc-add` — no tracking (differs from `.sub` on this axis only).
    public static var arcAddLabelStyle: TypeStyle { .init(font: pillButtonLabel) }
    public static var heroTitleStyle: TypeStyle { .init(font: heroTitle, tracking: -0.173) }          // -0.01em
    public static var heroAuthorStyle: TypeStyle { .init(font: heroAuthor) }
    public static var countBadgeStyle: TypeStyle { .init(font: countBadge) }
    public static var episodeTitleStyle: TypeStyle { .init(font: episodeTitle, tracking: -0.157) }    // -0.01em
    public static var episodeMetaStyle: TypeStyle { .init(font: episodeMeta) }
    public static var metaEmphasisStyle: TypeStyle { .init(font: metaEmphasis) }
    public static var shelfBadgeStyle: TypeStyle { .init(font: shelfBadge) }
    public static var podcastDetailTitleStyle: TypeStyle { .init(font: podcastDetailTitle, tracking: -0.410) } // -0.02em
    public static var detailAuthorStyle: TypeStyle { .init(font: detailAuthor) }
    public static var categoryLabelStyle: TypeStyle { .init(font: categoryLabel, tracking: 0.806, uppercase: true) } // 0.07em
    public static var detailBodyStyle: TypeStyle { .init(font: detailBody) }
    public static var expandLabelStyle: TypeStyle { .init(font: expandLabel) }
    public static var footnoteStyle: TypeStyle { .init(font: footnote) }

    /// `.pod-title` — same -0.01em-at-0.92rem math as `arcCardTitleStyle`.
    public static var showCardTitleStyle: TypeStyle { .init(font: showCardTitle, tracking: -0.147) }
    public static var showCardStudioStyle: TypeStyle { .init(font: showCardStudio) }

    // Home rails reconciliation styles (tracking = em × px).
    public static var upNextTileTitleStyle: TypeStyle { .init(font: upNextTileTitle, tracking: -0.1376) }  // -0.01em
    public static var upNextTileTimeStyle: TypeStyle { .init(font: upNextTileTime) }
    public static var newEpisodeTitleStyle: TypeStyle { .init(font: newEpisodeTitle, tracking: -0.1568) }  // -0.01em
    public static var newEpisodePodcastStyle: TypeStyle { .init(font: newEpisodePodcast) }
    public static var newEpisodeDateStyle: TypeStyle { .init(font: newEpisodeDate) }
    /// `.tag` / `.tag.hot` — tracking only; uppercasing is applied by `TagChip`
    /// itself (not baked into the token) so non-chip callers can opt out.
    public static var tagChipStyle: TypeStyle { .init(font: tagChip, tracking: 0.2048) }  // +0.02em

    // Add Feed by URL sheet reconciliation styles (tracking = em × px).
    public static var sheetTitleStyle: TypeStyle { .init(font: sheetTitle, tracking: -0.1792) }        // -0.01em
    public static var sheetLedeStyle: TypeStyle { .init(font: sheetLede) }
    public static var pasteLabelStyle: TypeStyle { .init(font: pasteLabel) }
    public static var noteTextStyle: TypeStyle { .init(font: noteText) }
    public static var addButtonLabelStyle: TypeStyle { .init(font: addButtonLabel, tracking: 0.16) }   // 0.01em
    public static var successTitleStyle: TypeStyle { .init(font: successTitle, tracking: -0.2736) }    // -0.015em
    public static var successSubtitleStyle: TypeStyle { .init(font: successSubtitle) }

    /// `.urlcta` — no tracking.
    public static var urlCTALabelStyle: TypeStyle { .init(font: urlCTALabel) }
}

public extension View {
    /// Apply a `TypeStyle` (font + tracking + optional uppercasing).
    func typeStyle(_ style: TypeStyle) -> some View {
        let base = self.font(style.font).tracking(style.tracking)
        return Group {
            if style.uppercase {
                base.textCase(.uppercase)
            } else {
                base
            }
        }
    }
}
