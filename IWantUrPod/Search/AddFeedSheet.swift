// Translated from design/kit/screens/add-feed-url.html (`.afu-*` classes,
// "built only on locked tokens") — the shared "Add a feed by URL" sheet
// behind Search's "Have a podcast URL?" entry points and Settings' "Add
// premium or custom podcast URL" row (docs/spec/add-feed-by-url.md). Four
// states driven by `AddFeedByURLViewModel.state` (mirrors the kit's
// `data-state` on `.afu-sheet`): ready (line 398), loading (spinner +
// "Checking…", line 432-435), error (the expiring-private-link message,
// line 427-430), success (check badge, line 445-451). The kit's top-left
// state switcher (line 367) is an authoring aid, not part of the UI.
//
// The kit draws its own grabber (`.afu-grabber`, line 248) and header
// (`.afu-head`, line 251) rather than relying on system sheet chrome, so
// this view hides the system drag indicator and reproduces both, plus the
// kit's literal 26px sheet-top corner radius (now `Radius.rSheet26`) via
// `.presentationCornerRadius`.
import SwiftUI
import SwiftData
import UIKit
import DesignSystem
import PodcastModels
import FeedParsingKit

/// The shared "Add a feed by URL" sheet. Resolves the environment
/// `modelContext` and builds its own `AddFeedByURLViewModel` (mirrors
/// `PodcastDetailScreen`'s lazy-`.task` composition, since `@Environment`
/// values aren't available at `init()` time), then hosts `AddFeedSheetBody`.
public struct AddFeedSheet: View {
    private let onSubscribed: (URL) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @State private var viewModel: AddFeedByURLViewModel?

    /// - Parameter onSubscribed: Called with the subscribed feed's URL on
    ///   success, so the caller can navigate to Podcast Detail. The sheet
    ///   dismisses itself after calling it.
    public init(onSubscribed: @escaping (URL) -> Void) {
        self.onSubscribed = onSubscribed
    }

    public var body: some View {
        Group {
            if let viewModel {
                AddFeedSheetBody(viewModel: viewModel, onSubscribed: onSubscribed)
            } else {
                Color.clear
            }
        }
        .task {
            guard viewModel == nil else { return }
            viewModel = AddFeedByURLViewModel(modelContext: modelContext, fetcher: FeedFetcher())
        }
        // `.afu-sheet`: 26px top corners (line 241-242), own grabber drawn
        // below instead of the system drag indicator, `--surface` fill.
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(Radius.rSheet26)
        .presentationBackground(palette.surface)
    }
}

/// Renders one fully-resolved `AddFeedByURLViewModel`. Split out from
/// `AddFeedSheet` (mirrors `PodcastDetailScreen`/`PodcastDetailView`) so
/// previews can seed a `viewModel` directly via
/// `AddFeedByURLViewModel(previewState:modelContext:)` without waiting on
/// the environment-resolving wrapper.
struct AddFeedSheetBody: View {
    @State private var viewModel: AddFeedByURLViewModel
    private let onSubscribed: (URL) -> Void

