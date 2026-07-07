// Frozen public component signatures — comments only.
// Design source: docs/design/direction.md §10 (component inventory), §12 (sources).
//
// This file intentionally contains NO code. Component *bodies* are built by
// later agents; their public signatures are FIXED here so screen/component
// builders link against the same API. Do not change these signatures without
// coordinating every caller. The supporting enums (ArtworkStyle, SubscribeState,
// AppTab, EmptyKind) are owned/defined by the component layer, not the token
// layer, and must match the shapes below.
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
// ── Section header (design/kit/components/section-header.html) ─────────────
//   SectionHeader(title: String, count: Int?)
//
// ── Floating Liquid Glass tab bar (design/kit/components/tab-bar.html, §12) ─
//   LiquidGlassTabBar(selection: Binding<AppTab>)
//   // enum AppTab { case discover, podcasts, upNext, downloads, settings }
//
// ── Sources checklist (design/kit/components/sources-checklist.html, §12) ──
//   SourcesChecklistRow(...)  // iOS switch toggle, solid coral "Primary"
//                             // badge, mint "Open index" tag, "Add API key"
//                             // ghost button, lock badge when unconfigured.
//
// ── Loading / empty states (design/kit/screens/*, §9) ─────────────────────
//   LoadingSkeleton(shelves: Int)   // design/kit/screens/search-loading.html shelf/rail skeleton
//   EmptyStateView(kind: EmptyKind, title: String, message: String,
//                  actions: () -> some View)
//   // enum EmptyKind { case firstRun, noResults, error }
