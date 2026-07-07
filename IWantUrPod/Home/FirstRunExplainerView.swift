// Composed from docs/design/direction.md tokens — no design/kit source.
// design/kit/screens/first-run.html's real content is a multi-step guided
// onboarding wizard (existing-app import, favorite-show picker, topic
// picker, personalized recommendations) that is explicitly out of scope (see
// design/kit/MANIFEST.md — "not yet fixed … building the real wizard is
// tracked separately"). E1-S1 asks only for a lightweight, once-only intro to
// the story-driven pitch, not that wizard, so this is a new, small composed
// screen rather than a translation of that file. Registered in
// design/kit/MANIFEST.md as composed-no-source.
import SwiftUI
import DesignSystem

/// The once-only explainer shown before Home on a fresh install (E1-S1).
/// Presented as a `fullScreenCover` by `HomeScreen`, gated by
/// ``FirstRunGate``. Re-openable from Settings via a control that resets the
/// gate.
struct FirstRunExplainerView: View {
    var onDismiss: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Spacing.sp7)

            badge

            Text("Less talk show.\nMore story arcs.")
                .typeStyle(Typography.displayLargeTitleStyle)
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.center)
                .padding(.top, Spacing.sp5)

            Text("i want ur pod is built for story-driven and investigative podcasts — limited series, true crime, narrative documentary. We'll show you a hand-picked place to start, and you can search for anything else.")
                .typeStyle(Typography.bodyStyle)
                .foregroundStyle(palette.textDim)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 320)
                .padding(.top, Spacing.sp4)

            Spacer()

            PrimaryButton(title: "Get started", action: onDismiss)
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, Spacing.sp6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.groupedBg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
    }

    private var badge: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [palette.coral, palette.mint],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 84, height: 84)
            .overlay {
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("First-run explainer — dark") {
    FirstRunExplainerView(onDismiss: {})
        .themedPalette()
        .environment(\.colorScheme, .dark)
}

#Preview("First-run explainer — light") {
    FirstRunExplainerView(onDismiss: {})
        .themedPalette()
        .environment(\.colorScheme, .light)
}
#endif