    @State private var urlString = ""
    @State private var successBadgeAppeared = false
    @FocusState private var isFieldFocused: Bool

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: AddFeedByURLViewModel, onSubscribed: @escaping (URL) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onSubscribed = onSubscribed
    }

    var body: some View {
        VStack(spacing: 0) {
            grabber
            header

            if case .success = viewModel.state {
                successView
            } else {
                formPart
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.bottom, Spacing.sp4)
        .background(palette.surface)
        .onChange(of: viewModel.state) { _, newState in
            // Success moment (line 320 "shown briefly, then the sheet
            // dismisses to the show"): hold the check badge on screen for a
            // beat before handing off and dismissing.
            guard case .success(let feedURL) = newState else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(650))
                onSubscribed(feedURL)
                dismiss()
            }
        }
        // Once a fetch is in flight (`.loading`) or has succeeded (`.success`,
        // during the 650 ms hand-off hold above), block Cancel and the
        // swipe-to-dismiss gesture. Otherwise a user who backs out mid-add is
        // still silently subscribed (the detached add Task runs to completion),
        // and a user who backs out during the success hold is still navigated
        // to the show by the detached success Task. Guarding these two
        // transient states keeps dismissal and the subscribe/navigate hand-off
        // in lockstep. A stuck fetch still resolves on URLSession's request
        // timeout, returning the sheet to a dismissable error state.
        .interactiveDismissDisabled(isLoading || isSuccess)
    }

    // MARK: - Grabber + header (`.afu-grabber` / `.afu-head`, lines 248-259)

    private var grabber: some View {
        Capsule()
            .fill(palette.separator)
            .frame(width: 38, height: 5)
            .padding(.top, 6)
            .padding(.bottom, Spacing.sp2)
            .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button("Cancel") { dismiss() }
                .buttonStyle(SheetOpacityButtonStyle())
                .font(Typography.rowTitle)   // 1rem / 700 (`.afu-cancel`, no tracking)
                .foregroundStyle(palette.accent)
                // Disabled while a fetch is in flight or during the success
                // hold — see `.interactiveDismissDisabled` on the body.
                .disabled(isLoading || isSuccess)

            Spacer(minLength: 0)

            Text("Add a feed")
                .typeStyle(Typography.sheetTitleStyle)
                .foregroundStyle(palette.text)

            Spacer(minLength: 0)

            // `.afu-spacer` — balances Cancel so the title stays centered.
            Color.clear.frame(width: 52, height: 1)
        }
        .frame(minHeight: 34)
    }

    // MARK: - Form (ready / loading / error share this, lines 407-442)

    private var formPart: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Paste a podcast\u{2019}s RSS link \u{2014} including private or premium feeds, like an ad\u{2011}free member link.")
                .typeStyle(Typography.sheetLedeStyle)
                .foregroundStyle(palette.textDim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
                .padding(.top, Spacing.sp2)
                .padding(.bottom, Spacing.sp3)

            HStack(spacing: Spacing.sp2) {
                urlField
                pasteButton
            }

            if !isLoading {
                note
                    .padding(.horizontal, 2)
                    .padding(.top, Spacing.sp3)
            }

            addButton
                .padding(.top, Spacing.sp3)

            footnoteRow
                .padding(.horizontal, 2)
                .padding(.top, Spacing.sp3)
        }
    }

    // MARK: - URL field (`.afu-field`, lines 264-279)

    private var urlField: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.textFaint)

            ZStack(alignment: .leading) {
                if urlString.isEmpty {
                    Text("https://\u{2026}")
                        .typeStyle(Typography.bodyStyle)
                        .foregroundStyle(palette.textDim)
                        .allowsHitTesting(false)
                }
                TextField("", text: $urlString)
                    .typeStyle(Typography.bodyStyle)
                    .foregroundStyle(palette.text)
                    .tint(palette.accent)
                    .textFieldStyle(.plain)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($isFieldFocused)
                    .disabled(isLoading)
                    .onSubmit(submit)
                    .accessibilityLabel("Feed URL")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 48)
        .background(palette.field, in: RoundedRectangle(cornerRadius: Radius.rField11, style: .continuous))
        .overlay {
            // `.afu-field.focused` (2px accent) / `.afu-field.bad` (2px
            // error ring, lines 272-273) — driven by real focus + VM state
            // rather than the kit's authoring-only class toggle.
            RoundedRectangle(cornerRadius: Radius.rField11, style: .continuous)
                .strokeBorder(isError ? KitLiteralColors.errorRing : palette.accent, lineWidth: 2)
                .opacity(isError || isFieldFocused ? 1 : 0)
        }
        .motion(Motion.easeSoft(duration: 0.25), value: isFieldFocused)
        .motion(Motion.easeSoft(duration: 0.25), value: isError)
        .contentShape(RoundedRectangle(cornerRadius: Radius.rField11, style: .continuous))
        .onTapGesture { isFieldFocused = true }
    }

    // MARK: - Paste (`.afu-paste`, lines 280-287)

    private var pasteButton: some View {
        Button {
            if let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !pasted.isEmpty {
                urlString = pasted
            }
        } label: {
            Text("Paste")
                .typeStyle(Typography.pasteLabelStyle)
                .foregroundStyle(palette.accent)
                .padding(.horizontal, Spacing.sp3)
                .frame(minHeight: 34)
                .background(palette.accent.opacity(0.12), in: Capsule())
        }
        .buttonStyle(SheetScaleButtonStyle(scale: 0.92))
        .disabled(isLoading)
        .accessibilityLabel("Paste from clipboard")
    }

    // MARK: - Inline note (`.afu-note`, lines 290-297, 420-430)

    @ViewBuilder
    private var note: some View {
        switch viewModel.state {
        case .ready:
            noteRow(
                icon: "info.circle",
                text: "Works with Patreon, Supercast, Supporting Cast, or any RSS feed link.",
                color: palette.textFaint
            )
        case .error(let message):
            noteRow(icon: "exclamationmark.triangle.fill", text: message, color: palette.errorText)
        case .loading, .success:
            EmptyView()
        }
    }

    private func noteRow(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .padding(.top, 1)
            Text(text)
                .typeStyle(Typography.noteTextStyle)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Add button (`.afu-add`, lines 300-318, 432-436)

    private var addButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(palette.onAccent)
                        .scaleEffect(0.7)
                    Text("Checking\u{2026}")
                } else {
                    Text("Add feed")
                }
            }
            .typeStyle(Typography.addButtonLabelStyle)
            .foregroundStyle(isAddDisabled ? palette.textFaint : palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(addBackground)
            .clipShape(Capsule())
        }
        .buttonStyle(SheetScaleButtonStyle(scale: 0.97))
        .disabled(isAddDisabled)
        .modifier(AddButtonShadow(enabled: !isAddDisabled, accent: palette.accent))
    }

    @ViewBuilder
    private var addBackground: some View {
        if isAddDisabled {
            Capsule().fill(palette.chip)
        } else if colorScheme == .dark {
            Capsule().fill(
                LinearGradient(colors: [palette.accent, palette.accent2],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        } else {
            Capsule().fill(palette.accent)
        }
    }

    // MARK: - Privacy footnote (`.afu-foot`, lines 338-343, 438-441)

    private var footnoteRow: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textFaint)
                .padding(.top, 1)
            Text("Private links are stored only on this device and never shared.")
                .typeStyle(Typography.footnoteStyle)
                .foregroundStyle(palette.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Success (`.afu-success`, lines 320-335, 444-451)

    private var successView: some View {
        VStack(spacing: Spacing.sp3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.rCheck22, style: .continuous)
                    .fill(
                        LinearGradient(colors: [palette.mint, palette.coral],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 72, height: 72)
            .elevCard(hairline: palette.hairline)
            .scaleEffect(successBadgeAppeared ? 1 : 0.7)
            .opacity(successBadgeAppeared ? 1 : 0)
            .accessibilityHidden(true)

            Text("Added to your shows")
                .typeStyle(Typography.successTitleStyle)
                .foregroundStyle(palette.text)

            // The kit's copy names the show ("Opening This American Life
            // Partners…"); the VM's `.success(URL)` carries only the feed
            // URL, not a title, so this uses generic copy instead — see the
            // report's ambiguity note.
            Text("Opening your show\u{2026}")
                .typeStyle(Typography.successSubtitleStyle)
                .foregroundStyle(palette.textDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
        }
        .padding(.top, Spacing.sp3)
        .padding(.horizontal, Spacing.sp2)
        .padding(.bottom, Spacing.sp4)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(Motion.resolve(Motion.easeSpring(duration: 0.5), reduceMotion: reduceMotion)) {
                successBadgeAppeared = true
            }
        }
    }

    // MARK: - Derived state

    private var isLoading: Bool { viewModel.state == .loading }

    private var isError: Bool {
        if case .error = viewModel.state { return true }
        return false
    }

    private var isSuccess: Bool {
        if case .success = viewModel.state { return true }
        return false
    }

    private var isAddDisabled: Bool {
        isLoading || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        Task { await viewModel.add(urlString: urlString) }
    }
}

// MARK: - Local button styles (kit-specific press feedback, not shared components)

/// `.afu-paste:active { transform: scale(.92) }` / `.afu-add:active { transform: scale(.97) }`
/// — distinct press-scale values from the shared `PillButtonStyle` (0.95),
/// so kept local rather than reusing that DesignSystem-internal style.
private struct SheetScaleButtonStyle: ButtonStyle {
    let scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.resolve(Motion.easeSpring(), reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// `.afu-cancel:active { opacity: .6 }`
private struct SheetOpacityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Applies `--elev-sub` only while the Add button is enabled (`.afu-add:disabled { box-shadow: none }`).
private struct AddButtonShadow: ViewModifier {
    let enabled: Bool
    let accent: Color

    func body(content: Content) -> some View {
        if enabled {
            content.elevSub(color: accent)
        } else {
            content
        }
    }
}

// MARK: - Preview

#if DEBUG
private struct AddFeedSheetPreviewHost: View {
    let state: AddFeedByURLViewModel.State
    var body: some View {
        Color.black.opacity(0.001) // lets the sheet's own presentation show through in canvas
            .sheet(isPresented: .constant(true)) {
                AddFeedSheetBody(
                    viewModel: AddFeedByURLViewModel(previewState: state, modelContext: ModelContext(ModelSchema.previewContainer())),
                    onSubscribed: { _ in }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(Radius.rSheet26)
            }
    }
}

#Preview("Add feed — ready (dark)") {
    AddFeedSheetPreviewHost(state: .ready)
        .themedPalette()
        .environment(\.colorScheme, .dark)
}

#Preview("Add feed — ready (light)") {
    AddFeedSheetPreviewHost(state: .ready)
        .themedPalette()
        .environment(\.colorScheme, .light)
}

#Preview("Add feed — loading (dark)") {
    AddFeedSheetPreviewHost(state: .loading)
        .themedPalette()
        .environment(\.colorScheme, .dark)
}

#Preview("Add feed — loading (light)") {
    AddFeedSheetPreviewHost(state: .loading)
        .themedPalette()
        .environment(\.colorScheme, .light)
}

#Preview("Add feed — error (dark)") {
    AddFeedSheetPreviewHost(state: .error("This link didn\u{2019}t work. Private feed links can expire \u{2014} grab a fresh one from the show and try again."))
        .themedPalette()
        .environment(\.colorScheme, .dark)
}

#Preview("Add feed — error (light)") {
    AddFeedSheetPreviewHost(state: .error("This link didn\u{2019}t work. Private feed links can expire \u{2014} grab a fresh one from the show and try again."))
        .themedPalette()
        .environment(\.colorScheme, .light)
}

#Preview("Add feed — success (dark)") {
    AddFeedSheetPreviewHost(state: .success(URL(string: "https://feeds.example.com/preview")!))
        .themedPalette()
        .environment(\.colorScheme, .dark)
}

#Preview("Add feed — success (light)") {
    AddFeedSheetPreviewHost(state: .success(URL(string: "https://feeds.example.com/preview")!))
        .themedPalette()
        .environment(\.colorScheme, .light)
}
#endif
