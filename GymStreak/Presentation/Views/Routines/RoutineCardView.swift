//
//  RoutineCardView.swift
//  GymStreak
//
//  Routine card of the redesigned Routinen tab. Two variants:
//  - hero ("Als Nächstes"): tinted gradient, full-width start button
//  - regular: compact card with inline play button
//

import SwiftUI

/// Takes a `RoutineCardModel`, never a `Routine`.
///
/// It previously called `RoutineMetricsService.primaryMuscleGroups`, `.totalSets` and
/// `.estimatedDurationMinutes`, plus a `sorted().prefix(3)` over `routineExercisesList` and
/// `WorkoutPlanningService.nextDue`, from computed properties `body` reads — four walks of the
/// `routineExercises → sets` graph per card per render, each faulting SwiftData relationships,
/// re-paid every time a lazy row is rebuilt. Being `Equatable` over plain values also lets
/// SwiftUI skip unchanged cards outright. See docs/history-performance.md.
struct RoutineCardView: View, Equatable {
    let card: RoutineCardModel
    var isHero: Bool = false
    let onStart: () -> Void

    /// The rendered output depends only on the model and the variant; `onStart` captures
    /// nothing that can change what is drawn (it forwards `card.id` to the ViewModel), so it
    /// is deliberately excluded rather than making the whole card non-`Equatable`.
    static func == (lhs: RoutineCardView, rhs: RoutineCardView) -> Bool {
        lhs.card == rhs.card && lhs.isHero == rhs.isHero
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
                ForEach(Array(card.avatars.enumerated()), id: \.element.id) { index, avatar in
                    ExerciseAvatarView(
                        muscleGroups: avatar.muscleGroups,
                        equipmentType: avatar.equipmentType,
                        size: isHero ? 44 : 38,
                        radius: isHero ? 14 : 12
                    )
                    .background(DesignSystem.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: isHero ? 14 : 12, style: .continuous))
                    .zIndex(Double(card.avatars.count - index))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(card.name)
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

    /// Muscle chips on the leading side, schedule status trailing.
    ///
    /// `scheduleStatus` gets `layoutPriority(1)` + `fixedSize`, so the HStack hands
    /// it its full intrinsic width first: long localizations ("Überfällig",
    /// "Heute fällig", weekday names) always render on one line instead of being
    /// squeezed and broken mid-word. `FlowLayout` then takes the whole remaining
    /// width — it is greedy, which is also what pins the badge to the trailing edge
    /// without a `Spacer` — and wraps chips that do not fit onto a second line.
    /// A `Spacer` here would be wrong: the HStack would split the leftover width
    /// between it and the chips, making them wrap earlier than necessary.
    private var metaRow: some View {
        HStack(alignment: .top, spacing: 10) {
            FlowLayout(spacing: 6) {
                ForEach(card.muscleGroups, id: \.self) { muscle in
                    MuscleChipView(muscleGroup: muscle, small: true)
                }
            }
            scheduleStatus
                .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var scheduleStatus: some View {
        if let dueLabel = ScheduleFormatter.nextDueLabel(for: card.nextDue) {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 9, weight: .bold))
                Text(dueLabel)
                    .font(.system(size: 11, weight: .bold))
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(DesignSystem.Colors.tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(DesignSystem.Colors.tint.opacity(0.14))
            .clipShape(Capsule())
        } else {
            Text(TimeFormatting.lastTrainedLabel(for: card.lastPerformed))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.4))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var metaText: String {
        String(
            format: "routines.card_meta".localized,
            card.exerciseCount, card.setCount, card.estimatedDurationMinutes
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
