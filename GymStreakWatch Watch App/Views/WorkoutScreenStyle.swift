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
    /// Distance from the physical bottom screen edge to the bottom of the
    /// complete-button capsule (design: 19/17/15 pt for 49/45/41 mm).
    let footerBottomGap: CGFloat
    let completeButtonHeight: CGFloat
    let completeLabelSize: CGFloat
    let segmentsWidth: CGFloat
    let chevronDiameter: CGFloat
    let chevronIconSize: CGFloat
    let fusedRowGap: CGFloat
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

    static let current: WorkoutScreenMetrics = {
        let width = WKInterfaceDevice.current().screenBounds.width
        if width >= 204 { return large }
        if width >= 192 { return mid }
        return small
    }()

    private static let large = WorkoutScreenMetrics(
        footerBottomGap: 19,
        completeButtonHeight: 35, completeLabelSize: 11, segmentsWidth: 62,
        chevronDiameter: 27, chevronIconSize: 10, fusedRowGap: 5.5,
        stepperDiameter: 36, stepperIconSize: 13,
        valueCardHeight: 46, valueCardRadius: 8, valueFontSize: 15.5, valueUnitSize: 9,
        topNameSize: 15, topPercentSize: 11, topSegmentHeight: 3.5, topZoneSpacing: 6
    )

    private static let mid = WorkoutScreenMetrics(
        footerBottomGap: 17,
        completeButtonHeight: 33, completeLabelSize: 10.5, segmentsWidth: 58,
        chevronDiameter: 26, chevronIconSize: 10, fusedRowGap: 5.5,
        stepperDiameter: 34, stepperIconSize: 12.5,
        valueCardHeight: 43, valueCardRadius: 8, valueFontSize: 14.5, valueUnitSize: 8.5,
        topNameSize: 14, topPercentSize: 10.5, topSegmentHeight: 3.5, topZoneSpacing: 5.5
    )

    private static let small = WorkoutScreenMetrics(
        footerBottomGap: 15,
        completeButtonHeight: 30, completeLabelSize: 9.5, segmentsWidth: 52,
        chevronDiameter: 23, chevronIconSize: 8.5, fusedRowGap: 4.5,
        stepperDiameter: 31, stepperIconSize: 11.5,
        valueCardHeight: 37, valueCardRadius: 7, valueFontSize: 13.5, valueUnitSize: 8,
        topNameSize: 12, topPercentSize: 9.5, topSegmentHeight: 3, topZoneSpacing: 4.5
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
