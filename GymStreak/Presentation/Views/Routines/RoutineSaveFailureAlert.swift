//
//  RoutineSaveFailureAlert.swift
//  GymStreak
//
//  The alert that replaces the swallowed `print` in `RoutinesViewModel.save()`.
//  See docs/workout-planning.md → "Making the next failure of this kind visible".
//

import SwiftUI

/// Presents `RoutinesViewModel.didFailToSave` as an alert.
///
/// Applied **once**, to the `NavigationStack` rather than to its root content —
/// an alert bound to the content underneath is not reliably presented once
/// `RoutineDetailView` is pushed over it, and the pushed detail view is where
/// most editing happens.
///
/// One application is enough even though saves also fire from surfaces with
/// their own presentation context (`CreateRoutineView` as a `fullScreenCover`,
/// `SchedulePlanningSheet` and the other detail sheets): every one of those call
/// sites dismisses immediately after saving, and `didFailToSave` outlives the
/// dismissal, so the failure surfaces on the stack alert as the sheet closes.
/// A second copy bound to the same flag is the thing to avoid — SwiftUI can
/// write `false` back while tearing that surface down, which would swallow the
/// alert rather than duplicate it.
private struct RoutineSaveFailureAlert: ViewModifier {
    @ObservedObject var viewModel: RoutinesViewModel

    func body(content: Content) -> some View {
        content.alert(
            "routine.save_failed.title".localized,
            isPresented: $viewModel.didFailToSave
        ) {
            Button("action.dismiss".localized, role: .cancel) {}
        } message: {
            Text("routine.save_failed.message".localized)
        }
    }
}

extension View {
    /// Tells the user when a routine change never reached the store — on screen
    /// it looks identical to one that did.
    func routineSaveFailureAlert(_ viewModel: RoutinesViewModel) -> some View {
        modifier(RoutineSaveFailureAlert(viewModel: viewModel))
    }
}
