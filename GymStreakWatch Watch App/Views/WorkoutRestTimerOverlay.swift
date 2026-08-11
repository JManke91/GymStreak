//
//  WorkoutRestTimerOverlay.swift
//  GymStreakWatch Watch App
//
//  The one and only rest timer of an active workout, in BOTH of its states.
//  ActiveWorkoutView mounts this as a sibling of its NavigationStack, so:
//    • exactly one minimized pill can ever exist — the vertical TabView keeps
//      neighbouring pages alive, so the previous per-page copies (exercise
//      list, metrics, controls) could be mounted at the same time;
//    • the pill layers ABOVE a pushed set editor instead of being covered by it;
//    • large and minimized live in one coordinate space, which is what lets the
//      shared surface and the countdown digits morph between them.
//

import SwiftUI

/// Constants shared by the two rest-timer states so they morph into each other.
enum WatchRestTimerMorph {
    /// `matchedGeometryEffect` ids — one shared progress surface, one shared
    /// countdown. Everything else (caption, buttons, metric rows, pill chrome)
    /// is non-shared and simply cross-fades.
    static let surfaceID = "watchRestTimerSurface"
    static let digitsID = "watchRestTimerDigits"

    /// Both states draw the surface as a continuous rounded rectangle with this
    /// radius, so only its *frame* has to interpolate. At full-screen size the
    /// radius is far smaller than the watch display's own corner radius, so the
    /// large panel still covers every visible pixel.
    static let surfaceCornerRadius: CGFloat = 18

    static let response: TimeInterval = 0.42

    static let animation: Animation = .spring(response: response, dampingFraction: 0.85)

    /// How the timer as a whole appears and disappears (a rest starting/ending),
    /// as opposed to `animation`, which drives large↔minimized.
    ///
    /// Owned here because a screen that reserves space for the pill has to fade
    /// its slot on exactly the same curve — see `reservedSlotHeight`.
    static let presenceAnimation: Animation = .easeInOut(duration: 0.25)

    /// Height a screen must free at the top when it has no empty top-trailing
    /// slot of its own (`ExerciseListView`). The pill hangs `baselineLift` above
    /// the safe-area top, so only its lower part reaches into the content, plus a
    /// small breathing gap.
    static let reservedSlotHeight: CGFloat = 16
}

/// Who owns the Digital Crown while a rest runs.
///
/// Crown routing is effectively single-owner and there is no focus-restoration
/// stack, so ownership is modelled explicitly instead of being left to two views
/// both declaring `.focusable(true)`: every candidate declares
/// `.focusable(crownOwner == .<itself>)` and `WorkoutRestTimerOverlay` derives
/// the value. `.none` leaves the Crown to whatever is underneath — the exercise
/// list's scroll, or a pushed destination.
enum WatchRestCrownOwner {
    case none
    case largeTimer
    case pillStepper
}

private struct RestPillStepperOpenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while the minimized pill is grown into its inline ± stepper. Read by
    /// the workout screens whose top-trailing content the grown pill covers —
    /// see `WorkoutTopProgressView`. Published by `ActiveWorkoutView`, which owns
    /// the flag because the overlay is a *sibling* of the screens that read it.
    var isRestPillStepperOpen: Bool {
        get { self[RestPillStepperOpenKey.self] }
        set { self[RestPillStepperOpenKey.self] = newValue }
    }
}

struct WorkoutRestTimerOverlay: View {
    @EnvironmentObject var viewModel: WatchWorkoutViewModel

    /// Whether the minimized pill is grown into its inline stepper. Owned by
    /// `ActiveWorkoutView` so the screens under the pill can fade the content it
    /// covers; the pill itself opens and closes it.
    @Binding var isStepperOpen: Bool

    /// Namespace for the large↔minimized morph. Owned here because this view is
    /// never itself removed while a rest runs — both states are its children.
    @Namespace private var morphNamespace

    /// When the last morph was started. User toggles arriving within one morph
    /// duration of it are dropped. See `setMinimized(_:)`.
    @State private var lastMorphStart: Date = .distantPast

    /// False while a large↔pill morph is in flight. Handed to the large state,
    /// which owns the Digital Crown only while it is true: crown-driven resizing
    /// of a view mid-`matchedGeometryEffect`, and a glyph-replacing
    /// `.contentTransition` on the shared digits while they interpolate, are both
    /// undocumented territory. Driven off the flag rather than off `setMinimized`
    /// so state-driven switches (a rest elapsing while minimized) count too.
    @State private var isMorphSettled = true
    @State private var morphSettleTask: Task<Void, Never>?

    /// Distance from the screen's trailing edge to the pill's visible edge.
    /// Matches the set editor's content inset (8pt screen padding + 2pt top-zone
    /// padding), which is where the pill used to sit.
    private static let trailingInset: CGFloat = 10

    /// How far the pill is raised above the top of the safe area. The safe area
    /// begins at the "Exercise X / Y" label; the 2026-07-24 design pinned the
    /// pill's BOTTOM to that label's text baseline, i.e. it overhangs upward into
    /// the free status-bar space beside the system clock instead of crowding the
    /// segment progress bar below. Reproduces that without the per-screen
    /// `alignmentGuide` trick, which only worked inside `WorkoutTopProgressView`.
    private static let baselineLift: CGFloat = 12

    var body: some View {
        content
            .animation(WatchRestTimerMorph.presenceAnimation, value: viewModel.isResting)
            // Implicit, so EVERY change of the flag animates — including the
            // state-driven expand the view model performs when a rest elapses
            // naturally, which no explicit transaction of ours would cover.
            .animation(WatchRestTimerMorph.animation, value: viewModel.isRestTimerMinimized)
            .onChange(of: viewModel.isRestTimerMinimized) { _, _ in
                markMorphInFlight()
                closeStepper()
            }
            .onChange(of: viewModel.isResting) { _, _ in closeStepper() }
    }

