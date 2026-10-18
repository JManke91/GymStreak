//
//  OnboardingTrainingProfileTests.swift
//  GymStreakTests
//
//  The last step of the first-run tour — "How do you train?" — and what each
//  way of leaving it records (docs/onboarding.md, "Step 7").
//
//  What carries the ticket: the answer is written by the step's CTA and by
//  nothing else, so a skip stays "unanswered"; "I lift" ends exactly as the
//  tour always did; "I lift and fight" ends on the Fighter Strength program;
//  the answer survives a relaunch; and the CTA names where it leads.
//
//  Like `OnboardingFlowTests`, these run against the real
//  `OnboardingCompletionStore` over a throwaway defaults suite, because "it
//  survives a relaunch" is a property of what was written down.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct OnboardingTrainingProfileTests {

    // MARK: - The question

    @Test("Lifting is the default answer, and the CTA opens the app")
    func liftIsTheDefault() {
        let viewModel = makeViewModel()

        viewModel.go(to: .trainingProfile)

        #expect(viewModel.selectedTrainingProfile == .lift)
        #expect(viewModel.ctaKey == OnboardingStep.finishCTAKey)
    }

    @Test("Choosing to fight renames the CTA after the program it opens")
    func fightRenamesTheCTA() {
        let viewModel = makeViewModel()
        viewModel.go(to: .trainingProfile)

        viewModel.selectTrainingProfile(.fight)
        #expect(viewModel.ctaKey == OnboardingStep.fightFinishCTAKey)

        viewModel.selectTrainingProfile(.lift)
        #expect(viewModel.ctaKey == OnboardingStep.finishCTAKey)
    }

    @Test("The answer changes nothing before the last step")
    func selectionLeavesEarlierStepsAlone() {
        let viewModel = makeViewModel()

        viewModel.selectTrainingProfile(.fight)
        viewModel.go(to: .aiCoach)

        #expect(viewModel.ctaKey == OnboardingStep.aiCoach.ctaKey)
        #expect(viewModel.isPresenting)
    }

    // MARK: - Leaving the step

    @Test("Finishing as a lifter records the answer and opens nothing")
    func finishingAsLifter() {
        let defaults = makeDefaults()
        let programs = SpyProgramDetails()
        let viewModel = makeViewModel(defaults: defaults, programs: programs)

        viewModel.go(to: .trainingProfile)
        viewModel.advance()

        #expect(!viewModel.isPresenting)
        #expect(programs.requested.isEmpty)
        // The answer is on disk: a fresh store over the same defaults reads it.
        #expect(OnboardingCompletionStore(defaults: defaults).trainingProfile == .lift)
        #expect(!makeViewModel(defaults: defaults).isPresenting)
    }

    @Test("Finishing as a fighter records the answer and lands on Fighter Strength")
    func finishingAsFighter() {
        let defaults = makeDefaults()
        let programs = SpyProgramDetails()
        let viewModel = makeViewModel(defaults: defaults, programs: programs)

        viewModel.go(to: .trainingProfile)
        viewModel.selectTrainingProfile(.fight)
        viewModel.advance()

        #expect(!viewModel.isPresenting)
        // The one request, for the catalog's own id — never a literal the slide
        // could drift from (docs/routine-programs.md).
        #expect(programs.requested == [RoutineProgramCatalog.fighterStrength.id])
        #expect(OnboardingCompletionStore(defaults: defaults).trainingProfile == .fight)
    }

    @Test("The landing is requested before the cover comes down")
    func landingIsRequestedBeforeTheFlowEnds() {
        // The Routines tab pushes the detail underneath the cover, so the tour
        // ends *on* the program. The spy sees the flow still presenting when
        // the request arrives.
        let programs = SpyProgramDetails()
        let viewModel = makeViewModel(programs: programs)
        programs.onRequest = { #expect(viewModel.isPresenting) }

        viewModel.go(to: .trainingProfile)
        viewModel.selectTrainingProfile(.fight)
        viewModel.advance()

        #expect(programs.requested.count == 1)
    }

    @Test("Skipping records no answer, whatever card was selected")
    func skippingRecordsNoAnswer() {
        let defaults = makeDefaults()
        let programs = SpyProgramDetails()
        let viewModel = makeViewModel(defaults: defaults, programs: programs)

        viewModel.go(to: .trainingProfile)
        viewModel.selectTrainingProfile(.fight)
        viewModel.skip()

        #expect(!viewModel.isPresenting)
        #expect(programs.requested.isEmpty)
        #expect(OnboardingCompletionStore(defaults: defaults).trainingProfile == nil)
        // The tour itself is still spent — skipping is deciding.
        #expect(!makeViewModel(defaults: defaults).isPresenting)
    }

    @Test("A dismissal the tour did not initiate records no answer either")
    func hostDismissalRecordsNoAnswer() {
        let defaults = makeDefaults()
        let viewModel = makeViewModel(defaults: defaults)

        viewModel.go(to: .trainingProfile)
        viewModel.selectTrainingProfile(.fight)
        viewModel.flowWasDismissed()

        #expect(OnboardingCompletionStore(defaults: defaults).trainingProfile == nil)
    }

    @Test("Selecting a card alone writes nothing — only the CTA answers")
    func selectingDoesNotRecord() {
        let defaults = makeDefaults()
        let viewModel = makeViewModel(defaults: defaults)

        viewModel.go(to: .trainingProfile)
        viewModel.selectTrainingProfile(.fight)

        #expect(viewModel.isPresenting)
        #expect(OnboardingCompletionStore(defaults: defaults).trainingProfile == nil)
    }

    // MARK: - The record

    @Test("An install that answered once keeps its answer, and never un-answers")
    func recordSurvivesRelaunch() {
        let defaults = makeDefaults()
        let store = OnboardingCompletionStore(defaults: defaults)

        store.recordTrainingProfile(.fight)

        #expect(store.trainingProfile == .fight)
        #expect(OnboardingCompletionStore(defaults: defaults).trainingProfile == .fight)
        // And a fresh install has none — the funnel buckets that as "unanswered".
        #expect(OnboardingCompletionStore(defaults: makeDefaults()).trainingProfile == nil)
    }

    // MARK: - Localization

    @Test("Every string the last step renders is localized, in both exits")
    func stepStringsAreLocalized() {
        let keys = [
            "onboarding.profile.eyebrow",
            "onboarding.profile.title",
            "onboarding.profile.body",
            "onboarding.profile.lift.title",
            "onboarding.profile.lift.detail",
            "onboarding.profile.fight.title",
            "onboarding.profile.fight.detail",
            "onboarding.profile.import",
            "onboarding.profile.import.dialog_title",
            // The dialog reuses the two import sheets' own titles.
            "history_import.title",
            "history_import.hevy.title",
            OnboardingStep.finishCTAKey,
            OnboardingStep.fightFinishCTAKey
        ]

        for key in keys {
            // A missing entry in Localizable.strings resolves to the key itself.
            #expect(key.localized != key)
        }
    }

    // MARK: - Fixtures

    /// Records every program the tour asked for, in order.
    private final class SpyProgramDetails: ProgramDetailRequesting {
        private(set) var requested: [String] = []
        var onRequest: (() -> Void)?

        func requestProgramDetail(_ programId: String) {
            requested.append(programId)
            onRequest?()
        }
    }

    private func makeViewModel(
        defaults: UserDefaults? = nil,
        programs: SpyProgramDetails? = nil
    ) -> OnboardingFlowViewModel {
        OnboardingFlowViewModel(
            completion: OnboardingCompletionStore(defaults: defaults ?? makeDefaults()),
            programDetails: programs
        )
    }

    /// A throwaway suite per test: the real store writes `UserDefaults.standard`,
    /// which the developer's simulator shares.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "OnboardingTrainingProfileTests.\(UUID().uuidString)")!
    }
}
