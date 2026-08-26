//
//  RoutineCardModel.swift
//  GymStreak
//

import Foundation

/// Everything one routine card on the Routinen tab renders, precomputed once.
///
/// This exists for the same reason `HistorySnapshot` does: the card used to derive all of it
/// *inside* `body`. Three `RoutineMetricsService` calls, a `sorted().prefix(3)` and a
/// `WorkoutPlanningService.nextDue` ran from computed properties `body` reads, so every render
/// walked `routineExercises → sets` four times per card and faulted `exercise` per preview
/// avatar — an N+1 that is unbounded for Pro users, whose routine count is uncapped.
/// See docs/history-performance.md.
///
/// Deliberately localization-free (dates and numbers, no formatted strings), so the values are
/// produced by `RoutineMetricsService` in `Domain/` and the view owns the wording — the same
/// split `RoutineMetricsService.setSchemeSummary` already uses.
struct RoutineCardModel: Identifiable, Hashable, Sendable {
    /// The routine's own id, copied verbatim — never regenerated on rebuild, so `ForEach`
    /// identity, scroll position and row state survive a re-fetch (main-thread rule 8).
    let id: UUID
    let name: String
    let exerciseCount: Int
    let setCount: Int
    let estimatedDurationMinutes: Int
    /// Primary muscle groups in exercise order, already limited to what the card shows.
    let muscleGroups: [String]
    /// The first exercises' avatars, already limited to what the card shows.
    let avatars: [RoutineCardAvatar]
    /// Next due date when the routine is planned, nil otherwise. Fixed at build time rather
    /// than recomputed per render — the list rebuilds on `onAppear` and on every mutation,
    /// which is what keeps a day rollover from showing a stale "today".
    let nextDue: Date?
    /// Most recent completed session, nil when never trained.
    let lastPerformed: Date?
}

/// One overlapping avatar tile on a routine card. Carries the values
/// `ExerciseAvatarView` needs so the row never faults `RoutineExercise.exercise`.
struct RoutineCardAvatar: Identifiable, Hashable, Sendable {
    let id: UUID
    let muscleGroups: [String]
    let equipmentType: EquipmentType
}
