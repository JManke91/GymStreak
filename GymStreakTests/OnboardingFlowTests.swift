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

    // MARK: - Step 4: progressive overload

    @Test("Every string the Progressive Overload slide renders is localized")
    func overloadSlideStringsAreLocalized() {
        let content = OnboardingFeatureSlideContent.progressiveOverload
        let keys = [
            content.breadcrumbKey,
            content.eyebrowKey,
            content.titleKey,
            content.bodyKey,
            // The tour's own marker on the prompt — chrome, not an app control.
            "onboarding.overload.callout",
            // Borrowed rather than restated, so the tour cannot name the
            // exercise differently than the library does.
            OnboardingSampleWorkout.seedKey,
            // What the two production surfaces inside the plate render.
            "workout.exercise.sets_done",
            "workout.exercise.rep_goal",
            "rest_timer.rest_short",
            "rep_range.prompt.for_exercise",
            "rep_range.all_sets_maxed",
            "rep_range.increase"
        ] + content.bulletKeys

        for key in keys {
            #expect(key.localized != key)
        }
    }

    @Test("The Progressive Overload slide's sample avatar matches the seeded library")
    func sampleWorkoutAvatarMatchesTheCatalog() {
        // Same pin as the other two slides: the muscle groups and equipment are
        // restated in `Presentation`, and nothing outside this test notices the
        // day the catalog row changes.
        let row = seed(OnboardingSampleWorkout.seedKey)

        #expect(row != nil)
        #expect(OnboardingSampleWorkout.muscleGroups == row?.muscleGroups)
        #expect(OnboardingSampleWorkout.equipmentType == row?.equipmentType)
        #expect(OnboardingSampleWorkout.exercise.muscleGroups == row?.muscleGroups)
        #expect(OnboardingSampleWorkout.exercise.equipmentType == row?.equipmentType)
    }

    @Test("Every sample set sits at the top of the rep goal, which is what the prompt claims")
    func sampleWorkoutSetsAreAllAtTheRepCeiling() {
        // The slide's entire premise. A set below the ceiling would leave the
        // plate showing a prompt the app would not actually have raised.
        let sets = OnboardingSampleWorkout.completedSets()

        #expect(sets.count == OnboardingSampleWorkout.setCount)

        for set in sets {
            #expect(set.isCompleted)
            #expect(set.isAtUpperRepLimit)
            #expect(!set.isOutsideRepRange)
            #expect(set.targetRepMax == OnboardingSampleWorkout.targetRepMax)
            // No completion time: it is what pushed the reps and the weight into
            // an ellipsis at plate width. See `completedSets()`.
            #expect(set.completedAt == nil)
        }

        // Stable row identities across two builds of the list.
        #expect(sets.map(\.id) == OnboardingSampleWorkout.completedSets().map(\.id))
        #expect(Set(sets.map(\.id)).count == sets.count)
    }

    @Test("The card shows the exercise finished, and offers no swap")
    func sampleWorkoutExerciseReadsAsFinished() {
        let exercise = OnboardingSampleWorkout.exercise

        #expect(exercise.isComplete)
        #expect(exercise.completedSets == OnboardingSampleWorkout.setCount)
        #expect(exercise.repRangeText == "4–6")
        // A swap is only offered before the first set is logged, so a card with
        // three completed sets that still showed one would be a card the app
        // cannot produce.
        #expect(!exercise.canSwap)
        #expect(!exercise.isSwapLocked)
    }

    @Test("The slide previews a suggestion, and its message names no weight")
    func overloadPromptSuggestsWithoutNamingAWeight() {
        // The shipped bar renders `rep_range.all_sets_maxed(targetRepMax)` — the
        // rep goal, never a next weight. The slide's copy is written to that, so
        // this pins the message the reader is actually shown.
        guard case .suggestion(let candidate) = OnboardingSampleWorkout.prompt else {
            Issue.record("The tour must preview a suggestion, not an applied confirmation")
            return
        }

        #expect(candidate.targetRepMax == OnboardingSampleWorkout.targetRepMax)
        #expect(candidate.exerciseName == OnboardingSampleWorkout.seedKey.localized)
        #expect(!candidate.isAssistance)
        #expect(candidate.exerciseId == OnboardingSampleWorkout.exercise.id)

        let message = "rep_range.all_sets_maxed".localized(candidate.targetRepMax)
        let weight = WeightFormatting.number(OnboardingSampleWorkout.kilograms, in: .kilograms)
        #expect(!message.contains(weight))

        // And no slide string may name one either.
        let content = OnboardingFeatureSlideContent.progressiveOverload
        for key in [content.titleKey, content.bodyKey] + content.bulletKeys {
            #expect(!key.localized.contains(weight))
        }
    }

    // MARK: - Step 5: history

    @Test("Every string the History slide renders is localized")
    func historySlideStringsAreLocalized() {
        let content = OnboardingFeatureSlideContent.history
        let keys = [
            content.breadcrumbKey,
            content.eyebrowKey,
            content.titleKey,
            content.bodyKey,
            // Borrowed rather than restated, so the tour cannot name the
            // exercise — or the routine — differently than the app does.
            OnboardingSampleHistory.seedKey,
            "onboarding.routines.sample.routine_name",
            // The marker beside the eyebrow.
            "pro.badge.label",
            // What the three production surfaces inside the plate render.
            "history.detail.duration",
            "history.detail.sets",
            "history.detail.volume",
            "history.detail.intensity",
            "history.card.sets",
            "history.detail.pr",
            "history.detail.pr_record",
            "history.detail.pr_e1rm_vs",
            "history.detail.vs_date",
            "history.detail.top_weight",
            "history.detail.volume_short",
            "history.detail.set_n",
            "history.detail.reps",
            "history.detail.set_new"
        ] + content.bulletKeys

        for key in keys {
            #expect(key.localized != key)
        }

        // The type chip resolves its own key, so it is checked through the label
        // rather than by restating the key the enum picks.
        #expect(!OnboardingSampleHistory.workoutType.label.hasPrefix("history.type."))

        // The slide advertises Pro; the badge is the whole of what it does about
        // it. `OnboardingFeatureSlideView` draws `OnyxProBadge` from this flag.
        #expect(content.showsProBadge)
    }

    @Test("The History slide's session is the routine the tour just built")
    func historySampleIsTheTourRoutine() {
        // The tiles describe the same routine steps 2 and 3 assemble, so the
        // four numbers are that session's rather than plausible-looking ones.
        // Both languages must classify to the same chip: "Upper Body A" and
        // "Oberkörper A" are both `.upper`.
        #expect(OnboardingSampleHistory.workoutType == .upper)
        #expect(OnboardingSampleHistory.workoutType
                == WorkoutType.classify(routineName: OnboardingSampleHistory.routineName))

        let supersetSets = OnboardingSampleRoutine.supersetMembers.flatMap(\.plannedSets)
        #expect(OnboardingSampleHistory.sessionSetCount
                == OnboardingSampleHistory.currentSets.count + supersetSets.count)

        let blockVolume = OnboardingSampleHistory.currentSets
            .reduce(0.0) { $0 + $1.kilograms * Double($1.reps) }
        #expect(OnboardingSampleHistory.sessionVolumeKilograms > blockVolume)

        // The comparison strip prints the previous session's date, so it has to
        // be before this one.
        #expect(OnboardingSampleHistory.previousSessionDate < OnboardingSampleHistory.sessionDate)
    }

    @Test("Every delta the History slide shows is derived from the sets printed beside it")
    func historySampleDeltasAgreeWithTheSets() {
        guard let comparison = OnboardingSampleHistory.comparison,
              let previous = comparison.previousPerformance else {
            Issue.record("The slide must preview a comparison against a previous session")
            return
        }

        let sets = comparison.currentPerformance.sets
        #expect(sets.count == OnboardingSampleHistory.currentSets.count)

        // The chips as the block builds them, so this asserts what is on screen
        // rather than the values behind it.
        let deltas = sets.map {
            SetDeltaChip.Delta(
                comparison: $0,
                isCompleted: true,
                hasPreviousSession: true,
                loadBehavior: .resistance,
                unit: .kilograms
            )
        }

        // Set 1 took the weight up, set 2 repeated, set 3 lost a rep, and set 4
        // did not exist last time — the four states a delta chip has.
        guard case .gain(let gainLabel, _) = deltas[0] else {
            Issue.record("Set 1 must read as a weight gain")
            return
        }
        #expect(gainLabel == "+" + WeightFormatting.label(2.5, in: .kilograms))
        #expect(deltas[1] == .neutral)
        guard case .loss(_, .reps(let repsLost)) = deltas[2] else {
            Issue.record("Set 3 must read as one rep short")
            return
        }
        #expect(repsLost == 1)
        #expect(deltas[3] == .new)
        #expect(sets[3].previousWeight == nil)
        #expect(sets[3].previousReps == nil)

        // The strip's two summary figures, from the same sets: the top weight
        // rose, and so did the volume — a red percentage under four mostly green
        // chips would be a slide arguing with itself.
        let topWeight = sets.filter(\.isCompleted).map(\.currentWeight).max() ?? 0
        #expect(topWeight > (previous.bestSet?.weight ?? 0))
        #expect(comparison.hasComparableVolume)
        #expect((comparison.volumeDeltaPercentage ?? 0) > 0)
    }

    @Test("The History slide's personal record is one the app would actually award")
    func historySamplePRIsAnActualRecord() {
        guard let record = OnboardingSampleHistory.prDetail else {
            Issue.record("The slide must preview a personal record")
            return
        }

        // The set with the best Epley estimate, beating the best of the previous
        // session — which is exactly what `PersonalRecordService` calls a PR. A
        // gold chip on a set that is not a record would be the tour teaching a
        // badge the user's own data will never produce that way.
        let estimates = OnboardingSampleHistory.currentSets.map {
            ExerciseLoadMetrics.estimatedOneRepMax(weight: $0.kilograms, reps: $0.reps)
        }
        #expect(record.estimatedOneRepMax == estimates.max())
        #expect(record.estimatedOneRepMax > (record.previousBest ?? 0))
        #expect(record.previousBest != nil)

        // And it points at a set the block actually draws, so the trophy lands
        // on the right cell.
        #expect(OnboardingSampleHistory.exerciseDisplay.sets.map(\.id).contains(record.setId))
        let recordSet = OnboardingSampleHistory.exerciseDisplay.sets.first { $0.id == record.setId }
        #expect(recordSet?.weight == record.weight)
        #expect(recordSet?.reps == record.reps)
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
