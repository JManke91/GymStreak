//
//  MatSessionDetailView.swift
//  GymStreak
//
//  One logged mat session, pushed from the History list.
//  See docs/fight-conditioning.md.
//

import SwiftUI

struct MatSessionDetailView: View {
    /// A main-context `@Model`, resolved by id before the push — one object on one
    /// screen, not an N+1 per scrolled cell.
    let session: MatSession
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
        .navigationTitle(isBeingDeleted ? "" : MatSessionCopy.sport(session.sport))
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
            hasHealthKitWorkout: !isBeingDeleted && session.healthKitWorkoutId != nil,
            onDelete: delete
        )
    }

    private func delete(alsoFromHealthKit: Bool) {
        isBeingDeleted = true
        dismiss()
        HapticManager.shared.success()
        Task {
            await viewModel.delete(session, alsoFromHealthKit: alsoFromHealthKit)
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                OnyxCard {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text(Self.dateFormatter.string(from: session.startTime))
                            .font(.onyxSubheadline)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        Text(ConditioningCopy.clock(session.duration))
                            .font(.onyxNumberLarge)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        Label(
                            MatSessionCopy.sport(session.sport),
                            systemImage: MatSessionCopy.sportSymbol(session.sport)
                        )
                        .font(.onyxFootnote)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        if let intensity = session.intensity {
                            Label(MatSessionCopy.intensity(intensity), systemImage: "flame")
                                .font(.onyxFootnote)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !session.note.isEmpty {
                    OnyxCard {
                        Text(session.note)
                            .font(.onyxSubheadline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if session.healthKitWorkoutId != nil {
                    Label("conditioning.history.detail.in_health".localized, systemImage: "heart.fill")
                        .font(.onyxFootnote)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.xxl)
        }
    }

    @MainActor
    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateStyle = .full
        fmt.timeStyle = .short
        return fmt
    }()
}

/// Navigation value for a mat session — a bare `UUID` is claimed by workout sessions
/// (same reason as `ConditioningRecordDestination`).
struct MatSessionDestination: Hashable {
    let id: UUID
}
