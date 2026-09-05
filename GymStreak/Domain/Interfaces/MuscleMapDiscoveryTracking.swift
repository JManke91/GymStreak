//
//  MuscleMapDiscoveryTracking.swift
//  GymStreak
//
//  Whether the user has been taught that the muscle map is tappable.
//  See docs/muscle-map.md, "Discoverability".
//

import Foundation

/// The durable "this user knows the muscle map responds to a tap" record, which
/// is what decides whether the card carries its one-line discovery hint.
///
/// **One flag for the whole capability, not one per screen.** Tapping a belly on
/// a recorded workout is the same gesture as tapping one on a routine, so
/// learning it on either surface must silence the hint on both — being taught
/// the same thing twice is worse than not being taught at all.
///
/// Device-local, and deliberately **not** the App Group suite: the watch app has
/// no muscle map and the widget has none either, so neither has any business
/// reading this. It is not mirrored to iCloud for the reason
/// `FounderCelebrationTracking` gives — presentation history, where a second
/// device re-teaching the gesture is the cheaper mistake than a device that
/// never teaches it.
///
/// `@MainActor` because the card reads it during layout, and it imports nothing
/// beyond Foundation on purpose: no `UserDefaults` key may appear in this
/// signature.
@MainActor
protocol MuscleMapDiscoveryTracking: AnyObject {

    /// Whether the gesture has been learned — either because the user used it or
    /// because the hint has been spent. Cheap by contract: it is asked while the
    /// card is being composed, so a conformer answers from memory rather than
    /// from I/O.
    var hasDiscoveredMuscleMap: Bool { get }

    /// Records that the user selected a region, by any route — a belly or a pill.
    /// The hint has done its job and is retired. Idempotent, one-way.
    func recordSelection()

    /// Counts one appearance of the hint that the user did not act on. After the
    /// third the hint retires itself unused, so a user who simply never taps is
    /// not shown explanatory chrome forever — the permanent-chrome outcome this
    /// design exists to avoid.
    ///
    /// Called **once per card appearance**, never from a view `body`.
    func recordShown()
}
