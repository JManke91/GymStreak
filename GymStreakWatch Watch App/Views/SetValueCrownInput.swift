//
//  SetValueCrownInput.swift
//  GymStreakWatch Watch App
//
//  The Digital Crown half of the set editor: while a value card is unlocked,
//  each Crown detent steps the focused value; while it is locked, a turn is
//  only reported so the editor can say "Tap first". Applied by
//  FullScreenSetEditorView, which owns the lock and decides what a step means.
//

import SwiftUI
import WatchKit

enum SetValueCrown {
    /// How long an unlocked card waits for Crown input before locking again.
    static let relockDelay: TimeInterval = 3
}

extension View {
    /// Holds the Crown while `isListening` and routes its detents to
    /// `onDetents` while `isActive`.
    ///
    /// `isListening` is the editor's ownership condition (no rest timer
    /// candidate holding the Crown, mutation allowed) — this view is
    /// Crown-focusable exactly then. `isActive` additionally requires an
    /// unlocked card; only then do detents change a value and click. A locked
    /// rotation goes to `onLockedTurn` with its running detent count instead.
    /// `isUnlocked` is set back to false `SetValueCrown.relockDelay` after the
    /// last Crown input; every (re)start of that delay is reported to
    /// `onRelockScheduled` with its deadline. A change of `armingID` (a fresh
    /// tap on a card) restarts it.
    func setValueCrownInput(
        isListening: Bool,
        isActive: Bool,
        isUnlocked: Binding<Bool>,
        armingID: Int,
        onDetents: @escaping (Int) -> Void,
        onCommit: @escaping () -> Void,
        onLockedTurn: @escaping (Int) -> Void,
        onRelockScheduled: @escaping (Date) -> Void
    ) -> some View {
        modifier(
            SetValueCrownInput(
                isListening: isListening,
                isActive: isActive,
                isUnlocked: isUnlocked,
                armingID: armingID,
                onDetents: onDetents,
                onCommit: onCommit,
                onLockedTurn: onLockedTurn,
                onRelockScheduled: onRelockScheduled
            )
        )
    }
}

private struct SetValueCrownInput: ViewModifier {
    let isListening: Bool
    let isActive: Bool
    @Binding var isUnlocked: Bool
    let armingID: Int
    let onDetents: (Int) -> Void
    /// Makes the buffered detents durable (the checkpoint). Called once per
    /// rotation and whenever the Crown is taken away mid-rotation — never per
    /// detent.
    let onCommit: () -> Void
    let onLockedTurn: (Int) -> Void
    let onRelockScheduled: (Date) -> Void

    /// Scratch detent counter. It never means a value: only the difference
    /// between two readings is applied, which is what keeps a weight that is
    /// off the display grid unsnapped. Continuous, so it wraps at the range
    /// bounds — `detents(from:to:wrappingAt:)` reads a wrap as the short way.
    @State private var detentCounter: Double = 0
    @State private var hasUncommittedDetents = false
    /// Detents of the current locked rotation; reset when the Crown idles.
    @State private var lockedDetents = 0
    @State private var relockTask: Task<Void, Never>?
    @FocusState private var isCrownFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    private static let counterRange: Double = 10_000
    /// Focus requested in the same update as a push is reported not to take;
    /// wait out the push transition first.
    private static let appearFocusDelay: Duration = .milliseconds(400)

    func body(content: Content) -> some View {
        content
            // MUST precede `.digitalCrownRotation` and sit on the same view as
            // `.focused`, or Crown input silently does nothing.
            .focusable(isListening)
            // The focusable view is the whole editor; a system focus ring
            // around it would be noise.
            .focusEffectDisabled()
            .focused($isCrownFocused)
            .defaultFocus($isCrownFocused, true)
            .digitalCrownRotation(
                detent: $detentCounter,
                from: -Self.counterRange,
                through: Self.counterRange,
                by: 1,
                // Passed explicitly — Apple's docs disagree on the default.
                sensitivity: .medium,
                // Continuous hides the system Crown indicator, which otherwise
                // shows as a scroll bar on a locked turn (forum 707381).
                isContinuous: true,
                // Off for good: the flag is read when the modifier is installed,
                // so it cannot follow the lock (device test 2026-10-23). The
                // unlocked click is played in `applyDetents` instead.
                isHapticFeedbackEnabled: false,
                onIdle: rotationDidSettle
            )
            .onChange(of: detentCounter) { previous, current in
                applyDetents(from: previous, to: current)
            }
            .onChange(of: isActive) { _, active in
                if active {
                    lockedDetents = 0
                    scheduleRelock()
                } else {
                    relockTask?.cancel()
                    commitIfNeeded()
                }
            }
            .onChange(of: isListening) { _, listening in
                // One tick later: setting focus in the same update that makes
                // the view focusable is reported not to take (forums 683806,
                // 767044).
                Task { @MainActor in isCrownFocused = listening }
            }
            .onChange(of: armingID) { _, _ in
                if isActive { scheduleRelock() }
            }
            .task {
                try? await Task.sleep(for: Self.appearFocusDelay)
                reclaimFocus()
            }
            // Wrist-down / Always-On can drop the focus without telling us.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { reclaimFocus() }
            }
            .onDisappear {
                relockTask?.cancel()
                commitIfNeeded()
            }
    }

    private func applyDetents(from previous: Double, to current: Double) {
        let detents = WatchSetValueStepping.detents(from: previous, to: current, wrappingAt: Self.counterRange)
        guard detents != 0 else { return }
        // A Crown turned while locked never changes a value — it only earns
        // the hint.
        guard isActive else {
            lockedDetents += detents
            onLockedTurn(lockedDetents)
            return
        }
        WKInterfaceDevice.current().play(.click)
        onDetents(detents)
        hasUncommittedDetents = true
        scheduleRelock()
    }

    private func reclaimFocus() {
        guard isListening else { return }
        isCrownFocused = true
    }

    /// Restarted by every unlock and every detent, so the lock closes 3 s after
    /// the last Crown input — taps on ± do not hold it open.
    private func scheduleRelock() {
        relockTask?.cancel()
        onRelockScheduled(Date.now.addingTimeInterval(SetValueCrown.relockDelay))
        relockTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(SetValueCrown.relockDelay))
            guard !Task.isCancelled else { return }
            isUnlocked = false
        }
    }

    private func rotationDidSettle() {
        lockedDetents = 0
        commitIfNeeded()
    }

    private func commitIfNeeded() {
        guard hasUncommittedDetents else { return }
        hasUncommittedDetents = false
        onCommit()
    }
}
