//
//  SwipeToDeleteContainer.swift
//  GymStreak
//
//  Hand-rolled swipe-to-delete for the history list.
//
//  `.swipeActions` and `.onDelete` are unavailable here: both require a `List`
//  or `Form`, while the history list is a `ScrollView` of custom cards grouped
//  under month dividers, nested inside the history screen's own `ScrollView`.
//  Converting the screen to a `List` was rejected (see docs/delete-workout.md).
//

import SwiftUI

/// Shared open/drag state for the history list's swipe rows.
///
/// Owned by `HistoryView` — the view that owns the scroll view — so that at
/// most one card can be open at a time and so scrolling can close it.
struct HistorySwipeState {
    /// The card whose delete action is currently revealed, if any.
    var openCardId: UUID?
    /// The card whose horizontal drag is currently in flight, if any. Tracked by
    /// id rather than as a flag so a second finger on another card cannot end
    /// the first card's drag. Scroll-driven closing is suppressed while it is
    /// set, so a slightly diagonal swipe cannot close the very card it is opening.
    var draggingCardId: UUID?
}

/// Wraps a history card so dragging it to the left reveals a destructive delete action.
///
/// The drag is attached with `.simultaneousGesture` and a 15pt minimum distance so
/// the enclosing scroll view keeps its own pan gesture — `.gesture` and
/// `.highPriorityGesture` both starve it. Movement is only tracked once the drag is
/// horizontally dominant, which keeps vertical scrolling from catching on a row.
///
/// **The wrapped content must not be a `Button` or `NavigationLink`.** Selection is
/// this container's own `TapGesture`, reported through `onSelect`, because a SwiftUI
/// button activates on touch-up anywhere inside its bounds: a swipe that begins and
/// ends on the card is a valid activation, so wrapping a `NavigationLink` made every
/// swipe push the detail screen. See docs/delete-workout.md.
struct SwipeToDeleteContainer<Content: View>: View {
    /// Identity of the wrapped card, matched against `HistorySwipeState.openCardId`.
    let id: UUID
    @Binding var state: HistorySwipeState
    /// Invoked when the revealed action (or the VoiceOver delete action) is triggered.
    let onDelete: () -> Void
    /// Invoked when the card is tapped while closed — the caller performs the push.
    let onSelect: () -> Void
    private let content: Content

    /// Live translation of the in-flight drag; the resting offset comes from `isOpen`.
    @State private var dragTranslation: CGFloat = 0

    private let actionWidth: CGFloat = 84
    private let cornerRadius: CGFloat = 20

    init(
        id: UUID,
        state: Binding<HistorySwipeState>,
        onDelete: @escaping () -> Void,
        onSelect: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self._state = state
        self.onDelete = onDelete
        self.onSelect = onSelect
        self.content = content()
    }

    private var isOpen: Bool { state.openCardId == id }

    /// Clamped between fully closed and slightly past the action width, so an
    /// over-drag has a little give without exposing empty space.
    private var offset: CGFloat {
        let resting: CGFloat = isOpen ? -actionWidth : 0
        return min(0, max(resting + dragTranslation, -actionWidth - 16))
    }

    var body: some View {
        content
            // The card is no longer a button, so the row's button semantics are
            // rebuilt here: one combined element, activated by VoiceOver's double
            // tap, with delete offered in the Actions rotor.
            // (`AccessibilityActionKind.delete` is macOS-only, hence the named action.)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { select() }
            .accessibilityAction(named: Text("action.delete".localized)) { triggerDelete() }
            // The card's own background is nearly transparent; an opaque backdrop
            // in the screen's background colour keeps the red action from showing
            // through it while the card is at rest.
            .background(
                DesignSystem.Colors.background,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .onTapGesture { handleTap() }
            // Restores what dropping the NavigationLink cost keyboard users:
            // Full Keyboard Access can focus the row and open it with Return.
            .focusable()
            .onKeyPress(.return) {
                select()
                return .handled
            }
            .onKeyPress(.space) {
                select()
                return .handled
            }
            .simultaneousGesture(dragGesture)
            .offset(x: offset)
            // Applied outside the offset so it stays put while the card slides,
            // and sized from the card so it fills the row's full height.
            .background(alignment: .trailing) { deleteAction }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    // MARK: - Revealed action

    private var deleteAction: some View {
        Button {
            triggerDelete()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 17, weight: .semibold))
                Text("action.delete".localized)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Color.white)
            .frame(width: actionWidth)
            .frame(maxHeight: .infinity)
            .background(DesignSystem.Colors.destructive)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Only an element once revealed — while it sits behind a closed card
        // VoiceOver would otherwise announce a control the user cannot see.
        // The card's delete action covers the closed case.
        .accessibilityHidden(!isOpen)
    }

    // MARK: - Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 15, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if state.draggingCardId != id {
                    state.draggingCardId = id
                    // Opening a card closes whichever one was open before.
                    if state.openCardId != nil && !isOpen {
                        withAnimation(DesignSystem.Animation.spring) { state.openCardId = nil }
                    }
                }
                dragTranslation = value.translation.width
            }
            .onEnded { _ in
                // Only the card that owns the in-flight drag resolves it; any
                // other card just springs back to where its open state says.
                let wasTracking = state.draggingCardId == id
                if wasTracking { state.draggingCardId = nil }
                let shouldOpen = wasTracking && offset < -actionWidth / 2
                if shouldOpen && !isOpen { HapticManager.shared.light() }
                withAnimation(DesignSystem.Animation.spring) {
                    if wasTracking { state.openCardId = shouldOpen ? id : nil }
                    dragTranslation = 0
                }
            }
    }

    // MARK: - Actions

    private func close() {
        withAnimation(DesignSystem.Animation.spring) {
            state.openCardId = nil
            dragTranslation = 0
        }
    }

    /// A tap while *any* card is open only dismisses it — the same rule a `List`
    /// row follows, so a swipe left open never leads to an accidental push.
    private func handleTap() {
        guard state.openCardId == nil else {
            close()
            return
        }
        select()
    }

    private func select() {
        HapticManager.shared.light()
        // Leaving the list closes whichever card was open.
        state.openCardId = nil
        onSelect()
    }

    private func triggerDelete() {
        close()
        onDelete()
    }
}
