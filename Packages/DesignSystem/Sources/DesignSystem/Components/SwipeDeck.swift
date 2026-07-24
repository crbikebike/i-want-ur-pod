// Composed from design/kit/screens/explore-theme-shows.html (swipe deck) — see design/kit/MANIFEST.md.
//
// The reusable card-swipe primitive behind Tier 2 of "Explore by theme"
// (`IWantUrPod/Explore/ThemeShowDeckScreen.swift`): a stack of the top few
// `items`, the frontmost draggable horizontally. A drag past the kit's
// ±110pt release threshold (`up()` in the kit script) fires `onSwipeRight`/
// `onSwipeLeft`; a drag under the kit's 8pt tap/swipe disambiguation
// (`Math.hypot(dx, dy) < 8`) fires `onTap` instead — the toast-sheet peek.
//
// `SwipeDeck` is stateless over its data: it holds no "current index" of its
// own. The caller owns advancing `items` (typically by removing the front
// element inside `onSwipeRight`/`onSwipeLeft`), exactly like the kit's
// `idx++; render()` — this view only ever redraws whatever prefix of `items`
// it's handed. That is also what makes `programmaticAction` work for the
// detail "toast" sheet's "subscribing dismisses the card behind it" behavior
// (`subscribeFromSheet()` in the kit): the caller sets the binding, this view
// plays the same fly-out animation a real swipe would, and then invokes the
// same `onSwipeRight`/`onSwipeLeft` callback — so there is exactly one place
// that mutates the caller's data, regardless of which path triggered it.
import SwiftUI

/// A swipe direction that can be triggered from outside a `SwipeDeck` — e.g.
/// the detail sheet's Subscribe button advancing the card behind it once the
/// person has already subscribed via that sheet, without a real drag.
public enum SwipeDeckAction: Sendable, Equatable {
    case right
    case left
}

/// A reusable, generic card-swipe deck. See the file header for the exact
/// gesture contract (kit `up()`/`down()`/`move()`).
public struct SwipeDeck<Item: Identifiable, CardContent: View>: View {
    private let items: [Item]
    private let visibleDepth: Int
    private let rightStampTitle: String
    private let leftStampTitle: String
    @Binding private var programmaticAction: SwipeDeckAction?
    private let onSwipeRight: (Item) -> Void
    private let onSwipeLeft: (Item) -> Void
    private let onTap: (Item) -> Void
    private let card: (Item) -> CardContent

    /// Kit `up()`: `if (dx > 110) fly('in'); else if (dx < -110) fly('skip');`.
    private static var swipeThreshold: CGFloat { 110 }
    /// Kit `up()`: `if (Math.hypot(dx, dy) < 8)` → treat as a tap, not a swipe.
    private static var tapThreshold: CGFloat { 8 }
    /// Kit `fly()`: `translate(${off*520}px, 60px) rotate(${off*22}deg)`.
    private static var flyDistance: CGFloat { 520 }
    private static var flyVerticalDrift: CGFloat { 60 }
    private static var flyRotationDegrees: Double { 22 }
    /// Kit `restTransform()`: `translateY(depth*14) scale(1 - depth*0.05)`.
    private static func restYOffset(depth: Int) -> CGFloat { CGFloat(depth) * 14 }
    private static func restScale(depth: Int) -> CGFloat { 1 - CGFloat(depth) * 0.05 }

    @State private var dragTranslation: CGSize = .zero
    @State private var isDragging = false
    @State private var flyOffset: CGSize?
    @State private var flyRotation: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - items: The deck's remaining items, front-to-back. The caller
    ///     removes the front item (inside `onSwipeRight`/`onSwipeLeft`) to
    ///     advance the deck.
    ///   - visibleDepth: How many cards to render behind the top one (kit:
    ///     3 — the third stays fully transparent, matching
    ///     `depth > 1 ? opacity 0 : 1`).
    ///   - rightStampTitle: Overlay stamp shown (fading in with drag
    ///     progress) on a rightward drag — kit's "Subscribed ✓".
    ///   - leftStampTitle: Overlay stamp for a leftward drag — kit's "Skip".
    ///   - programmaticAction: Set from outside to fly the top card off
    ///     without a real drag (see file header). Resets to `nil` once
    ///     consumed.
    ///   - onTap: Fired instead of a swipe when the release movement is
    ///     under `tapThreshold` — the detail "toast" sheet's trigger.
    public init(
        items: [Item],
        visibleDepth: Int = 3,
        rightStampTitle: String = "Subscribed ✓",
        leftStampTitle: String = "Skip",
        programmaticAction: Binding<SwipeDeckAction?> = .constant(nil),
        onSwipeRight: @escaping (Item) -> Void,
        onSwipeLeft: @escaping (Item) -> Void,
        onTap: @escaping (Item) -> Void = { _ in },
        @ViewBuilder card: @escaping (Item) -> CardContent
    ) {
        self.items = items
        self.visibleDepth = visibleDepth
        self.rightStampTitle = rightStampTitle
        self.leftStampTitle = leftStampTitle
        self._programmaticAction = programmaticAction
        self.onSwipeRight = onSwipeRight
        self.onSwipeLeft = onSwipeLeft
        self.onTap = onTap
        self.card = card
    }

