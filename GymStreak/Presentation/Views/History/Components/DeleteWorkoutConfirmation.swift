//
//  DeleteWorkoutConfirmation.swift
//  GymStreak
//
//  The single delete confirmation shared by every entry point into deleting a
//  recorded workout (the detail screen's ellipsis menu and the history card's
//  long-press context menu). Keeping it in one place is
//  what lets the choice copy stay identical wherever the user starts the
//  deletion.
//

import SwiftUI

/// Presents the destructive confirmation for deleting a recorded workout.
///
/// When the session has an Apple Health counterpart the user picks between two
/// destructive outcomes — GymStreak only, or GymStreak *and* Apple Health. When
/// it has none, the Apple Health option is not offered at all: there would be
/// nothing for it to remove.
///
/// This is an `.alert` rather than a `.confirmationDialog` on purpose. On iOS 26
/// a `confirmationDialog` anchors to the view its modifier is attached to, so
/// attaching one to a large ancestor (which both call sites are) makes it
/// mis-anchor as a floating popover — the same trap documented on
/// `PendingSyncBannerView`. An alert has no anchor and both call sites already
/// used one.
private struct DeleteWorkoutConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    /// Whether the workout being deleted has an Apple Health counterpart.
    let hasHealthKitWorkout: Bool
    /// Invoked on confirmation with whether Apple Health should be included.
    let onDelete: (_ alsoFromHealthKit: Bool) -> Void
    /// Invoked when the user backs out, so the caller can drop the pending workout.
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content.alert("workout.history.delete.title".localized, isPresented: $isPresented) {
            if hasHealthKitWorkout {
                Button("workout.history.delete.gymstreak_only".localized, role: .destructive) {
                    onDelete(false)
                }
                Button("workout.history.delete.with_health".localized, role: .destructive) {
                    onDelete(true)
                }
            } else {
                Button("action.delete".localized, role: .destructive) {
                    onDelete(false)
                }
            }
            Button("action.cancel".localized, role: .cancel) { onCancel() }
        } message: {
            Text(hasHealthKitWorkout
                 ? "workout.history.delete.message_health".localized
                 : "workout.history.delete.message".localized)
        }
    }
}

extension View {
    /// Attaches the shared delete-workout confirmation.
    func deleteWorkoutConfirmation(
        isPresented: Binding<Bool>,
        hasHealthKitWorkout: Bool,
        onDelete: @escaping (_ alsoFromHealthKit: Bool) -> Void,
        onCancel: @escaping () -> Void = {}
    ) -> some View {
        modifier(DeleteWorkoutConfirmation(
            isPresented: isPresented,
            hasHealthKitWorkout: hasHealthKitWorkout,
            onDelete: onDelete,
            onCancel: onCancel
        ))
    }
}
