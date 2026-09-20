//
//  ConditioningProgramStoring.swift
//  GymStreak
//
//  The user's conditioning-program enrollment, readable and writable.
//  See docs/fight-conditioning.md.
//

import Foundation

/// `@MainActor` like `HeartRateProfileStoring`: the conformer is observable
/// main-actor state that the program screen and the Routines card bind to.
@MainActor
protocol ConditioningProgramStoring: AnyObject {

    /// `nil` when the user is not enrolled (never was, or left the program).
    var enrollment: ConditioningProgramEnrollment? { get set }

    /// The user closed the program card on the Routines tab. Device-local.
    var isRoutinesCardDismissed: Bool { get set }
}
