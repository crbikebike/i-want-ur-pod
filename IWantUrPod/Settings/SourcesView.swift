// Translated from the retired settings-sources kit screen (removed 2026-07-06 — v1 is Apple-only, no source picker; see design/kit/MANIFEST.md and docs/design/direction.md §12). Removing this screen is part of the pending dock-IA SwiftUI pass.
// Settings → Sources: the grouped opt-in search-source checklist. Apple
// Podcasts is the keyless primary and ships ON; PodcastIndex is opt-in and
// stays locked until the user adds an API key + secret via the "Add API key"
// sheet, which writes to KeychainStore. Enable/disable flows through the
// DesignSystem SourcesChecklistRow switch; "Set as primary" reorders the
// SearchCoordinator so the primary + fallback ordering (§12.3) changes with it.
import SwiftUI
import DesignSystem
import DirectoryKit

// MARK: - Key store abstraction

/// The subset of ``KeychainStore`` the Sources screen depends on, factored into
/// a protocol so previews can stand in an in-memory store without touching the
/// system Keychain. The production conformance below forwards to the real
/// ``KeychainStore`` (§12.2: keys live in the Keychain; the UI only ever sees
/// connection state and a redacted hint).
protocol PodcastIndexKeyStoring {
    /// Whether a complete key + secret pair is stored.
    var hasKey: Bool { get }
    /// A redacted, display-safe hint for the stored key (e.g. `"key ending ••3F"`).
    var keyHint: String? { get }
    /// Persists a key + secret pair, replacing any existing values.
    func saveKey(_ key: String, secret: String) throws
    /// Removes any stored key + secret.
    func removeKey() throws
}

extension KeychainStore: PodcastIndexKeyStoring {
    var hasKey: Bool { hasCredentials }
    var keyHint: String? { redactedDisplay }
    func saveKey(_ key: String, secret: String) throws { try save(apiKey: key, apiSecret: secret) }
    func removeKey() throws { try deleteCredentials() }
}

// MARK: - Sources screen

/// Settings → Sources. Reflects and edits a ``SearchCoordinator``: the checklist
/// toggles map to `setEnabled`, "Set as primary" maps to `setPrimary`, and the
/// "Search order" list mirrors `orderedSources` so the primary + fallback chain
/// is visible and reorderable (§12.3). PodcastIndex credentials are managed
/// through an injected ``PodcastIndexKeyStoring`` (the real Keychain in the app).
public struct SourcesView: View {

    private let coordinator: SearchCoordinator
    private let keyStore: any PodcastIndexKeyStoring

    @Environment(\.palette) private var palette

    /// Mirror of the key store's connection state, refreshed on appear and after
    /// the key sheet saves or removes credentials (the store itself isn't
    /// observable, so we snapshot the two non-secret facts we render).
    @State private var piConfigured = false
    @State private var piKeyHint: String?
    @State private var showKeySheet = false

    /// - Parameter coordinator: The search orchestrator to reflect and edit. It
    ///   should already hold both sources (Apple + PodcastIndex) so their order
    ///   and enablement are manageable here.
    public init(coordinator: SearchCoordinator) {
        self.coordinator = coordinator
        self.keyStore = KeychainStore()
    }

    /// Test / preview seam: inject a key store.
    init(coordinator: SearchCoordinator, keyStore: any PodcastIndexKeyStoring) {
        self.coordinator = coordinator
        self.keyStore = keyStore
    }

    // MARK: Derived source state

    private var orderedKinds: [SourceKind] { coordinator.orderedSources.map(\.kind) }

    /// The primary source: the first enabled source in priority order (§12.3).
    private var primaryKind: SourceKind? {
        coordinator.orderedSources.first { coordinator.isEnabled($0.kind) }?.kind
    }

    private var enabledCount: Int {
        coordinator.orderedSources.filter { coordinator.isEnabled($0.kind) }.count
    }

    private func enabledBinding(for kind: SourceKind) -> Binding<Bool> {
        Binding(
            get: { coordinator.isEnabled(kind) },
            set: { coordinator.setEnabled($0, for: kind) }
        )
    }

    private func displayName(for kind: SourceKind) -> String {
        switch kind {
        case .apple: return "Apple Podcasts"
        case .podcastIndex: return "PodcastIndex"
        }
    }

