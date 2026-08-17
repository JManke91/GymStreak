//
//  ContentView.swift
//  GymStreak
//
//  Created by Julian Manke on 14.08.25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        ContentViewInternal(dependencies: dependencies)
    }
}

private struct ContentViewInternal: View {
    @StateObject private var workoutViewModel: WorkoutViewModel
    private let historySnapshotProvider: HistorySnapshotProviding
    private let aiCoachPreferences: AICoachPreferencesProviding
    private let aiCoachAvailability: AICoachAvailabilityProviding
    private let proactivePromptCoordinator: ProactivePromptCoordinating
    /// Hosted once, here, so a gate anywhere in the app can raise a paywall
    /// without its screen owning a sheet. `@Observable`, so reading
    /// `pendingPlacement` in `body` is enough to re-render on a request.
    private let paywalls: any PaywallPresenting
    /// Handed to the paywall so a restore is judged by the same rule every gate
    /// is judged by (docs/pro-subscription.md §5j). Read nowhere else here.
    private let entitlements: any ProEntitlementProviding
    /// Owns §8 A/B's armed triggers and the endowed figures placement B renders.
    /// Read here because both paywall hosts below are here.
    private let proactivePaywalls: ProactivePaywallCoordinator
    /// The one-time Founder thank-you. Hosted here, above the tabs, because it
    /// has to reach the user before any gate, badge or nudge can
    /// (docs/pro-subscription.md §5h).
    private let founderCelebration: FounderCelebrationCoordinator

    /// Observable singletons — @State so SwiftUI tracks their changes.
    @State private var preferences = AICoachPreferences.shared
    @State private var availability = AICoachAvailability.shared

    /// Floating coach bar → full chat (zoom morph). See docs/ai-coach-entry-point-concepts.md.
    @State private var showingCoachChat = false
    @Namespace private var coachChatZoom

    init(dependencies: AppDependencies) {
        self.historySnapshotProvider = dependencies.historySnapshotProvider
        self.aiCoachPreferences = dependencies.aiCoachPreferences
        self.aiCoachAvailability = dependencies.aiCoachAvailability
        self.proactivePromptCoordinator = dependencies.proactivePromptCoordinator
        self.paywalls = dependencies.paywalls
        self.entitlements = dependencies.proEntitlements
        self.proactivePaywalls = dependencies.proactivePaywalls
        self.founderCelebration = dependencies.founderCelebration
        self._workoutViewModel = StateObject(wrappedValue: WorkoutViewModel(
            workoutSessionRepository: dependencies.workoutSessionRepository,
            routineRepository: dependencies.routineRepository,
            healthKitManager: dependencies.makeHealthKitWorkoutService(),
            watchSync: dependencies.watchSync,
            workoutHistoryCorrelation: dependencies.workoutHistoryCorrelation,
            restTimerReminders: dependencies.restTimerReminders,
            restTimerLiveActivity: dependencies.restTimerLiveActivity,
            routineTemplateSync: dependencies.routineTemplateSync,
            recovery: dependencies.workoutRecovery,
            activeWorkout: dependencies.activeWorkout,
            proactivePaywalls: dependencies.proactivePaywalls
        ))
    }

