//
//  WatchMarqueeTextTests.swift
//  GymStreakWatchTests
//
//  `WatchMarqueeCycle` decides whether the active-workout exercise name scrolls
//  and how long its travel takes. Both are pure geometry, and both are easy to
//  get subtly wrong in a way no build catches: a threshold that is too eager
//  makes short names twitch for three points of overflow, and a threshold that
//  is too lax leaves the long German names truncated — the bug the marquee
//  exists to fix.
//
//  The scroll threshold is not an arbitrary constant. It is the exact point
//  where `minimumScaleFactor(0.85)` runs out of room, so these tests pin the
//  handover between "shrink it" and "move it" rather than a magic number.
//

import Foundation
import Testing
@testable import GymStreakWatch_Watch_App

@Suite @MainActor
struct WatchMarqueeTextTests {

    // MARK: - When the label should move at all

    @Test("Text that fits its slot never scrolls")
    func fittingTextDoesNotScroll() {
        let cycle = WatchMarqueeCycle(overflow: -20, slotWidth: 130)

        #expect(cycle.scrolls == false)
        #expect(cycle.travelDuration == 0)
        #expect(cycle.cycleDuration == 0)
    }

    @Test("Text that exactly fills its slot never scrolls")
    func exactFitDoesNotScroll() {
        #expect(WatchMarqueeCycle(overflow: 0, slotWidth: 130).scrolls == false)
    }

    @Test("Overflow the 0.85 scale floor can still absorb shrinks instead of scrolling")
    func absorbableOverflowShrinksInsteadOfScrolling() {
        let slot: CGFloat = 130
        // A label of natural width W fits at scale f when W · f <= slot, so with
        // f >= 0.85 the largest rescuable natural width is slot / 0.85.
        let rescuable = slot / WatchMarqueeCycle.scaleFloor - slot

        let justInside = WatchMarqueeCycle(overflow: rescuable - 0.5, slotWidth: slot)
        #expect(justInside.scrolls == false)
        #expect(justInside.travelDuration == 0)
    }

    @Test("Overflow past the scale floor scrolls, because shrinking can no longer save it")
    func unabsorbableOverflowScrolls() {
        let slot: CGFloat = 130
        let rescuable = slot / WatchMarqueeCycle.scaleFloor - slot

        let justOutside = WatchMarqueeCycle(overflow: rescuable + 0.5, slotWidth: slot)
        #expect(justOutside.scrolls)
        #expect(justOutside.travelDuration > 0)
    }

    @Test("A zero-width slot scrolls nothing — it has not been measured yet")
    func unmeasuredSlotDoesNotScroll() {
        // First layout pass: both widths are still 0. Scrolling here would fire a
        // cycle against garbage geometry before the real measurement lands.
        #expect(WatchMarqueeCycle(overflow: 0, slotWidth: 0).scrolls == false)
        #expect(WatchMarqueeCycle(overflow: 200, slotWidth: 0).scrolls == false)
    }

    // MARK: - Pacing

    @Test("Travel time is the overflow at the fixed crawl speed")
    func travelDurationTracksOverflow() {
        let slot: CGFloat = 130
        let overflow = 96 + slot / WatchMarqueeCycle.scaleFloor - slot
        let cycle = WatchMarqueeCycle(overflow: overflow, slotWidth: slot)

        #expect(cycle.scrolls)
        #expect(
            abs(cycle.travelDuration - Double(overflow / WatchMarqueeCycle.pointsPerSecond)) < 0.0001
        )
    }

    @Test("Longer names take proportionally longer to travel")
    func longerOverflowTravelsLonger() {
        let slot: CGFloat = 130
        let shorter = WatchMarqueeCycle(overflow: 60, slotWidth: slot)
        let longer = WatchMarqueeCycle(overflow: 120, slotWidth: slot)

        #expect(shorter.scrolls)
        #expect(longer.scrolls)
        #expect(longer.travelDuration > shorter.travelDuration)
    }

    @Test("The cycle is head-dominant, so most glances land on the resting prefix")
    func cycleRestsAtTheHeadLongerThanAnywhereElse() {
        // The whole reason the marquee is acceptable on a glance screen: the
        // resting head state is the single longest phase, so a 1–2 second look
        // reads the same prefix the static label used to show.
        let cycle = WatchMarqueeCycle(overflow: 70, slotWidth: 130)

        #expect(cycle.scrolls)
        #expect(WatchMarqueeCycle.headDwell > WatchMarqueeCycle.tailDwell)
        #expect(WatchMarqueeCycle.headDwell > WatchMarqueeCycle.returnDuration)
        #expect(
            abs(
                cycle.cycleDuration
                    - (WatchMarqueeCycle.headDwell
                        + cycle.travelDuration
                        + WatchMarqueeCycle.tailDwell
                        + WatchMarqueeCycle.returnDuration)
            ) < 0.0001
        )
    }

    @Test("The longest shipped German seed name still completes a cycle in a usable time")
    func longestSeedNameCompletesPromptly() {
        // "Kreuzheben mit gestreckten Beinen" is the longest name in the German
        // seed catalog and the case that motivated the marquee. At ~15 pt bold it
        // wants roughly 230 pt in a slot of roughly 130 pt.
        let cycle = WatchMarqueeCycle(overflow: 230 - 130, slotWidth: 130)

        #expect(cycle.scrolls)
        // A full read must fit comfortably inside a normal rest pause rather than
        // outlasting the user's attention.
        #expect(cycle.cycleDuration < 10)
    }
}
