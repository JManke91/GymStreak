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
    /// Owns §8 A/B's armed triggers and the endowed figures placement B renders.
    /// Read here because both paywall hosts below are here.
    private let proactivePaywalls: ProactivePaywallCoordinator

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
        self.proactivePaywalls = dependencies.proactivePaywalls
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
            .sheet(item: paywallBinding(for: pendingPaywall)) { placement in
                PaywallPlaceholderView(
                    placement: placement,
                    lifetimeTotals: proactivePaywalls.valueMomentTotals
                )
                .onAppear { paywalls.didPresent(placement) }
            }
        }
        // Pro paywall host. Every placement in the app raises its sheet from
        // here; the presenter decides whether a request becomes a presentation
        // (docs/pro-subscription.md). Suppressed while the coach-chat cover is
        // up, because that cover hosts its own — one binding non-nil in two
        // hosts at once would have both attempt a presentation.
        .sheet(item: paywallBinding(for: showingCoachChat ? nil : pendingPaywall)) { placement in
            PaywallPlaceholderView(
                placement: placement,
                // Only `.valueMoment` renders these; every other placement
                // ignores them (docs/pro-subscription.md §5g).
                lifetimeTotals: proactivePaywalls.valueMomentTotals
            )
            // Reported from `onAppear`, not from the request, because the
            // covers below can keep a raised paywall off the screen — and a
            // paywall nobody saw must not spend its once-ever fire.
            .onAppear { paywalls.didPresent(placement) }
        }
        // AI Coach opt-in: shown once when Apple Intelligence is available
        // and the user has not yet completed or permanently dismissed opt-in.
        .fullScreenCover(isPresented: .constant(shouldShowOptIn)) {
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