    public var body: some View {
        ZStack {
            ForEach(Array(visibleItems.enumerated().reversed()), id: \.element.id) { depth, item in
                cardView(item: item, depth: depth)
            }
        }
        .onChange(of: programmaticAction) { _, newValue in
            guard let action = newValue, let top = items.first else { return }
            performFly(action, item: top)
        }
    }

    private var visibleItems: [Item] { Array(items.prefix(visibleDepth)) }

    @ViewBuilder
    private func cardView(item: Item, depth: Int) -> some View {
        let isTop = depth == 0
        card(item)
            .zIndex(Double(visibleDepth - depth))
            .scaleEffect(Self.restScale(depth: depth))
            .offset(x: isTop ? currentOffset.width : 0, y: Self.restYOffset(depth: depth) + (isTop ? currentOffset.height : 0))
            .rotationEffect(.degrees(isTop ? currentRotation : 0))
            .opacity(depth > 1 ? 0 : 1)
            .overlay(alignment: .topTrailing) {
                if isTop { stamp(rightStampTitle, rotation: 14, opacity: rightStampOpacity) }
            }
            .overlay(alignment: .topLeading) {
                if isTop { stamp(leftStampTitle, rotation: -14, opacity: leftStampOpacity) }
            }
            .gesture(dragGesture(for: item, isTop: isTop))
            .animation(isDragging || reduceMotion ? nil : .interactiveSpring(response: 0.4, dampingFraction: 0.86), value: dragTranslation.width)
    }

    // MARK: - Drag → swipe/tap

    /// Attached to every visible card (not just the top one) because a
    /// conditional `Gesture?` has no clean SwiftUI spelling — but the kit's
    /// "peek" look intentionally leaves a sliver of the card(s) behind
    /// visible past the top card's edges, so a stray touch landing on that
    /// sliver would otherwise mutate the *shared* `dragTranslation`/
    /// `isDragging` state the top card reads, visibly yanking it. `isTop`
    /// gates every callback to a no-op for every card except the front one.
    private func dragGesture(for item: Item, isTop: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isTop else { return }
                isDragging = true
                dragTranslation = CGSize(width: value.translation.width, height: value.translation.height * 0.4)
            }
            .onEnded { value in
                guard isTop else { return }
                isDragging = false
                let translation = value.translation
                if hypot(translation.width, translation.height) < Self.tapThreshold {
                    dragTranslation = .zero
                    onTap(item)
                } else if translation.width > Self.swipeThreshold {
                    performFly(.right, item: item)
                } else if translation.width < -Self.swipeThreshold {
                    performFly(.left, item: item)
                } else {
                    dragTranslation = .zero
                }
            }
    }

    /// Plays the kit's `fly()` animation (real swipe or `programmaticAction`),
    /// then — after the same ~220ms the kit waits before `idx++; render()` —
    /// invokes the matching callback so the caller advances its own state.
    private func performFly(_ action: SwipeDeckAction, item: Item) {
        let sign: CGFloat = action == .right ? 1 : -1
        let animation: Animation? = reduceMotion ? nil : Motion.easeSoft(duration: 0.45)
        withAnimation(animation) {
            flyOffset = CGSize(width: sign * Self.flyDistance, height: Self.flyVerticalDrift)
            flyRotation = Double(sign) * Self.flyRotationDegrees
        }
        let delay = reduceMotion ? 0 : 0.22
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            switch action {
            case .right: onSwipeRight(item)
            case .left: onSwipeLeft(item)
            }
            // Reset so whichever item is now on top (one card back) renders
            // at rest rather than inheriting the flown-out transform.
            dragTranslation = .zero
            flyOffset = nil
            flyRotation = 0
            if programmaticAction != nil { programmaticAction = nil }
        }
    }

    // MARK: - Live transform (drag or fly-out)

    private var currentOffset: CGSize { flyOffset ?? dragTranslation }
    private var currentRotation: Double {
        if let flyOffset { return flyOffset.width > 0 ? Self.flyRotationDegrees : -Self.flyRotationDegrees }
        return Double(dragTranslation.width / 18)
    }

    /// Kit `move()`: `p = clamp(dx / 120, -1, 1)`, then each stamp's opacity
    /// tracks `p` (or `-p`) on its own side.
    private var dragProgress: CGFloat {
        if let flyOffset { return flyOffset.width > 0 ? 1 : -1 }
        return max(-1, min(1, dragTranslation.width / 120))
    }
    private var rightStampOpacity: Double { Double(max(dragProgress, 0)) }
    private var leftStampOpacity: Double { Double(max(-dragProgress, 0)) }

    // MARK: - Stamp overlay (kit `.stamp.in` / `.stamp.skip`)

    private func stamp(_ title: String, rotation: Double, opacity: Double) -> some View {
        Text(title.uppercased())
            .font(.system(size: 15, weight: .heavy))
            .tracking(1)
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 3)
            )
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .padding(26)
            .allowsHitTesting(false)
    }
}
