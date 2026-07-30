//
//  ProgressiveOverloadViews.swift
//  GymStreakWatch Watch App
//
//  The three mid-workout progressive-overload surfaces from the approved design
//  (Claude Design — "Progressive Overload.html", surface 2):
//
//    2a  suggestion capsule — orange, in the thumb zone over the set controls
//    2b  increment picker   — Digital Crown / tap, pushed onto WorkoutRoute
//    2c  confirmation       — full-bleed green moment, then back to the workout
//
//  These are presentation only. Every one of them reports intent to
//  `WatchWorkoutViewModel` (`applyProgressiveOverload`, `showOverloadIncrementPicker`,
//  `deferProgressiveOverload`) and holds no persistence, math, or transport.
//

import SwiftUI
import WatchKit

// MARK: - Container

/// The whole overload flow, as ONE modal sheet presented by `ActiveWorkoutView`.
///
/// Why a sheet and not the floating card this started as: on watchOS a sheet is
/// **always modal** — it blocks interaction with the presenter for free, which is
/// what stops stray taps landing on the live set controls underneath. Apple's
/// HIG also points custom-content prompts at sheets rather than alerts or action
/// sheets, whose plain title/message/button anatomy cannot carry this content
/// (colored icon, computed weight, resulting-weight preview).
///
/// The steps switch content INSIDE this one sheet rather than pushing: the
/// workout owns exactly one `NavigationStack`, and a second one (or a competing
/// sheet) is the thing the in-workout-editing tickets explicitly forbid.
///
/// Note the modality is a UX guarantee, not the data guarantee: set completion is
/// already blocked while the flow is up by `isWorkoutInputSuspended`, which is
/// also the ONLY thing that stops the Action Button — that arrives through a
/// donated App Intent, which bypasses the SwiftUI hierarchy entirely and is
/// therefore unaffected by any presentation style.
struct ProgressiveOverloadSheet: View {
    @EnvironmentObject private var viewModel: WatchWorkoutViewModel

    var body: some View {
        step
            // Presented from INSIDE the sheet: an alert attached to the
            // presenting view cannot surface above it. A failed local write or
            // an unresolvable target returns to the suggestion, which stays
            // actionable behind this alert.
            .alert(
                "Weight increase",
                isPresented: Binding(
                    get: { viewModel.overloadErrorMessage != nil },
                    set: { if !$0 { viewModel.overloadErrorMessage = nil } }
                ),
                presenting: viewModel.overloadErrorMessage
            ) { _ in
                Button("OK", role: .cancel) { viewModel.overloadErrorMessage = nil }
            } message: { message in
                Text(message)
            }
    }

    /// Reads only `overloadPresentation` and the pre-resolved
    /// `overloadDisplay` — no lookups, no service calls, no collection walks.
    @ViewBuilder
    private var step: some View {
        switch viewModel.overloadPresentation {
        case .suggestion(let slotID), .applying(let slotID):
            if let display = viewModel.overloadDisplay, let targetRepMax = display.targetRepMax {
                ProgressiveOverloadSuggestionView(
                    exerciseName: display.exerciseName,
                    targetRepMax: targetRepMax,
                    defaultIncrement: ProgressiveOverloadIncrement.default,
                    isAssistance: display.isAssistance,
                    onApply: {
                        viewModel.applyProgressiveOverload(
                            slotID: slotID, increment: ProgressiveOverloadIncrement.default
                        )
                    },
                    onChange: { viewModel.showOverloadIncrementPicker(slotID: slotID) },
                    onLater: { viewModel.deferProgressiveOverload(slotID: slotID) }
                )
            } else {
                unavailableStep(slotID: slotID)
            }

        case .picker(let slotID):
            if let display = viewModel.overloadDisplay {
                ProgressiveOverloadIncrementPicker(
                    exerciseName: display.exerciseName,
                    currentWeight: display.templateWeight,
                    isAssistance: display.isAssistance,
                    hasUniformWeights: display.hasUniformWeights,
                    onApply: { increment in
                        viewModel.applyProgressiveOverload(slotID: slotID, increment: increment)
                    },
                    onCancel: { viewModel.setOverloadPresentation(.suggestion(slotID: slotID)) }
                )
            } else {
                unavailableStep(slotID: slotID)
            }

        case .confirmation(_, let newWeight, let targetRepMin):
            ProgressiveOverloadConfirmationView(
                newWeight: newWeight,
                targetRepMin: targetRepMin,
                // A slot that vanished falls back to the resistance wording.
                isAssistance: viewModel.overloadDisplay?.isAssistance ?? false,
                hasUniformWeights: viewModel.overloadDisplay?.hasUniformWeights ?? true
            ) {
                viewModel.dismissOverloadConfirmation()
            }

        case .none:
            EmptyView()
        }
    }

