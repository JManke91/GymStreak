//
//  ConditioningRecordDetailView.swift
//  GymStreak
//
//  One recorded conditioning session, pushed from the History list. Everything
//  shown is read off the record itself — it is denormalized precisely so this
//  screen never has to ask the library what the session used to be.
//  See docs/fight-conditioning.md.
//

import SwiftUI

struct ConditioningRecordDetailView: View {
    /// A main-context `@Model`, resolved by id before the push. Safe here in a way it is
    /// not in a row: this is one object on one screen, not an N+1 per scrolled cell.
    let record: ConditioningRecord
    let viewModel: ConditioningHistoryViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false
    /// The screen blanks itself before the delete awaits, so nothing reads the tombstone.
    @State private var isBeingDeleted = false

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()
            if !isBeingDeleted {
                content
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    HapticManager.shared.light()
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("action.delete".localized)
            }
        }
        .deleteWorkoutConfirmation(
            isPresented: $showingDeleteConfirmation,
            // Short-circuited: the modifier sits outside the `isBeingDeleted` guard, so
            // without it the alert would still read the tombstoned record.
            hasHealthKitWorkout: !isBeingDeleted && record.healthKitWorkoutId != nil,
            onDelete: delete
        )
    }

    private var title: String {
        ConditioningCopy.recordedTitle(sessionType: record.sessionType, snapshot: record.titleSnapshot)
    }

    private func delete(alsoFromHealthKit: Bool) {
        isBeingDeleted = true
        dismiss()
        HapticManager.shared.success()
        Task {
            await viewModel.delete(record, alsoFromHealthKit: alsoFromHealthKit)
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                headline
                structure
                if record.healthKitWorkoutId != nil {
                    Label("conditioning.history.detail.in_health".localized, systemImage: "heart.fill")
                        .font(.onyxFootnote)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.xxl)
        }
    }

    private var headline: some View {
        OnyxCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text(Self.dateFormatter.string(from: record.startTime))
                    .font(.onyxSubheadline)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Text(ConditioningCopy.clock(record.duration))
                    .font(.onyxNumberLarge)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                if let modality = record.modality {
                    Label(
                        ConditioningCopy.modality(modality),
                        systemImage: ConditioningCopy.modalitySymbol(modality)
                    )
                    .font(.onyxFootnote)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                if record.endedEarly {
                    Label("conditioning.history.ended_early".localized, systemImage: "flag.checkered")
                        .font(.onyxFootnote)
                        .foregroundStyle(DesignSystem.Colors.warning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var structure: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("conditioning.preview.structure".localized.uppercased())
                .font(.onyxMonoLabel)
                .kerning(0.7)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            OnyxCard {
                // Bounded, constant content (at most four rows) — a plain stack is fine.
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    if let energySystem = record.energySystem {
                        row(
                            "conditioning.history.detail.energy".localized,
                            ConditioningCopy.energySystem(energySystem)
                        )
                    }
                    if !record.isSteadyState {
                        row(
                            "conditioning.history.detail.rounds".localized,
                            "conditioning.history.rounds".localized(
                                record.roundsCompleted, record.roundsPlanned
                            )
                        )
                        row(
                            "conditioning.history.detail.interval".localized,
                            "conditioning.preview.work_rest".localized(
                                ConditioningCopy.duration(record.workInterval),
                                ConditioningCopy.duration(record.restInterval)
                            )
                        )
                        if record.setsPlanned > 0 {
                            row(
                                "conditioning.preview.sets_label".localized,
                                "\(record.setsPlanned)"
                            )
                        }
                    }
                    if let effort = record.effort {
                        row(
                            "conditioning.history.detail.effort".localized,
                            ConditioningCopy.effort(effort)
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.onyxSubheadline)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Spacer(minLength: DesignSystem.Spacing.md)
            Text(value)
                .font(.onyxSubheadline)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
    }

    /// Hoisted out of `body`: allocating a `DateFormatter` per render is the rule this
    /// screen shares with the list (docs/history-performance.md).
    @MainActor
    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateStyle = .full
        fmt.timeStyle = .short
        return fmt
    }()
}

/// Navigation value for a conditioning record.
///
/// A bare `UUID` cannot be used: `HistoryView`'s stack already claims `UUID.self` for workout
/// sessions, and a conditioning id pushed there would resolve to "no such workout" and render
/// nothing. Same precedent as `PeriodRecapDestination`.
struct ConditioningRecordDestination: Hashable {
    let id: UUID
}