    private func icon(for kind: SourceKind) -> SourcesChecklistRow.Icon {
        switch kind {
        case .apple: return .apple
        case .podcastIndex: return .podcastIndex
        }
    }

    // MARK: Body

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                groupLabel("Search sources")
                    .padding(.top, Spacing.sp6)
                sourcesCard
                footnote("Add your PodcastIndex key + secret to enable it. Keys are stored in the device Keychain, never in the app bundle.")
                    .padding(.top, Spacing.sp3)

                if piConfigured {
                    removeKeyButton
                        .padding(.top, Spacing.sp4)
                        .padding(.horizontal, Spacing.sp4)
                }

                groupLabel("Search order")
                    .padding(.top, Spacing.sp6)
                orderCard
                footnote("Primary is searched first. If it's unavailable or finds nothing, we fall back to the next enabled source — results are never merged. Enable a second source to pick which one leads.")
                    .padding(.top, Spacing.sp3)

                groupLabel("About")
                    .padding(.top, Spacing.sp6)
                showFirstRunButton
                footnote("Re-show the one-time intro to i want ur pod's story-driven focus, next time you open Discover.")
                    .padding(.top, Spacing.sp3)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.top, Spacing.sp4)
            .padding(.bottom, AppShell.tabBarReservedPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(palette.groupedBg.ignoresSafeArea())
        .onAppear(perform: refreshKeyState)
        .sheet(isPresented: $showKeySheet) {
            AddAPIKeySheet(
                keyStore: keyStore,
                isConfigured: piConfigured,
                currentHint: piKeyHint,
                onSaved: {
                    coordinator.setEnabled(true, for: .podcastIndex)
                    refreshKeyState()
                },
                onRemoved: {
                    coordinator.setEnabled(false, for: .podcastIndex)
                    refreshKeyState()
                }
            )
            .themedPalette()
        }
    }

    // MARK: Header (.titlewrap + .lede)

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sp3) {
            Text("Sources")
                .typeStyle(Typography.displayLargeTitleStyle)
                .foregroundStyle(palette.text)

            Text("Choose which directories i want ur pod searches. Your primary source runs first — the rest are fallback, never merged.")
                .font(Typography.body)
                .foregroundStyle(palette.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }

    // MARK: Search-sources checklist (.srclist)

    private var sourcesCard: some View {
        card {
            appleRow
            separator
            podcastIndexRow
        }
    }

    private var appleRow: some View {
        let isPrimary = primaryKind == .apple
        let enabled = coordinator.isEnabled(.apple)
        return SourcesChecklistRow(
            icon: .apple,
            name: "Apple Podcasts",
            subtitle: "iTunes directory · Works out of the box, no key needed",
            isEnabled: enabledBinding(for: .apple),
            isPrimary: isPrimary,
            isReorderable: enabledCount >= 2,
            onSetPrimary: (enabled && !isPrimary) ? { coordinator.setPrimary(.apple) } : nil
        )
    }

    @ViewBuilder private var podcastIndexRow: some View {
        if piConfigured {
            let isPrimary = primaryKind == .podcastIndex
            let enabled = coordinator.isEnabled(.podcastIndex)
            SourcesChecklistRow(
                icon: .podcastIndex,
                name: "PodcastIndex",
                subtitle: connectedSubtitle,
                isEnabled: enabledBinding(for: .podcastIndex),
                isOpenIndex: true,
                isReorderable: enabledCount >= 2,
                onSetPrimary: (enabled && !isPrimary) ? { coordinator.setPrimary(.podcastIndex) } : nil
            )
        } else {
            SourcesChecklistRow(
                icon: .podcastIndex,
                name: "PodcastIndex",
                subtitle: "The independent, community-run podcast directory.",
                isEnabled: nil,
                isOpenIndex: true,
                isLocked: true,
                isFeatured: true,
                pitch: "Indie-first and free. Bring your own API key (key + secret) to switch it on and set it as a search source.",
                keyHint: "Inactive until a key is added",
                onAddKey: { showKeySheet = true }
            )
        }
    }

    private var connectedSubtitle: String {
        if let hint = piKeyHint { return "Connected · \(hint)" }
        return "Connected"
    }

    private var removeKeyButton: some View {
        GhostButton(title: "Remove PodcastIndex key") { showKeySheet = true }
    }

    // MARK: About (E1-S1 — re-show the first-run explainer)

    /// Resets the ``FirstRunGate`` flag so `DiscoverView` presents the
    /// once-only explainer again the next time Discover appears (no relaunch
    /// needed — the gate is checked on every `onAppear`).
    private var showFirstRunButton: some View {
        card {
            Button {
                FirstRunGate().reset()
            } label: {
                HStack(spacing: Spacing.sp3) {
                    Text("Show first-run intro again")
                        .typeStyle(Typography.rowTitleStyle)
                        .foregroundStyle(palette.text)
                    Spacer(minLength: 0)
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textFaint)
                }
                .padding(.vertical, Spacing.sp3)
                .padding(.horizontal, Spacing.sp4)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Search-order list (.srclist of .orow)

    private var orderCard: some View {
        card {
            let kinds = orderedKinds
            ForEach(Array(kinds.enumerated()), id: \.element) { index, kind in
                orderRow(index: index, kind: kind)
                if index < kinds.count - 1 { orderSeparator }
            }
        }
    }

    private func orderRow(index: Int, kind: SourceKind) -> some View {
        let enabled = coordinator.isEnabled(kind)
        let isPrimary = primaryKind == kind
        return HStack(spacing: Spacing.sp3) {
            Text("\(index + 1)")
                .font(Typography.subhead.weight(.heavy))
                .foregroundStyle(palette.accent)
                .frame(width: 26, height: 26)
                .background(palette.accent.opacity(0.08), in: Circle())

            HStack(spacing: Spacing.sp2) {
                Text(displayName(for: kind))
                    .typeStyle(Typography.rowTitleStyle)
                    .foregroundStyle(palette.text)
                orderTag(kind: kind, enabled: enabled, isPrimary: isPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.textFaint)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Spacing.sp3)
        .padding(.horizontal, Spacing.sp4)
        .opacity(enabled ? 1 : 0.55)
    }

    @ViewBuilder
    private func orderTag(kind: SourceKind, enabled: Bool, isPrimary: Bool) -> some View {
        if isPrimary {
            Text("Primary")
                .typeStyle(Typography.badgeStyle)
                .foregroundStyle(palette.onAccent)
                .padding(.vertical, 3)
                .padding(.horizontal, Spacing.sp2)
                .background(palette.accent, in: Capsule())
        } else {
            mutedTag(orderMutedLabel(kind: kind, enabled: enabled))
        }
    }

    private func orderMutedLabel(kind: SourceKind, enabled: Bool) -> String {
        if enabled { return "Fallback" }
        if kind == .podcastIndex && !piConfigured { return "Add key to enable" }
        return "Off"
    }

    private func mutedTag(_ text: String) -> some View {
        Text(text)
            .typeStyle(Typography.badgeStyle)
            .foregroundStyle(palette.textFaint)
            .padding(.vertical, 3)
            .padding(.horizontal, Spacing.sp2)
            .background(palette.chip, in: Capsule())
    }

    // MARK: Shared pieces

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous))
            .elevList(hairline: palette.hairline)
    }

    /// `.srow::after` — hairline inset past the 46pt icon + row gap.
    private var separator: some View {
        Rectangle()
            .fill(palette.separator)
            .frame(height: 0.5)
            .padding(.leading, Spacing.sp4 + 46 + Spacing.sp3)
    }

    /// `.orow::after` — hairline inset past the 26pt number + row gap.
    private var orderSeparator: some View {
        Rectangle()
            .fill(palette.separator)
            .frame(height: 0.5)
            .padding(.leading, Spacing.sp4 + 26 + Spacing.sp3)
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .typeStyle(Typography.groupLabelStyle)
            .foregroundStyle(palette.textFaint)
            .padding(.horizontal, Spacing.sp4)
            .padding(.bottom, Spacing.sp2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(Typography.subhead)
            .foregroundStyle(palette.textFaint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.sp4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Key-state refresh

    private func refreshKeyState() {
        piConfigured = keyStore.hasKey
        piKeyHint = keyStore.keyHint
        // A source can't be enabled without credentials (§12.2).
        if !piConfigured { coordinator.setEnabled(false, for: .podcastIndex) }
    }
}

// MARK: - Add API key sheet

/// Collects the PodcastIndex API key + secret and writes them to the key store
/// (§12.2). The secret field is masked; neither value is ever echoed back — when
/// a key already exists the sheet shows only the redacted hint and offers to
/// replace or remove it.
private struct AddAPIKeySheet: View {
    let keyStore: any PodcastIndexKeyStoring
    let isConfigured: Bool
    let currentHint: String?
    let onSaved: () -> Void
    let onRemoved: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = ""
    @State private var apiSecret = ""
    @State private var errorMessage: String?

    private var canSave: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sp5) {
                    Text("Bring your own PodcastIndex API credentials to switch it on. Keys are stored in the device Keychain and used only to sign search requests.")
                        .font(Typography.body)
                        .foregroundStyle(palette.textDim)
                        .fixedSize(horizontal: false, vertical: true)

                    if isConfigured, let currentHint {
                        Label {
                            Text("Currently connected · \(currentHint)")
                                .font(Typography.subhead)
                        } icon: {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(palette.accent2)
                    }

                    field("API key", text: $apiKey, secure: false)
                    field("API secret", text: $apiSecret, secure: true)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Typography.subhead)
                            .foregroundStyle(palette.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    PrimaryButton(title: isConfigured ? "Replace key" : "Save key") {
                        save()
                    }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)

                    if isConfigured {
                        GhostButton(title: "Remove key") { remove() }
                    }
                }
                .padding(Spacing.gutter)
            }
            .background(palette.groupedBg.ignoresSafeArea())
            .navigationTitle("PodcastIndex key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(palette.accent)
                }
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sp2) {
            Text(title.uppercased())
                .typeStyle(Typography.groupLabelStyle)
                .foregroundStyle(palette.textFaint)

            Group {
                if secure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(Typography.body)
            .foregroundStyle(palette.text)
            .padding(.horizontal, Spacing.sp4)
            .frame(height: 48)
            .background(palette.field, in: RoundedRectangle(cornerRadius: Radius.rField11, style: .continuous))
        }
    }

    private func save() {
        do {
            try keyStore.saveKey(
                apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                secret: apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = "Couldn't save those credentials. Check the key and secret, then try again."
        }
    }

    private func remove() {
        do {
            try keyStore.removeKey()
            onRemoved()
            dismiss()
        } catch {
            errorMessage = "Couldn't remove the stored key. Try again."
        }
    }
}

// MARK: - Preview

#if DEBUG
import PodcastModels
import SwiftData

/// In-memory key store for previews so no real Keychain access is needed.
private final class PreviewKeyStore: PodcastIndexKeyStoring {
    private var key: String?
    private var secret: String?

    init(key: String? = nil, secret: String? = nil) {
        self.key = key
        self.secret = secret
    }

    var hasKey: Bool { key != nil && secret != nil }
    var keyHint: String? {
        guard let key, !key.isEmpty else { return nil }
        return "key ending ••\(String(key.suffix(2)))"
    }
    func saveKey(_ key: String, secret: String) throws {
        self.key = key
        self.secret = secret
    }
    func removeKey() throws {
        key = nil
        secret = nil
    }
}

@MainActor
private func previewCoordinator(piEnabled: Bool) -> SearchCoordinator {
    let coordinator = SearchCoordinator(sources: [
        FixtureSource(results: DiscoverViewModel.sampleResults),
        PodcastIndexSource(),
    ])
    if piEnabled { coordinator.setEnabled(true, for: .podcastIndex) }
    return coordinator
}

#Preview("Sources — first run (dark)") {
    SourcesView(
        coordinator: previewCoordinator(piEnabled: false),
        keyStore: PreviewKeyStore()
    )
    .themedPalette()
    .environment(\.colorScheme, .dark)
    .modelContainer(ModelSchema.previewContainer())
}

#Preview("Sources — key added (light)") {
    SourcesView(
        coordinator: previewCoordinator(piEnabled: true),
        keyStore: PreviewKeyStore(key: "PXABC123DF", secret: "s3cr3t-value")
    )
    .themedPalette()
    .environment(\.colorScheme, .light)
    .modelContainer(ModelSchema.previewContainer())
}
#endif
