import AppIntents

// MARK: - Complete Set Intent (Primary Action Button function during workout)

struct GymStreakCompleteSetIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Set"

    static var description: IntentDescription {
        IntentDescription("Mark the current exercise set as complete")
    }

    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        // Get the shared app state and complete the set
        if let appDelegate = await AppStateProvider.shared.workoutViewModel {
            appDelegate.completeCurrentSet()
        }

        // Return the same intent so the Action Button continues to complete sets
        return .result(actionButtonIntent: GymStreakCompleteSetIntent())
    }
}

// MARK: - Pause Workout Intent

struct GymStreakPauseWorkoutIntent: PauseWorkoutIntent {
    static var title: LocalizedStringResource = "Pause Workout"

    @MainActor
    func perform() async throws -> some IntentResult {
        if let viewModel = await AppStateProvider.shared.workoutViewModel {
            viewModel.pauseWorkout()
        }
        return .result(actionButtonIntent: GymStreakResumeWorkoutIntent())
    }
}

// MARK: - Resume Workout Intent

struct GymStreakResumeWorkoutIntent: ResumeWorkoutIntent {
    static var title: LocalizedStringResource = "Resume Workout"

    @MainActor
    func perform() async throws -> some IntentResult {
        if let viewModel = await AppStateProvider.shared.workoutViewModel {
            viewModel.resumeWorkout()
        }
        return .result(actionButtonIntent: GymStreakCompleteSetIntent())
    }
}

// MARK: - App Shortcuts Provider

struct GymStreakAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .blue }

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GymStreakPauseWorkoutIntent(),
            phrases: ["Pause \(.applicationName)"],
            shortTitle: "Pause",
            systemImageName: "pause.fill"
        )

        AppShortcut(
            intent: GymStreakResumeWorkoutIntent(),
            phrases: ["Resume \(.applicationName)"],
            shortTitle: "Resume",
            systemImageName: "play.fill"
        )
    }
}

// MARK: - App State Provider (Singleton for Intent access)

@MainActor
final class AppStateProvider {
    static let shared = AppStateProvider()

    weak var workoutViewModel: WatchWorkoutViewModel?

    private init() {}

    func setWorkoutViewModel(_ viewModel: WatchWorkoutViewModel) {
        self.workoutViewModel = viewModel
    }
}
