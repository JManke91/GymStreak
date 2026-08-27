//
//  WeightUnitEnvironment.swift
//  GymStreak
//
//  The user's weight unit as a SwiftUI Environment value.
//

import SwiftUI

extension EnvironmentValues {

    /// The unit weights are shown and entered in.
    ///
    /// Injected once at the app root from `WeightUnitPreference`, so the ~40
    /// call sites that render a weight can read it without every row
    /// initializer prop-drilling it. Views may read this directly; ViewModels
    /// take `WeightUnitPreferenceProviding` by init injection instead.
    ///
    /// The default is `.kilograms` — the canonical stored unit, so a view built
    /// outside the app root (a preview, a test host) shows raw stored values.
    @Entry var weightUnit: WeightUnit = .kilograms
}
