//
//  OnboardingFlowTests.swift
//  GymStreakTests
//
//  The first-run onboarding tour (docs/onboarding.md).
//
//  Three things carry the ticket: the tour appears on an install that has never
//  seen it and never again afterwards, with the record surviving a relaunch;
//  **both** exits — finishing the last step and skipping — spend that record;
//  and the step navigation cannot walk off either end of the flow.
//
//  These run against the real `OnboardingCompletionStore` over a throwaway
//  defaults suite, because "it never comes back" is a property of what was
//  written down, and a double would assert it away.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct OnboardingFlowTests {

    // MARK: - When the tour is due

    @Test("An install that has never seen the tour shows it")
    func freshInstallShowsTour() {
        let viewModel = makeViewModel()

        #expect(viewModel.isPresenting)
        #expect(viewModel.currentStep == .welcome)
    }

    @Test("An install that has completed the tour does not show it again")
    func completedInstallSkipsTour() {
        let defaults = makeDefaults()
        let store = OnboardingCompletionStore(defaults: defaults)
        store.recordCompleted()

        let viewModel = OnboardingFlowViewModel(completion: store)

        #expect(!viewModel.isPresenting)
    }

    @Test("Finishing the last step records the flag, and a relaunch goes to the tabs")
    func finishingRecordsTheFlag() {
        let defaults = makeDefaults()
        let viewModel = makeViewModel(defaults: defaults)

        // Walk to the end and one step past it — the last `advance()` is the
        // one that ends the flow.
        for _ in 0..<OnboardingStep.allCases.count {
            viewModel.advance()
        }

        #expect(!viewModel.isPresenting)
        // A fresh view model and store over the same defaults — the next launch.
        #expect(!makeViewModel(defaults: defaults).isPresenting)
    }

    @Test("Skipping records the flag exactly like finishing does")
    func skippingRecordsTheFlag() {
        let defaults = makeDefaults()
        let viewModel = makeViewModel(defaults: defaults)

        viewModel.skip()

        #expect(!viewModel.isPresenting)
        #expect(!makeViewModel(defaults: defaults).isPresenting)
    }

    @Test("A dismissal reported by the host records the flag once")
    func hostDismissalRecordsOnce() {
        let defaults = makeDefaults()
        let viewModel = makeViewModel(defaults: defaults)

        viewModel.skip()
        // SwiftUI writes the binding back after the flow lowered its own flag.
        viewModel.flowWasDismissed()
        viewModel.flowWasDismissed()

        #expect(!viewModel.isPresenting)
        #expect(!makeViewModel(defaults: defaults).isPresenting)
    }

    @Test("The tour is shown regardless of what the install already contains")
    func tourIsUnconditional() {
        // The rule is the absence of one: nothing but the record decides. An
        // existing user updating into this version has never recorded it, so
        // this is the case that test stands for.
        #expect(makeViewModel().isPresenting)
    }

    @Test("The flow never raises itself again once it has ended")
    func onboardingNeverReRaisesItself() {
        // Load-bearing beyond the tour itself: `ContentView` suppresses the
        // Founder thank-you while this flag is up, and that cover spends a
        // once-ever record when its binding is written back. A tour that could
        // rise again would tear down a Founder screen already on display and
        // spend it on nobody.
        let viewModel = makeViewModel()

        viewModel.skip()
        viewModel.advance()
        viewModel.goBack()
        viewModel.skip()

        #expect(!viewModel.isPresenting)
    }

    // MARK: - Step navigation

    @Test("Advancing walks the steps in order")
    func advancingWalksTheSteps() {
        let viewModel = makeViewModel()

        for step in OnboardingStep.allCases {
            #expect(viewModel.currentStep == step)
            #expect(viewModel.stepNumber == step.rawValue + 1)
            viewModel.advance()
        }

        #expect(viewModel.stepCount == OnboardingStep.allCases.count)
    }

    @Test("Back cannot go below the first step")
    func backStopsAtTheFirstStep() {
        let viewModel = makeViewModel()

        #expect(!viewModel.canGoBack)

        viewModel.goBack()
        viewModel.goBack()

        #expect(viewModel.currentStep == .welcome)
        #expect(viewModel.stepNumber == 1)
        // Going back off the first step must not be mistaken for leaving.
        #expect(viewModel.isPresenting)
    }

    @Test("Back returns to the previous step and re-disables itself at the start")
    func backReturnsToPreviousStep() {
        let viewModel = makeViewModel()

        viewModel.advance()
        #expect(viewModel.canGoBack)

        viewModel.goBack()

        #expect(viewModel.currentStep == .welcome)
        #expect(!viewModel.canGoBack)
    }

    // MARK: - Localization

    @Test("Every string in the shell is localized")
    func shellStringsAreLocalized() {
        let keys = [
            "onboarding.skip",
            "onboarding.back.accessibility",
            "onboarding.progress.accessibility",
            "onboarding.step_counter",
            "onboarding.cta.continue",
            "onboarding.welcome.eyebrow",
            "onboarding.welcome.title",
            "onboarding.welcome.body",
            "onboarding.welcome.bullet1",
            "onboarding.welcome.bullet2",
            "onboarding.welcome.bullet3",
            "onboarding.welcome.cta"
        ]

        for key in keys {
            // A missing entry in Localizable.strings resolves to the key itself.
            #expect(key.localized != key)
        }
    }

    @Test("Every string the Routines slide renders is localized")
    func routinesSlideStringsAreLocalized() {
        let content = OnboardingFeatureSlideContent.routines
        let keys = [
            content.breadcrumbKey,
            content.eyebrowKey,
            content.titleKey,
            content.bodyKey,
            "onboarding.preview.accessibility",
            "onboarding.routines.sample.routine_name",
            "onboarding.routines.sample.routine_meta",
            // Borrowed from the seeded library rather than restated, so the
            // tour cannot name an exercise differently than the app does.
            "seed.exercise.lat_pulldown",
            // The set editor's own heading, rendered inside the plate.
            "routine.section.sets"
        ] + content.bulletKeys

        for key in keys {
            #expect(key.localized != key)
        }
    }

    @Test("The Routines slide's sample values produce a uniform set summary")
    func sampleRoutineReadsAsOneScheme() {
        // The header's summary is the plate's headline number. A mixed scheme
        // would silently swap it for the "3 sets · max 55 kg" fallback, which
        // teaches nothing about reps — so the sample staying uniform is a
        // property of the copy, not an accident of the numbers.
        let display = OnboardingSampleRoutine.exerciseCard(in: .kilograms)
        let reps = Set(OnboardingSampleRoutine.plannedSets.map(\.reps))
        let weights = Set(OnboardingSampleRoutine.plannedSets.map(\.kilograms))

        #expect(reps.count == 1)
        #expect(weights.count == 1)
        #expect(display.setSummary.contains("55"))
        #expect(display.setSummary.contains("10"))
        #expect(display.alternativesCount == 1)
    }

    @Test("The Routines slide's sample avatars match the seeded library")
    func sampleRoutineAvatarsMatchTheCatalog() {
        // The slide names its exercises by their seed keys but restates their
        // muscle groups and equipment locally, because `Presentation` may not
        // read `Data/Seeding`. Nothing in the app enforces that the two agree —
        // so the avatar colour and glyph would drift silently the day the
        // catalog row changes. The *test* target may reach across the layer,
        // and this is the only thing holding the copy honest.
        let display = OnboardingSampleRoutine.exerciseCard(in: .kilograms)

        let pulldown = seed("seed.exercise.lat_pulldown")
        #expect(display.avatar?.muscleGroups == pulldown?.muscleGroups)
        #expect(display.avatar?.equipmentType == pulldown?.equipmentType)

        let pullUp = seed("seed.exercise.pull_up")
        #expect(display.alternativeAvatars.first?.muscleGroups == pullUp?.muscleGroups)
        #expect(display.alternativeAvatars.first?.equipmentType == pullUp?.equipmentType)
    }

    @Test("Every string the Supersets slide renders is localized")
    func supersetsSlideStringsAreLocalized() {
        let content = OnboardingFeatureSlideContent.supersets
        let keys = [
            content.breadcrumbKey,
            content.eyebrowKey,
            content.titleKey,
            content.bodyKey,
            // The group's caption is the app's own label, not a slide string.
            "superset.label"
        ] + content.bulletKeys + OnboardingSampleRoutine.supersetMembers.map(\.seedKey)

        for key in keys {
            #expect(key.localized != key)
        }
    }

    @Test("The Supersets slide's sample avatars match the seeded library")
    func supersetSampleAvatarsMatchTheCatalog() {
        // Same reason as the Routines slide's pin: the slide restates the two
        // exercises' muscle groups and equipment locally, and nothing outside
        // this test notices the day a catalog row changes.
        for member in OnboardingSampleRoutine.supersetMembers {
            let row = seed(member.seedKey)
            #expect(row != nil)
            #expect(member.muscleGroups == row?.muscleGroups)
            #expect(member.equipmentType == row?.equipmentType)
        }
    }

    @Test("The Supersets slide's members read as one scheme and share a rest time")
    func supersetSampleReadsAsOneScheme() {
        // Both header summaries have to read "3 × 10 reps · <weight>": the
        // mixed-scheme fallback drops the reps, and a slide about grouping two
        // exercises cannot afford two differently shaped cards. One rest time
        // for the whole group is the slide's actual claim.
        for member in OnboardingSampleRoutine.supersetMembers {
            #expect(Set(member.plannedSets.map(\.reps)).count == 1)
            #expect(Set(member.plannedSets.map(\.kilograms)).count == 1)
            #expect(member.card(in: .kilograms).setSummary.contains("10"))
            // A rep range on every card, so neither shows the empty goal chip.
            #expect(member.targetRepMin < member.targetRepMax)
        }

        #expect(OnboardingSampleRoutine.supersetMembers.count == 2)
        #expect(OnboardingSampleRoutine.supersetRestTime == 90)
    }

    @Test("The first superset of a routine is the one labelled A")
    func theFirstSupersetOfARoutineIsLabelledA() {
        // `OnboardingSampleRoutine.supersetLetter` is a constant, and the colour
        // the slide tints its connector with is derived from it. What makes "A"
        // the right constant is the production label provider, so assert that
        // rather than the constant against itself.
        let group = UUID()
        let exercises = [
            SampleGroupable(supersetId: group, order: 0),
            SampleGroupable(supersetId: group, order: 1)
        ]

        #expect(SupersetLabelProvider.labels(for: exercises)[group] == OnboardingSampleRoutine.supersetLetter)
    }

    /// The smallest thing `SupersetLabelProvider` accepts — the production
    /// conformances are `@Model` types the tour has no reason to build.
    private struct SampleGroupable: SupersetGroupable {
        let supersetId: UUID?
        let order: Int
    }

    private func seed(_ key: String) -> SeedExercise? {
        SeedExerciseCatalog.entries.first { $0.seedKey == key }
    }

    @Test("Every step names a localized call to action")
    func everyStepHasALocalizedCTA() {
        for step in OnboardingStep.allCases {
            #expect(step.ctaKey.localized != step.ctaKey)
        }
    }

    // MARK: - Harness

    private func makeViewModel(defaults: UserDefaults? = nil) -> OnboardingFlowViewModel {
        OnboardingFlowViewModel(
            completion: OnboardingCompletionStore(defaults: defaults ?? makeDefaults())
        )
    }

    /// A throwaway suite per test: the real store writes `UserDefaults.standard`,
    /// which the developer's simulator shares.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "OnboardingFlowTests.\(UUID().uuidString)")!
    }
}
