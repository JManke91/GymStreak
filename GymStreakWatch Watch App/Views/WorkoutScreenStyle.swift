//
//  WorkoutScreenStyle.swift
//  GymStreakWatch Watch App
//
//  Size metrics and shared button styles for the active-workout set editor and
//  the large rest timer.
//
//  The design (design/gym-streak/project/SwiftUI Handoff.md, "Watch Final
//  Design.html") specifies THREE columns — 49 / 45 / 41 mm. 41 mm is the
//  design's smallest frame, but it is NOT the smallest shipping watch:
//
//      case    logical pt      tier
//      38 mm   136 × 170       xSmall
//      40 mm   162 × 197       xSmall   ← below every design column
//      41 mm   176 × 215       small    ← the design's smallest column
//      42 mm   187 × 223       small
//      44 mm   184 × 224       small
//      45 mm   198 × 242       mid
//      46 mm   208 × 248       large
//      49 mm   205 × 251       large    (Ultra 3: 211 × 256)
//
//  A 40 mm watch is 14 pt narrower AND 18 pt shorter than the 41 mm frame the
//  design was drawn on, so the 41 mm column does not fit it — the bottom action
//  row fell off the screen. `xSmall` is the extrapolated fourth column.
//
//  The tier is picked from the TIGHTER of the two axes, not from the width
//  alone: 44 mm is as narrow as 41 mm but as tall as 45 mm, and the failure
//  mode of these screens is vertical overflow, so a width-only key measures the
//  wrong thing. `min(widthTier, heightTier)` keeps a case in the largest column
//  that fits it on *both* axes.
//

import SwiftUI
import WatchKit

/// Keep every field a `CGFloat`. Views hold this as a stored `private let`, so
/// it is part of their value for SwiftUI's structural comparison — all-POD
/// keeps that comparison cheap and correct. A `String`, array or closure field
/// would silently cost those views their equality-based invalidation skipping.
struct WorkoutScreenMetrics {
    let completeButtonHeight: CGFloat
    /// Size of the icon-only checkmark glyph on the Complete button.
    let completeIconSize: CGFloat
    /// Height of the footer row's tap area. This — not
    /// `completeButtonHeight` — is what the row costs in the vertical budget,
    /// so it has to be tiered. Design handoff §6 sets the floor at 24 pt on
    /// watchOS; the smaller tiers keep the visual capsule plus a few points of
    /// slop rather than the iOS-sized 44 pt block.
    let actionRowHeight: CGFloat
    let segmentsWidth: CGFloat
    let chevronDiameter: CGFloat
    let chevronIconSize: CGFloat
    let fusedRowGap: CGFloat
    /// Extra horizontal inset on the footer (fused) row so the round chevrons
    /// stay inside the display's curved corners (design `--pad-chrome`).
    let fusedRowHPad: CGFloat
    let stepperDiameter: CGFloat
    let stepperIconSize: CGFloat
    let valueCardHeight: CGFloat
    let valueCardRadius: CGFloat
    let valueCardGap: CGFloat
    let valueFontSize: CGFloat
    let valueUnitSize: CGFloat
    /// Top-zone (exercise name + workout progress) tiers, design §4.
    let topNameSize: CGFloat
    let topPercentSize: CGFloat
    let topSegmentHeight: CGFloat
    let topZoneSpacing: CGFloat
    /// Elapsed-time label in the routine row (bold text + stopwatch glyph) —
    /// moved out of the top toolbar so it no longer collides with the clock.
    let elapsedFontSize: CGFloat
    let elapsedIconSize: CGFloat
    /// Floors for the set editor's two flexible gaps. They are floors, not
    /// fixed heights — on the larger cases the leftover space still flows into
    /// them; on the small ones they must be small enough that the column fits
    /// at all, because a `Spacer(minLength:)` the layout cannot honour pushes
    /// the footer past the bottom edge instead of compressing.
    let editorTopGap: CGFloat
    let editorBottomGap: CGFloat
    /// Gap below the stepper/metrics cluster.
    let clusterBottomGap: CGFloat
    /// Compact HR/kCal readout (`WorkoutMetricsView(size: .small)`), used by
    /// both the set editor and the rest timer's top row. It is the tallest
    /// element of the editor's middle band, so it has to shrink with the case.
    let metricValueSize: CGFloat
    let metricUnitSize: CGFloat
    let metricIconSize: CGFloat
    let metricRowSpacing: CGFloat
    /// Large rest timer (`RestTimerLargeView`).
    let restCountdownSize: CGFloat
    let restStackSpacing: CGFloat
    let restCenterSpacing: CGFloat
    let restVerticalPadding: CGFloat
    let restMinimizeIconSize: CGFloat

