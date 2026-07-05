// Translated from design/kit/components/search-field.html (.search + SHARED KIT EXTRAS).
// iOS-native search field: field fill, leading magnifier, focus accent ring,
// mic affordance that becomes a clear button once text is entered.
import SwiftUI

/// An iOS-style search field.
///
/// Layout & states mirror `design/kit/components/search-field.html`:
/// - 40pt tall pill on the `--field` fill, radius `--r-field` (11).
/// - Leading magnifier tinted `--text-faint`; placeholder in `--text-dim`.
/// - 2pt `--accent` ring while focused (`:focus-within` in the kit).
/// - Trailing 30pt circular button: a mic when empty, a chip-backed clear
///   (`✕`) once text is present (the "Filled + clear affordance" variant).
public struct SearchField: View {
    @Binding private var text: String
    private let placeholder: String
    private let onSubmit: () -> Void

    @Environment(\.palette) private var palette
    @FocusState private var isFocused: Bool

    public init(
        text: Binding<String>,
        placeholder: String,
        onSubmit: @escaping () -> Void
    ) {
        self._text = text
        self.placeholder = placeholder
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: Spacing.sp2) {
            // Leading magnifier — .mag, color var(--text-faint).
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.textFaint)

            // Input + placeholder. TextField's own prompt cannot carry a role
            // color, so the placeholder is overlaid to hit --text-dim exactly.
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .typeStyle(Typography.bodyStyle)
                        .foregroundStyle(palette.textDim)
                        .allowsHitTesting(false)
                }
                TextField("", text: $text)
                    .typeStyle(Typography.bodyStyle)
                    .foregroundStyle(palette.text)
                    .tint(palette.accent)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .focused($isFocused)
                    .onSubmit(onSubmit)
            }

            trailingButton
        }
        .padding(.leading, Spacing.sp3)   // 12 — kit padding-left
        .padding(.trailing, Spacing.sp1 + 2)  // 6 — kit padding-right
        .frame(height: 40)
        .background(palette.field, in: RoundedRectangle(cornerRadius: Radius.rField11, style: .continuous))
        .overlay {
            // :focus-within → box-shadow 0 0 0 2px var(--accent).
            RoundedRectangle(cornerRadius: Radius.rField11, style: .continuous)
                .strokeBorder(palette.accent, lineWidth: 2)
                .opacity(isFocused ? 1 : 0)
        }
        .motion(Motion.easeSoft(duration: 0.25), value: isFocused)
        .contentShape(RoundedRectangle(cornerRadius: Radius.rField11, style: .continuous))
        .onTapGesture { isFocused = true }
    }

    @ViewBuilder
    private var trailingButton: some View {
        if text.isEmpty {
            // Mic affordance (visual only — no dictation behavior specified, §11).
            Image(systemName: "mic.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(palette.textFaint)
                .frame(width: 30, height: 30)
                .accessibilityLabel("Voice search")
        } else {
            // Clear affordance — chip-backed ✕, color var(--text).
            Button {
                text = ""
                isFocused = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.text)
                    .frame(width: 30, height: 30)
                    .background(palette.chip, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear search")
        }
    }
}

#if DEBUG
private struct SearchFieldPreviewHost: View {
    @Environment(\.palette) private var palette
    @State private var empty = ""
    @State private var filled = "true crime"
    var body: some View {
        VStack(spacing: Spacing.sp4) {
            SearchField(text: $empty, placeholder: "Shows, people, topics", onSubmit: {})
            SearchField(text: $filled, placeholder: "Shows, people, topics", onSubmit: {})
        }
        .padding(Spacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.groupedBg)
    }
}

#Preview("Search field — light") {
    SearchFieldPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .light)
}

#Preview("Search field — dark") {
    SearchFieldPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}
#endif
