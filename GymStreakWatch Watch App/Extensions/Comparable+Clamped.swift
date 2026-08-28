//
//  Comparable+Clamped.swift
//  GymStreakWatch Watch App
//
//  Extracted from `ValueStepperView.swift` when that view and its only caller
//  (`InlineSetEditorView`) were deleted — both were unreachable dead code that
//  carried a third, contradictory weight convention ("lbs", step 5) into a tree
//  where every live surface reads the synced unit. See
//  docs/weight-unit-preference.md and docs/watch-localization.md.
//

import Foundation

extension Comparable {
    /// Clamps a value to the given range.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