    /// Ordered smallest → largest so the two axis rankings can be compared.
    private enum Tier: Int, Comparable {
        case xSmall, small, mid, large

        static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    static let current: WorkoutScreenMetrics = {
        forScreen(WKInterfaceDevice.current().screenBounds.size)
    }()

    /// Split out of `current` so a preview can render a tier other than the
    /// host device's. There is no watch unit-test target, so the thresholds
    /// themselves are verified by inspection against the table above plus the
    /// `testControlsStayOnScreenOnSmallestCase` UI test — which only proves the
    /// case it is run on. Note the 46 mm case clears the `large` height
    /// threshold by 2 pt (248 vs. 246); do not raise it.
    static func forScreen(_ size: CGSize) -> WorkoutScreenMetrics {
        let widthTier: Tier = {
            if size.width >= 204 { return .large }   // 46 / 49 mm
            if size.width >= 192 { return .mid }     // 45 mm
            if size.width >= 170 { return .small }   // 41 / 42 / 44 mm
            return .xSmall                            // 38 / 40 mm
        }()

        let heightTier: Tier = {
            if size.height >= 246 { return .large }  // 46 / 49 mm
            if size.height >= 230 { return .mid }    // 45 mm
            if size.height >= 205 { return .small }  // 41 / 42 / 44 mm
            return .xSmall                            // 38 / 40 mm
        }()

        switch min(widthTier, heightTier) {
        case .large: return large
        case .mid: return mid
        case .small: return small
        case .xSmall: return xSmall
        }
    }

    private static let large = WorkoutScreenMetrics(
        completeButtonHeight: 35, completeIconSize: 17, actionRowHeight: 44, segmentsWidth: 62,
        chevronDiameter: 27, chevronIconSize: 10, fusedRowGap: 5.5, fusedRowHPad: 14,
        stepperDiameter: 32, stepperIconSize: 12,
        valueCardHeight: 40, valueCardRadius: 8, valueCardGap: 6.5,
        valueFontSize: 15.5, valueUnitSize: 9,
        topNameSize: 15, topPercentSize: 11, topSegmentHeight: 3.5, topZoneSpacing: 6,
        elapsedFontSize: 16, elapsedIconSize: 12,
        editorTopGap: 4, editorBottomGap: 8, clusterBottomGap: 7,
        metricValueSize: 14, metricUnitSize: 11, metricIconSize: 10, metricRowSpacing: 5,
        restCountdownSize: 44, restStackSpacing: 6, restCenterSpacing: 6,
        restVerticalPadding: 12, restMinimizeIconSize: 24
    )

    private static let mid = WorkoutScreenMetrics(
        completeButtonHeight: 33, completeIconSize: 15.5, actionRowHeight: 44, segmentsWidth: 58,
        chevronDiameter: 26, chevronIconSize: 10, fusedRowGap: 5.5, fusedRowHPad: 15.5,
        stepperDiameter: 31.5, stepperIconSize: 11.5,
        valueCardHeight: 40, valueCardRadius: 8, valueCardGap: 6.5,
        valueFontSize: 14.5, valueUnitSize: 8.5,
        topNameSize: 14, topPercentSize: 10.5, topSegmentHeight: 3.5, topZoneSpacing: 5.5,
        elapsedFontSize: 15, elapsedIconSize: 11.5,
        editorTopGap: 4, editorBottomGap: 8, clusterBottomGap: 7,
        metricValueSize: 14, metricUnitSize: 11, metricIconSize: 10, metricRowSpacing: 5,
        restCountdownSize: 44, restStackSpacing: 6, restCenterSpacing: 6,
        restVerticalPadding: 12, restMinimizeIconSize: 24
    )

