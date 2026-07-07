//
//  RoutineCardView.swift
//  GymStreak
//
//  Routine card of the redesigned Routinen tab. Two variants:
//  - hero ("Als Nächstes"): tinted gradient, full-width start button
//  - regular: compact card with inline play button
//

import SwiftUI

struct RoutineCardView: View {
    let routine: Routine
    let lastPerformed: Date?
    var isHero: Bool = false
    let onStart: () -> Void

    private var muscles: [String] { RoutineMetricsService.primaryMuscleGroups(for: routine) }
    private var setCount: Int { RoutineMetricsService.totalSets(for: routine) }
    private var duration: Int { RoutineMetricsService.estimatedDurationMinutes(for: routine) }

    /// Next due date when the routine is planned; nil otherwise.
    private var nextDue: Date? {
        guard let schedule = routine.schedule, schedule.isActive else { return nil }
        return WorkoutPlanningService.nextDue(for: schedule, lastCompleted: lastPerformed)
    }
    private var previewExercises: [RoutineExercise] {
        Array(routine.routineExercisesList.sorted(by: { $0.order < $1.order }).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isHero {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("routines.up_next".localized.uppercased())
                        .font(.system(size: 10.5, weight: .bold))
                        .kerning(0.8)
                }
                .foregroundStyle(DesignSystem.Colors.tint)
            }

            titleRow

            metaRow

            if isHero {
                Button(action: onStart) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("routine.start_workout".localized)
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(DesignSystem.Colors.textOnTint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(DesignSystem.Colors.tint)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, isHero ? 18 : 16)
        .padding(.top, isHero ? 18 : 16)
        .padding(.bottom, isHero ? 16 : 14)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isHero ? DesignSystem.Colors.tint.opacity(0.22) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var titleRow: some View {
        HStack(spacing: 12) {
            // Overlapping avatars of the first exercises
            HStack(spacing: -10) {
                ForEach(Array(previewExercises.enumerated()), id: \.element.id) { index, entry in
                    ExerciseAvatarView(
                        muscleGroups: entry.exercise?.muscleGroups ?? ["General"],
                        equipmentType: entry.exercise?.equipmentType ?? .dumbbell,
                        size: isHero ? 44 : 38,
                        radius: isHero ? 14 : 12
                    )
                    .background(DesignSystem.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: isHero ? 14 : 12, style: .continuous))
                    .zIndex(Double(previewExercises.count - index))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.name)
                    .font(.system(size: isHero ? 19 : 16.5, weight: .bold, design: .rounded))
                    .kerning(-0.4)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(metaText)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.5))
            }

            Spacer(minLength: 0)

            if !isHero {
                Button(action: onStart) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.tint)
                        .frame(width: 40, height: 40)
                        .background(DesignSystem.Colors.tint.opacity(0.15))
                        .overlay(
                            Circle().stroke(DesignSystem.Colors.tint.opacity(0.25), lineWidth: 1)
                        )
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("routine.start_workout".localized)
            }
        }
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            ForEach(muscles.prefix(3), id: \.self) { muscle in
                MuscleChipView(muscleGroup: muscle, small: true)
            }
            Spacer(minLength: 8)
            if let dueLabel = ScheduleFormatter.nextDueLabel(for: nextDue) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 9, weight: .bold))
                    Text(dueLabel)
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(DesignSystem.Colors.tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DesignSystem.Colors.tint.opacity(0.14))
                .clipShape(Capsule())
            } else {
                Text(TimeFormatting.lastTrainedLabel(for: lastPerformed))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
    }

    private var metaText: String {
        String(
            format: "routines.card_meta".localized,
            routine.routineExercisesList.count, setCount, duration
        )
    }

    @ViewBuilder
    private var cardBackground: some View {
        if isHero {
            LinearGradient(
                colors: [
                    DesignSystem.Colors.tint.opacity(0.10),
                    DesignSystem.Colors.tint.opacity(0.03),
                    Color.white.opacity(0.02),
                ],
                startPoint: .top, endPoint: .bottom
            )
        } else {
            Color.white.opacity(0.035)
        }
    }
}