    var body: some View {
        // Read here, in `body`, rather than only inside the sheet's binding
        // closure: that is what registers this view as an observer of the
        // `@Observable` presenter. A closure evaluated later, outside body's
        // tracking scope, would leave a raised paywall unnoticed.
        let pendingPaywall = paywalls.pendingPlacement
        // Read in `body` for the same reason, so raising the Founder screen
        // from the launch task actually re-renders this view.
        let isCelebratingFounder = founderCelebration.isPresenting

        TabView {
            RoutinesView()
                .tabItem {
                    Label("tab.routines".localized, systemImage: "list.bullet")
                }

            ExercisesView()
                .tabItem {
                    Label("tab.exercises".localized, systemImage: "dumbbell.fill")
                }

            HistoryView(
                viewModel: workoutViewModel,
                historySnapshotProvider: historySnapshotProvider,
                aiCoachPreferences: aiCoachPreferences,
                aiCoachAvailability: aiCoachAvailability,
                proactivePromptCoordinator: proactivePromptCoordinator
            )
                .tabItem {
                    Label("tab.history".localized, systemImage: "clock.fill")
                }

            SettingsRootView()
                .tabItem {
                    Label("tab.settings".localized, systemImage: "gearshape.fill")
                }
        }
        .tint(DesignSystem.Colors.tint)
        .preferredColorScheme(.dark)
        .tabBarMinimizeBehavior(.onScrollDown)
        // Floating coach companion bar — visible whenever the chat surface is
        // active; hidden for ineligible devices and when the user disabled it.
        .tabViewBottomAccessory(isEnabled: isCoachBarVisible) {
            CoachBarView {
                // Freeze the screen anchor before presentation lifecycle runs
                // (the cover fires the covered screen's onDisappear, which
                // clears the live anchor).
                CoachScreenContext.shared.freezeForPresentation()
                showingCoachChat = true
            }
            .matchedTransitionSource(id: Self.coachBarTransitionId, in: coachChatZoom)
        }
        .fullScreenCover(isPresented: $showingCoachChat, onDismiss: {
            // Single cancellation point for an in-flight stream (the chat view
            // itself no longer cancels in onDisappear, so pushing settings
            // within the chat stack doesn't kill a streaming answer).
            CoachChatService.shared.cancel()
        }) {
            NavigationStack {
                CoachChatView()
            }
            .navigationTransition(.zoom(sourceID: Self.coachBarTransitionId, in: coachChatZoom))
            // Second paywall host, inside the cover. `.coachChat` is by
            // definition raised from in here (docs/pro-subscription.md §5e), and
            // the root's sheet below cannot reach the screen while a full-screen
            // cover is up — it would only appear once the user left the chat,
            // which reads as a paywall arriving out of nowhere. Both hosts read
            // the same `pendingPlacement`, so whichever shows it clears it for
            // the other; the presenter is untouched.
            //
            // Filtered to `.coachChat` deliberately: any *other* placement that
            // manages to fire while the chat is open belongs on the screen the
            // user came from, not inside a chat they are reading. Such a
            // placement stays pending and surfaces at the root host once the
            // cover closes — the deferral §7 describes, which is the correct
            // behaviour for a placement the chat did not raise.
            .sheet(item: paywallBinding(for: pendingPaywall == .coachChat ? pendingPaywall : nil)) { placement in
                ProPaywallView(
                    placement: placement,
                    entitlements: entitlements,
                    lifetimeTotals: proactivePaywalls.valueMomentTotals,
                    onPaywallShown: { paywalls.didPresent(placement) }
                )
                .onAppear { paywalls.sheetDidAppear() }
            }
        }
        // Pro paywall host. Every placement in the app raises its sheet from
        // here; the presenter decides whether a request becomes a presentation
        // (docs/pro-subscription.md). Suppressed while the coach-chat cover is
        // up, because that cover hosts its own — one binding non-nil in two
        // hosts at once would have both attempt a presentation.
        .sheet(item: paywallBinding(for: showingCoachChat ? nil : pendingPaywall)) { placement in
            ProPaywallView(
                placement: placement,
                entitlements: entitlements,
                // Only `.valueMoment` renders these; every other placement
                // ignores them (docs/pro-subscription.md §5g).
                lifetimeTotals: proactivePaywalls.valueMomentTotals,
                // Reported when an *offer* reaches the screen, not when the
                // sheet does: an offering that fails to resolve shows no offer
                // at all, and that must not spend a once-ever fire.
                onPaywallShown: { paywalls.didPresent(placement) }
            )
            // The sheet itself, on the other hand, is on screen from here on —
            // which is what stops a later request swapping it out from under
            // the user, loading and retry states included.
            .onAppear { paywalls.sheetDidAppear() }
        }
        // The one-time Founder thank-you (docs/pro-subscription.md §5h). A
        // full-screen cover above the tabs, so a grandfathered user meets the
        // good news before anything that could read as bad news. It sells
        // nothing, so it is not routed through the paywall seam.
        .fullScreenCover(isPresented: founderCelebrationBinding(isPresenting: isCelebratingFounder)) {
            FounderCelebrationView()
        }
        // AI Coach opt-in: shown once when Apple Intelligence is available
        // and the user has not yet completed or permanently dismissed opt-in.
        // Suppressed while the Founder screen is up: two covers on one context
        // present one at a time, and this is the ordering that matters — the
        // opt-in comes back on its own once the thank-you is dismissed.
        .fullScreenCover(isPresented: .constant(shouldShowOptIn && !isCelebratingFounder)) {
            AICoachOptInView()
        }
        .task {
            // Resolve availability on first foreground; the fullScreenCover
            // binding re-evaluates once state changes from .unknown → .available.
            await availability.refresh()
        }
    }

    /// Wraps the placement `body` already read into a binding `sheet(item:)` can
    /// clear. Only a dismissal is written back — nothing but the presenter
    /// raises a paywall.
    private func paywallBinding(for placement: PaywallPlacement?) -> Binding<PaywallPlacement?> {
        Binding(
            get: { placement },
            set: { if $0 == nil { paywalls.dismiss() } }
        )
    }

    /// The Founder screen's presentation, with its dismissal reported back —
    /// which is the only thing that spends the once-ever record. Nothing but the
    /// coordinator raises it, so only a dismissal is written back.
    private func founderCelebrationBinding(isPresenting: Bool) -> Binding<Bool> {
        Binding(
            get: { isPresenting },
            set: { if !$0 { founderCelebration.celebrationWasDismissed() } }
        )
    }

    /// `true` when all conditions for showing the opt-in screen are met.
    private var shouldShowOptIn: Bool {
        availability.isAvailable && preferences.shouldShowOptIn
    }

    /// The coach bar rides on every screen — it must vanish entirely when the
    /// device is ineligible or the user turned the feature off.
    private var isCoachBarVisible: Bool {
        availability.isAvailable && preferences.isChatEffectivelyEnabled
    }

    private static let coachBarTransitionId = "coach-bar"
}

#Preview {
    ContentView()
        .modelContainer(for: [Routine.self, Exercise.self, RoutineExercise.self, ExerciseSet.self, RoutineSchedule.self, WorkoutSession.self, WorkoutExercise.self, WorkoutSet.self], inMemory: true)
}