    /// The design's 41 mm column, unchanged — it also covers 42 mm and 44 mm,
    /// both of which have more height than the 41 mm it was drawn for.
    private static let small = WorkoutScreenMetrics(
        completeButtonHeight: 30, completeIconSize: 13.5, actionRowHeight: 44, segmentsWidth: 52,
        chevronDiameter: 23, chevronIconSize: 8.5, fusedRowGap: 4.5, fusedRowHPad: 13,
        stepperDiameter: 29, stepperIconSize: 11,
        valueCardHeight: 35, valueCardRadius: 7, valueCardGap: 6.5,
        valueFontSize: 13.5, valueUnitSize: 8,
        topNameSize: 12, topPercentSize: 9.5, topSegmentHeight: 3, topZoneSpacing: 4.5,
        elapsedFontSize: 13.5, elapsedIconSize: 10,
        editorTopGap: 4, editorBottomGap: 8, clusterBottomGap: 7,
        metricValueSize: 14, metricUnitSize: 11, metricIconSize: 10, metricRowSpacing: 5,
        restCountdownSize: 42, restStackSpacing: 6, restCenterSpacing: 6,
        restVerticalPadding: 10, restMinimizeIconSize: 22
    )

    /// 40 mm (162 × 197) and 38 mm — below the design's smallest frame. The
    /// 41 mm column extrapolated down by roughly the 197/215 height ratio, with
    /// the three elements that do not scale with a font size (the footer row,
    /// the compact metrics readout and the rest timer's fixed paddings) cut
    /// harder, because those are where the missing 18 pt actually went.
    private static let xSmall = WorkoutScreenMetrics(
        completeButtonHeight: 28, completeIconSize: 12.5, actionRowHeight: 34, segmentsWidth: 46,
        chevronDiameter: 21, chevronIconSize: 8, fusedRowGap: 4, fusedRowHPad: 10,
        stepperDiameter: 26, stepperIconSize: 10,
        valueCardHeight: 31, valueCardRadius: 6, valueCardGap: 5,
        valueFontSize: 12.5, valueUnitSize: 7.5,
        topNameSize: 11, topPercentSize: 9, topSegmentHeight: 2.5, topZoneSpacing: 3.5,
        elapsedFontSize: 12.5, elapsedIconSize: 9,
        editorTopGap: 2, editorBottomGap: 4, clusterBottomGap: 4,
        metricValueSize: 12, metricUnitSize: 9, metricIconSize: 8, metricRowSpacing: 2,
        restCountdownSize: 34, restStackSpacing: 3, restCenterSpacing: 2,
        restVerticalPadding: 4, restMinimizeIconSize: 18
    )
}

/// Press feedback for capsule/circle controls: scale down with a soft spring.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Round dark chevron button with pressed highlight. The tap area is the full
/// footer row height (`WorkoutScreenMetrics.actionRowHeight`) around the smaller
/// visual circle — tiered, so it does not cost a 40 mm screen the same 44 pt it
/// costs an Ultra.
struct ChevronCircleStyle: ButtonStyle {
    /// Minimum tap side, design handoff §6 ("Mindest-Hit-Targets ≥ 24 pt").
    private static let minHitSide: CGFloat = 24

    let diameter: CGFloat
    let rowHeight: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: diameter, height: diameter)
            .background(
                Circle().fill(
                    configuration.isPressed
                        ? OnyxWatch.Colors.strokeSubtle
                        : OnyxWatch.Colors.card
                )
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            // Both axes: the visual circle is allowed down to 21 pt on the
            // smallest case, but the hit rect must not follow it below the
            // 24 pt watchOS floor of handoff §6 — and `frame(height:)` alone
            // leaves the tap area exactly `diameter` wide.
            .frame(minWidth: Self.minHitSide, minHeight: Self.minHitSide)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