    /// The target stopped being resolvable while its step was on screen — the
    /// slot was removed or swapped, and `revalidateOverloadPresentation` has not
    /// closed the flow yet. Without this the sheet would render nothing, leaving
    /// a blank modal whose only escape is a swipe the user has no reason to
    /// expect. Never a silent auto-apply: the transaction is abandoned.
    private func unavailableStep(slotID: UUID) -> some View {
        VStack(spacing: 12) {
            Text(
                "This exercise is no longer part of the workout.",
                comment: "Shown when a progressive-overload target disappears while its sheet is open"
            )
            .font(.system(size: 14, weight: .medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(OnyxWatch.Colors.textSecondary)

            Button {
                viewModel.deferProgressiveOverload(slotID: slotID)
            } label: {
                Text("Close", comment: "Dismisses the progressive-overload sheet")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(OnyxWatch.Colors.card, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
    }
}

// MARK: - 2a · Suggestion

/// The first step of the sheet: what happened, and the one recommended action.
///
/// This was a floating card pinned to the bottom of the live workout screen. As
/// sheet content it no longer draws its own card chrome — HIG asks modal sheets
/// to keep the system material rather than replace it — and it gains room for
/// the exercise name, which the cramped card never showed.
struct ProgressiveOverloadSuggestionView: View {
    let exerciseName: String
    let targetRepMax: Int
    let defaultIncrement: Double
    let isAssistance: Bool
    let onApply: () -> Void
    let onChange: () -> Void
    let onLater: () -> Void

    var body: some View {
        // Scrolls so the largest Dynamic Type sizes cannot clip the actions.
        ScrollView {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(OnyxWatch.Colors.warning.opacity(0.28))
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(OnyxWatch.Colors.warning)
                }
                .frame(width: 34, height: 34)
                .padding(.bottom, 8)

                Text("Ready for more", comment: "Mid-workout progressive-overload suggestion title")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(OnyxWatch.Colors.textPrimary)

                Text(exerciseName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OnyxWatch.Colors.textSecondary)
                    .lineLimit(2)
                    .padding(.top, 2)

                Text(
                    "All sets at \(targetRepMax) reps — range maxed.",
                    comment: "Mid-workout progressive-overload suggestion subtitle; parameter is the rep-range maximum"
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OnyxWatch.Colors.warning.opacity(0.85))
                .padding(.top, 6)

                Button(action: onApply) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                        Text(
                            "\(ProgressiveOverloadFormat.increment(defaultIncrement, isAssistance: isAssistance)) · all sets",
                            comment: "Mid-workout progressive-overload primary action; parameter is the signed weight step"
                        )
                        .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(OnyxWatch.Colors.textOnWarning)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(OnyxWatch.Colors.warning, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 14)

                // Full-width targets, not the cramped inline text pair the card
                // had — those were what made a missed tap plausible.
                Button(action: onChange) {
                    Text("Change", comment: "Opens the progressive-overload increment picker")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OnyxWatch.Colors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(OnyxWatch.Colors.card, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)

                Button(action: onLater) {
                    Text("Later", comment: "Dismisses the mid-workout progressive-overload suggestion")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OnyxWatch.Colors.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.plain)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6)
        }
    }
}

