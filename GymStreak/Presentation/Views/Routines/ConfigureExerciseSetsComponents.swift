//
//  ConfigureExerciseSetsComponents.swift
//  GymStreak
//
//  The presentational chrome of ConfigureExerciseSetsView, split out to keep
//  that screen near the file-size guideline: the live summary strip, the
//  no-sets-yet state with its quick schemes, and the section header/card
//  wrappers its five sections share. Everything here is stateless — the screen
//  owns the configuration and passes values in.
//

import SwiftUI

/// One of the ready-made set schemes offered on the empty state.
struct QuickSetScheme: Identifiable {
    let sets: Int
    let reps: Int

    var id: String { "\(sets)x\(reps)" }
}

/// Sets · volume · rest at a glance, so the configuration reads back without
/// re-scanning the rows. The reduce runs over the passed-in set array only — a
/// handful of value reads, no relationship traversal.
///
/// The volume is summed in canonical kilograms and converted once for display,
/// like every other weight on the screen.
struct ConfigureSummaryStrip: View {
    let sets: [ExerciseSet]
    let restTime: TimeInterval

    @Environment(\.weightUnit) private var weightUnit

    var body: some View {
        let volume = sets.reduce(0.0) { $0 + Double($1.reps) * $1.weight }
        return HStack(spacing: 0) {
            column(
                value: "\(sets.count)",
                label: "routine.section.sets".localized
            )
            divider
            column(
                value: volume > 0 ? WeightFormatting.label(volume, in: weightUnit) : "—",
                label: "configure_exercise.summary.volume".localized
            )
            divider
            column(
                value: restTime > 0 ? TimeFormatting.formatRestTime(restTime) : "rest_timer.off".localized,
                label: "rest_timer.rest_short".localized
            )
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 4)
        .background(DesignSystem.Colors.tint.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DesignSystem.Colors.tint.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func column(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .kerning(0.7)
                .foregroundStyle(Color.white.opacity(0.4))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(DesignSystem.Colors.tint.opacity(0.16))
            .frame(width: 1, height: 30)
    }
}

/// The "no sets yet" state: the fastest ways out of it are a quick scheme or a
/// single set, so those are the only two things offered.
struct ConfigureEmptySetsState: View {
    let schemes: [QuickSetScheme]
    let onApplyScheme: (QuickSetScheme) -> Void
    let onAddSingleSet: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("configure_exercise.empty.hint".localized)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                ForEach(schemes) { scheme in
                    Button {
                        HapticManager.shared.light()
                        withAnimation(DesignSystem.Animation.spring) {
                            onApplyScheme(scheme)
                        }
                    } label: {
                        Text("configure_exercise.quick_scheme".localized(scheme.sets, scheme.reps))
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(DesignSystem.Colors.tint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(DesignSystem.Colors.tint.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(DesignSystem.Colors.tint.opacity(0.28), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            DashedCreateButton(title: "configure_exercise.single_set".localized, compact: true) {
                withAnimation(DesignSystem.Animation.spring) { onAddSingleSet() }
            }
        }
    }
}

/// Uppercased section label with an optional trailing hint ("3 geplant",
/// "optional", the current rest time).
struct ConfigureSectionHeader: View {
    let title: String
    var hint: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(Color.white.opacity(0.42))

            if let hint {
                Text(hint)
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.3))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }
}

extension View {
    /// The neutral rounded card the sets and alternatives blocks sit on.
    func configureSectionCard() -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