    /// Exactly one view is Crown-focusable at a time, by construction: both
    /// candidates declare `.focusable(crownOwner == .<itself>)` against this one
    /// value. It is derived, never stored, so no path can leave two owners set.
    ///
    /// Ownership is additionally gated on the morph having settled — Crown input
    /// is inert while a large↔pill transition is in flight.
    private var crownOwner: WatchRestCrownOwner {
        guard viewModel.isResting, isMorphSettled else { return .none }
        if viewModel.isRestTimerMinimized {
            // The pill takes the Crown only while its stepper is open, so the
            // list underneath keeps Crown scrolling the rest of the time.
            return isStepperOpen ? .pillStepper : .none
        }
        return .largeTimer
    }

    /// The stepper belongs to the minimized state only, so expanding — or a rest
    /// ending while it is open — takes it down. The pill's own `onDisappear`
    /// flushes whatever it had buffered.
    ///
    /// **In a transaction**, and only when it is actually open: this runs in the
    /// same frame the pill starts being removed by its `.transition(.opacity)`,
    /// and an unanimated flip would snap the pill's chrome from `opacity(0)` back
    /// to 1 — a hard flash of the pill's own digits exactly while the shared
    /// digits are interpolating into the large timer.
    private func closeStepper() {
        guard isStepperOpen else { return }
        withAnimation(WatchRestPillStepper.spring) { isStepperOpen = false }
    }

    /// Marks a morph as running and clears the flag one morph duration later.
    /// Wall-clock like the re-toggle guard, and for the same reason: a flag
    /// released by an animation-completion callback stuck on watchOS.
    private func markMorphInFlight() {
        isMorphSettled = false
        morphSettleTask?.cancel()
        morphSettleTask = Task {
            try? await Task.sleep(for: .seconds(WatchRestTimerMorph.response))
            guard !Task.isCancelled else { return }
            isMorphSettled = true
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isResting {
            if viewModel.isRestTimerMinimized {
                // Compact pill in the top-trailing corner. The expanding frame
                // only positions it: it draws nothing and has no content shape,
                // so it never swallows taps meant for the screen underneath.
                RestTimerMinimizedPill(
                    timeRemaining: viewModel.restTimeRemaining,
                    totalDuration: viewModel.restDuration,
                    namespace: morphNamespace,
                    crownOwner: crownOwner,
                    isStepperOpen: $isStepperOpen,
                    onExpand: { setMinimized(false) }
                )
                // Resolve this state's geometry as one unit before the parent
                // pushes changes down — the sibling NavigationStack pushing or
                // popping the set editor otherwise bleeds into the frames the
                // morph is animating.
                .geometryGroup()
                // The pill's own visible box, unchanged from the set editor's
                // 2026-07-24 design (the +2×touchInset is the transparent touch
                // margin the pill adds around itself). The inline stepper is an
                // OVERLAY on the pill's card, so it grows leftward out of this
                // box without changing it — which is what keeps the drawn pill's
                // height and position identical whether it is open or not.
                .frame(
                    maxWidth: 96 + 2 * RestTimerMinimizedPill.touchInset,
                    maxHeight: 22 + 2 * RestTimerMinimizedPill.touchInset
                )
                .padding(.trailing, Self.trailingInset - RestTimerMinimizedPill.touchInset)
                .offset(y: -(Self.baselineLift + RestTimerMinimizedPill.touchInset))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                // Only the non-shared chrome fades; the surface and the digits
                // travel and resize via matchedGeometryEffect.
                .transition(.opacity)
                .zIndex(0)
            } else {
                RestTimerLargeView(
                    timeRemaining: viewModel.restTimeRemaining,
                    totalDuration: viewModel.restDuration,
                    formattedTime: viewModel.formattedRestTime,
                    state: viewModel.restTimerState,
                    namespace: morphNamespace,
                    isMorphSettled: isMorphSettled,
                    crownOwner: crownOwner,
                    onSkip: viewModel.skipRest,
                    onMinimize: { setMinimized(true) }
                )
                .geometryGroup()
                .transition(.opacity)
                // The large panel stays above the pill for the whole cross-fade,
                // so minimizing reads as one object shrinking into the corner
                // rather than the pill popping in front of it.
                .zIndex(1)
            }
        }
    }

    /// Switches between the large timer and the pill in a single animated
    /// transaction, so the shared surface and digits morph between them.
    ///
    /// Taps arriving while a morph is in flight are dropped: interrupting an
    /// in-flight `matchedGeometryEffect` transition is a documented source of
    /// ghosted or duplicated views and of AttributeGraph crashes.
    ///
    /// The window is measured against the wall clock rather than released by an
    /// animation-completion callback. A `withAnimation(_:completionCriteria:)`
    /// completion was tried first and **stuck**: it fired for the minimize but
    /// not for the following expand, so the flag stayed set and every later
    /// minimize was silently dropped. A time-boxed guard cannot get stuck.
    ///
    /// The guard deliberately gates **user** toggles only. State-driven changes
    /// (a rest being skipped, elapsing, or the next one starting) are published
    /// by the view model and reach the overlay directly, so they can never be
    /// swallowed and the overlay can never stick in the wrong state.
    private func setMinimized(_ minimized: Bool) {
        guard viewModel.isRestTimerMinimized != minimized else { return }

        let now = Date()
        guard now.timeIntervalSince(lastMorphStart) >= WatchRestTimerMorph.response else { return }
        lastMorphStart = now

        withAnimation(WatchRestTimerMorph.animation) {
            if minimized {
                viewModel.minimizeRestTimer()
            } else {
                viewModel.expandRestTimer()
            }
        }
    }
}
