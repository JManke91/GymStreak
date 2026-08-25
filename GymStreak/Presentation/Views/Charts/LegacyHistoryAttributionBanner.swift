//
//  LegacyHistoryAttributionBanner.swift
//  GymStreak
//

import SwiftUI

/// Tells the user that older workouts matching this exercise's name are being left out of
/// every number on the screen, and offers the one action that can bring them back.
///
/// The omission itself is deliberate and stays: a workout recorded before
/// `WorkoutExercise.exerciseId` existed is matched by name, and with two live exercises
/// sharing that name there is no honest way to pick one. Guessing would rewrite what the
/// user trained; dropping only hides it. What was wrong was doing it in silence — the
/// reporter read their own chart as the app having lost their data.
///
/// Renders nothing but text and a button. The count, the period and every string arrive
/// pre-composed from `ExerciseProgressViewModel`, so no date is formatted and no history
/// is scanned while this body is evaluated.
struct LegacyHistoryAttributionBanner: View {
    let message: String
    let exerciseName: String
    let sessionCount: Int
    let isAttributing: Bool
    let onAttribute: () -> Void

    @State private var isConfirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.folder.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.warning)
                Text("progress.legacy.unattributed.title".localized)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
            }
            Text(message)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                HapticManager.shared.light()
                isConfirming = true
            } label: {
                HStack(spacing: 6) {
                    if isAttributing {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(DesignSystem.Colors.textOnTint)
                    }
                    Text("progress.legacy.unattributed.action".localized)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(DesignSystem.Colors.textOnTint)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(DesignSystem.Colors.tint)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isAttributing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(DesignSystem.Colors.warning.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DesignSystem.Colors.warning.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
        // Explicit confirmation, not undo: this writes to workout history, which is
        // otherwise append-only, and the dialog names both the number of workouts and the
        // exercise they would be assigned to. See `docs/progress-charts.md` for why the
        // action is one-way and what it deliberately does not touch.
        .confirmationDialog(
            "progress.legacy.unattributed.confirm.title".localized(sessionCount, exerciseName),
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("progress.legacy.unattributed.confirm.action".localized) {
                onAttribute()
            }
            Button("action.cancel".localized, role: .cancel) {}
        } message: {
            Text("progress.legacy.unattributed.confirm.message".localized)
        }
    }
}
