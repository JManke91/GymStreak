//
//  WorkoutScreenStyle.swift
//  GymStreakWatch Watch App
//
//  Size metrics and shared button styles for the active-workout set editor.
//  Values follow the 49/45/41 mm columns of the workout screen design
//  (design/gym-streak/project/SwiftUI Handoff.md); smaller cases use the 41 mm tier.
//

import SwiftUI
import WatchKit

struct WorkoutScreenMetrics {
    let completeButtonHeight: CGFloat
    /// Size of the icon-only checkmark glyph on the Complete button.
    let completeIconSize: CGFloat
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

    static let current: WorkoutScreenMetrics = {
        let width = WKInterfaceDevice.current().screenBounds.width
        if width >= 204 { return large }
        if width >= 192 { return mid }
        return small
    }()

    private static let large = WorkoutScreenMetrics(
        completeButtonHeight: 35, completeIconSize: 17, segmentsWidth: 62,
        chevronDiameter: 27, chevronIconSize: 10, fusedRowGap: 5.5, fusedRowHPad: 14,
        stepperDiameter: 32, stepperIconSize: 12,
        valueCardHeight: 40, valueCardRadius: 8, valueFontSize: 15.5, valueUnitSize: 9,
        topNameSize: 15, topPercentSize: 11, topSegmentHeight: 3.5, topZoneSpacing: 6,
        elapsedFontSize: 16, elapsedIconSize: 12
    )

    private static let mid = WorkoutScreenMetrics(
        completeButtonHeight: 33, completeIconSize: 15.5, segmentsWidth: 58,
        chevronDiameter: 26, chevronIconSize: 10, fusedRowGap: 5.5, fusedRowHPad: 15.5,
        stepperDiameter: 31.5, stepperIconSize: 11.5,
        valueCardHeight: 40, valueCardRadius: 8, valueFontSize: 14.5, valueUnitSize: 8.5,
        topNameSize: 14, topPercentSize: 10.5, topSegmentHeight: 3.5, topZoneSpacing: 5.5,
        elapsedFontSize: 15, elapsedIconSize: 11.5
    )

    private static let small = WorkoutScreenMetrics(
        completeButtonHeight: 30, completeIconSize: 13.5, segmentsWidth: 52,
        chevronDiameter: 23, chevronIconSize: 8.5, fusedRowGap: 4.5, fusedRowHPad: 13,
        stepperDiameter: 29, stepperIconSize: 11,
        valueCardHeight: 35, valueCardRadius: 7, valueFontSize: 13.5, valueUnitSize: 8,
        topNameSize: 12, topPercentSize: 9.5, topSegmentHeight: 3, topZoneSpacing: 4.5,
        elapsedFontSize: 13.5, elapsedIconSize: 10
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

/// Round dark chevron button with pressed highlight; keeps a 44 pt tall tap area
/// around the smaller visual circle.
struct ChevronCircleStyle: ButtonStyle {
    let diameter: CGFloat

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
            .frame(height: OnyxWatch.Dimensions.minTouchTarget)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
