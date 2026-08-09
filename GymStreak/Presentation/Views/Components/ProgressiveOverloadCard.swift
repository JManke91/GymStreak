//
//  ProgressiveOverloadCard.swift
//  GymStreak
//
//  Actionable progressive-overload suggestion card for the post-workout
//  completion screen ("Bereit für mehr Gewicht" surface of the Progressive
//  Overload design). Two states:
//  - actionable: orange achievement card with per-set recap and a full-width
//    "increase weight" CTA that opens the WeightIncreaseSheet
//  - applied: quiet confirmation row with the new weight and an optional Undo
//

import SwiftUI

struct ProgressiveOverloadCard: View {
    let exercise: WorkoutExercise
    /// Live library exercise resolved via the routine-template slot; drives
    /// the avatar and subtitle. Nil for history whose template is gone.
    let libraryExercise: Exercise?
    let canUndo: Bool
    /// History surface only: force the confirmed state after applying to the
    /// live template. The historical `WorkoutExercise` is never mutated, so its
    /// own `progressiveOverloadApplied` flag stays false.
    var appliedOverride: Bool = false
    /// The new template weight for the confirmed row. Required on EVERY surface:
    /// an applied increase raises the template and leaves the workout's sets at
    /// the performance, so this can no longer be read off them anywhere. Nil
    /// falls back to the weight-free confirmation.
    var appliedWeight: Double? = nil
    /// The increase was applied, but the target's sets do not all share one
    /// weight — a pyramid or drop scheme. The confirmed row then states that all
    /// sets moved instead of naming a weight that is wrong for every set but
    /// the first.
    var hasAmbiguousAppliedWeight: Bool = false
    /// The live template's current first-set weight, struck through in the
    /// actionable CTA. Nil falls back to the performed weight.
    var templateWeight: Double? = nil
    /// History surface only: the source routine/exercise no longer exists, so
    /// the increase can't be applied. Replaces the CTA with a muted note.
    var isTemplateUnavailable: Bool = false
    let onIncrease: () -> Void
    let onUndo: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isApplied: Bool { exercise.progressiveOverloadApplied || appliedOverride }
    private var isAssistance: Bool { exercise.loadBehavior.isCounterweightAssistance }
    private var sortedSets: [WorkoutSet] { exercise.setsList.sorted { $0.order < $1.order } }

    /// The weight the confirmed row may announce. An applied increase raises
    /// the TEMPLATE and leaves the workout's sets at the performance, so it can
    /// never be read off `exercise` — only a caller that knows what was written
    /// can supply it. Nil (unknown, or a nonuniform pyramid/drop scheme) renders
    /// "all sets adjusted" rather than a number that would be wrong.
    private var confirmedWeight: Double? { hasAmbiguousAppliedWeight ? nil : appliedWeight }

