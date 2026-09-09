//
//  FunnelAttributeBucketTests.swift
//  GymStreakTests
//
//  The bucket vocabulary of the anonymous funnel attributes
//  (docs/funnel-instrumentation.md).
//
//  A dashboard filter matches the **literal** string, so `"2-4"` written as
//  `"2– 4"` — or a boundary off by one — would silently match nothing and the
//  chart would read as "no such users" rather than as a bug. Every value and
//  every boundary is therefore asserted character by character.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
struct FunnelAttributeBucketTests {

    @Test("The workout buckets are spelled exactly as the dashboard filters them")
    func workoutBucketSpelling() {
        #expect(attributes(workouts: 0).workoutsCompleted == "0")
        #expect(attributes(workouts: 1).workoutsCompleted == "1")
        #expect(attributes(workouts: 2).workoutsCompleted == "2-4")
        #expect(attributes(workouts: 4).workoutsCompleted == "2-4")
        #expect(attributes(workouts: 5).workoutsCompleted == "5+")
        #expect(attributes(workouts: 500).workoutsCompleted == "5+")
    }

    @Test("The routine buckets are spelled exactly as the dashboard filters them")
    func routineBucketSpelling() {
        #expect(attributes(routines: 0).routinesCreated == "0")
        #expect(attributes(routines: 1).routinesCreated == "1")
        #expect(attributes(routines: 2).routinesCreated == "2+")
        #expect(attributes(routines: 40).routinesCreated == "2+")
    }

    @Test("A count that could not be negative still buckets as zero rather than falling through")
    func negativeCountsBucketAsZero() {
        #expect(attributes(workouts: -1).workoutsCompleted == "0")
        #expect(attributes(routines: -1).routinesCreated == "0")
    }

    @Test("Onboarding and build channel are reported as the dashboard's literal strings")
    func flagSpelling() {
        #expect(attributes(onboarded: true).onboardingCompleted == "true")
        #expect(attributes(onboarded: false).onboardingCompleted == "false")
        #expect(attributes(channel: .appStore).buildChannel == "appstore")
        #expect(attributes(channel: .other).buildChannel == "other")
    }

    private func attributes(
        onboarded: Bool = false,
        workouts: Int = 0,
        routines: Int = 0,
        channel: AppBuildChannel = .other
    ) -> FunnelAttributes {
        FunnelAttributes.make(
            hasCompletedOnboarding: onboarded,
            completedWorkoutCount: workouts,
            userCreatedRoutineCount: routines,
            buildChannel: channel
        )
    }
}
