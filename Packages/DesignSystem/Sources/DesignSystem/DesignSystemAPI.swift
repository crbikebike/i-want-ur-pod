// Frozen public component signatures — comments only.
// Design source: docs/design/direction.md §10 (component inventory), §12 (sources).
//
// This file intentionally contains NO code. Component *bodies* are built by
// later agents; their public signatures are FIXED here so screen/component
// builders link against the same API. Do not change these signatures without
// coordinating every caller. The supporting enums (ArtworkStyle, SubscribeState,
// AppTab, EmptyKind) are owned/defined by the component layer, not the token
// layer, and must match the shapes below. (SeekDirection is likewise owned by
// the component layer.)
//
// ── Buttons (design/kit/components/buttons.html) ──────────────────────────
//   PrimaryButton(title: String, action: () -> Void)
//   SecondaryButton(title: String, action: () -> Void)
//   GhostButton(title: String, action: () -> Void)
//
// ── Search (design/kit/components/search-field.html) ──────────────────────
//   SearchField(text: Binding<String>, placeholder: String, onSubmit: () -> Void)
//
// ── Category shelves & artwork (design/kit/components/result-row.html) ─────
//   ResultShelf<Item, Trailing>(title: String, items: [Item], totalCount: Int?,
//               onViewAll: (() -> Void)?, onSelect: (Item) -> Void,
//               itemTitle:, itemAuthor:, itemArtwork:, trailing: (Item) -> some View)
//   PodCard<Trailing>(title: String, author: String, artwork: ArtworkStyle,
//           trailing: () -> some View)
//   PodGrid<Item, Trailing>(items: [Item], onSelect:, itemTitle:, itemAuthor:,
//           itemArtwork:, trailing: (Item) -> some View)   // "View all" destination
//   ArtworkTile(seed: Int, initial: String)
//   // ArtworkStyle: gradient-tile style for placeholders (.a1….a6, §9).
//
// ── Result card (design/kit/components/result-card.html) ───────────────────
//   ResultCard(title: String, author: String, artwork: ArtworkStyle)
//
// ── Subscribe (design/kit/components/subscribe-button.html) ────────────────
//   SubscribeButton(state: SubscribeState, action: () -> Void)
//   // enum SubscribeState { case idle, subscribing, subscribed }
//
// ── Seek (design/kit/components/seek-button.html) ─────────────────────────
//   SeekButton(direction: SeekDirection, seconds: Int, diameter: CGFloat,
//              accessibilityLabel: String, action: () -> Void)
//   // enum SeekDirection { case backward, forward }
//
// ── Section header (design/kit/components/section-header.html) ─────────────
//   SectionHeader(title: String, count: Int?)
//
// ── Floating Liquid Glass tab bar (design/kit/components/tab-bar.html, §12) ─
//   LiquidGlassTabBar(selection: Binding<AppTab>, searchQuery: Binding<String>,
//                     onCancelSearch: () -> Void)
//   // enum AppTab { case home, shows, upNext, search } — four-item dock
//   // (2026-07-05 IA revision). Tapping .search is a takeover: the bar's
//   // icons collapse into a Home glyph + search field + cancel (✕); the app
//   // drives `selection`/`searchQuery` and supplies `onCancelSearch` to
//   // restore the previously active tab.
//
// ── Sources checklist (design/kit/components/sources-checklist.html, §12) ──
//   SourcesChecklistRow(...)  // RETIRED from the app (v1 is Apple-only, no
//                             // source picker, §12) but kept in DesignSystem
//                             // as dormant groundwork; no in-app consumer.
//
// ── Loading / empty states (design/kit/screens/*, §9) ─────────────────────
//   LoadingSkeleton(shelves: Int)   // design/kit/screens/search-loading.html shelf/rail skeleton
//   EmptyStateView(kind: EmptyKind, title: String, message: String,
//                  actions: () -> some View)
//   // enum EmptyKind { case firstRun, noResults, error }
//
// ── Swipe deck (design/kit/screens/explore-theme-shows.html, Phase C) ──────
//   SwipeDeck<Item, CardContent>(items: [Item], visibleDepth: Int,
//             rightStampTitle: String, leftStampTitle: String,
//             programmaticAction: Binding<SwipeDeckAction?>,
//             onSwipeRight: (Item) -> Void, onSwipeLeft: (Item) -> Void,
//             onTap: (Item) -> Void, card: (Item) -> some View)
//   // enum SwipeDeckAction { case right, left } — set `programmaticAction`
//   // to fly the top card off without a real drag (e.g. a detail sheet's
//   // Subscribe action advancing the deck behind it).
