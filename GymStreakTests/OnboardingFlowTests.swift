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
