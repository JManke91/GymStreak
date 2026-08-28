//
//  WeightUnitEnvironment.swift
//  GymStreakWatch Watch App
//
//  The user's weight unit as a SwiftUI Environment value — the watch twin of
//  `GymStreak/Presentation/Helpers/WeightUnitEnvironment.swift`.
//

import SwiftUI

extension EnvironmentValues {

    /// The unit weights are shown and entered in.
    ///
    /// Injected once at the app root from `WatchWeightUnitStore`, which
    /// republishes whatever the iPhone last sent in the routine
    /// `applicationContext`. Views read this directly.
    ///
    /// The default is `.kilograms` — the canonical stored unit, and deliberately
    /// **not** `WeightUnit.default(for: .current)`: deriving the unit from the
    /// watch's own locale is the bug this feature removed, and it would let the
    /// two devices disagree about what a stored number means.
    @Entry var weightUnit: WeightUnit = .kilograms
}