    /// The weight the actionable CTA strikes through: what an increase would
    /// start from, i.e. the live template. Falls back to the performance only
    /// when the caller could not resolve the template.
    private var actionableCurrentWeight: Double { templateWeight ?? sortedSets.first?.actualWeight ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isApplied {
                confirmRow
            } else {
                description
                if !dynamicTypeSize.isAccessibilitySize {
                    setRecap
                }
                if isTemplateUnavailable {
                    unavailableNote
                } else {
                    increaseButton
                }
            }
        }
        .padding(15)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusXL, style: .continuous)
                .strokeBorder(
                    isApplied ? DesignSystem.Colors.divider : Color.orange.opacity(0.38),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusXL, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 11) {
            ExerciseAvatarView(
                muscleGroups: exercise.muscleGroups,
                equipmentType: libraryExercise?.equipmentType ?? .dumbbell
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.exerciseName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if !isApplied && !isTemplateUnavailable {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.orange)
                    .frame(width: 34, height: 34)
                    .background(Color.orange.opacity(0.22), in: Circle())
            }
        }
    }

    private var subtitle: String {
        var parts = [MuscleGroups.displayName(for: exercise.muscleGroups.first ?? "General")]
        if let equipment = libraryExercise?.equipmentType {
            parts.append(equipment.displayName)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actionable state

    private var description: some View {
        Text(accentedText(
            "rep_range.overload_card.description".localized(
                sortedSets.count,
                exercise.targetRepMax ?? 0,
                exercise.targetRepMin ?? 0,
                exercise.targetRepMax ?? 0
            ),
            accent: .orange
        ))
        .font(.system(size: 13.5, weight: .medium))
        .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.9))
        .padding(.top, 12)
    }

    private var setRecap: some View {
        HStack(spacing: 7) {
            ForEach(Array(sortedSets.enumerated()), id: \.element.id) { index, set in
                VStack(spacing: 4) {
                    Text("routine_exercise_detail.set_number".localized(index + 1))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text("\(set.actualReps)/\(exercise.targetRepMax ?? 0)")
                        .font(.system(size: 11, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(DesignSystem.Colors.textOnTint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color.orange.opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(DesignSystem.Colors.divider, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
        .padding(.top, 12)
    }

    private var increaseButton: some View {
        Button {
            HapticManager.shared.medium()
            onIncrease()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                Text((isAssistance ? "exercise.reduce_assistance" : "rep_range.increase_weight").localized)
                    .font(.system(size: 15.5, weight: .bold))
                Text(formattedWeight(actionableCurrentWeight))
                    .font(.system(size: 15.5, weight: .semibold))
                    .strikethrough()
                    .opacity(0.55)
            }
            .foregroundStyle(DesignSystem.Colors.textOnTint)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.orange, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 13)
    }

    /// History surface: the routine/exercise this session came from was edited
    /// or deleted, so there is no live template to bump. Clear, non-actionable.
    private var unavailableNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
            Text("rep_range.overload_card.routine_unavailable".localized)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(DesignSystem.Colors.textSecondary)
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.top, 13)
    }

    // MARK: - Applied state

    private var confirmRow: some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textOnTint)
                .frame(width: 30, height: 30)
                .background(DesignSystem.Colors.tint, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                if confirmedWeight == nil {
                    Text(accentedText(
                        "rep_range.overload_card.all_sets_adjusted".localized,
                        accent: DesignSystem.Colors.tint
                    ))
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                    Text("rep_range.overload_card.next_workout_no_weight".localized(
                        sortedSets.count, exercise.targetRepMin ?? 0
                    ))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                } else {
                    Text(accentedText(
                        (isAssistance ? "rep_range.overload_card.reduced_to" : "rep_range.overload_card.increased_to")
                            .localized(formattedWeight(confirmedWeight ?? 0)),
                        accent: DesignSystem.Colors.tint
                    ))
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                    Text("rep_range.overload_card.next_workout".localized(
                        sortedSets.count,
                        exercise.targetRepMin ?? 0,
                        formattedWeight(confirmedWeight ?? 0)
                    ))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }

            Spacer(minLength: 8)

            if canUndo {
                Button {
                    HapticManager.shared.light()
                    onUndo()
                } label: {
                    Text("action.undo".localized)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.tint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 13)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DesignSystem.Colors.divider)
                .frame(height: 1)
        }
        .padding(.top, 13)
    }

    // MARK: - Helpers

    private var cardBackground: some View {
        ZStack {
            DesignSystem.Colors.card
            if !isApplied {
                LinearGradient(
                    stops: [
                        .init(color: Color.orange.opacity(0.15), location: 0),
                        .init(color: .clear, location: 0.62)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private func formattedWeight(_ weight: Double) -> String {
        String(format: "%g kg", weight)
    }

    /// Parses the localized string's **bold** markers and colors those runs
    /// with the accent (the design's orange/green emphasis inside sentences).
    private func accentedText(_ string: String, accent: Color) -> AttributedString {
        var attributed = (try? AttributedString(markdown: string)) ?? AttributedString(string)
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            attributed[run.range].foregroundColor = accent
        }
        return attributed
    }
}
