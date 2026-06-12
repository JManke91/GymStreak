import AppIntents

// MARK: - Workout Style (required by StartWorkoutIntent)

enum GymStreakWorkoutStyle: String, AppEnum {
    case strengthTraining

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Workout"

    // Must be literal key-value pairs — dynamic construction (e.g. allCases.map)
    // breaks App Intents metadata extraction and the app silently disappears
    // from the Action Button settings picker.
    static let caseDisplayRepresentations: [GymStreakWorkoutStyle: DisplayRepresentation] = [
        .strengthTraining: "Strength Training"
    ]
}

// MARK: - Start Workout Intent (Action Button anchor)

/// Makes GymStreak selectable under Settings → Action Button → Workout on
/// Apple Watch Ultra and serves as the donation anchor for in-session actions.
/// Requires `workout-processing` in WKBackgroundModes and `workoutStyle`
/// declared as @Parameter — otherwise Settings only offers "Open App".
struct GymStreakStartWorkoutIntent: StartWorkoutIntent {
    static var title: LocalizedStringResource = "Start Workout"

    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Workout")
    var workoutStyle: GymStreakWorkoutStyle

    static var suggestedWorkouts: [GymStreakStartWorkoutIntent] {
        [GymStreakStartWorkoutIntent(style: .strengthTraining)]
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Start Workout")
    }

    init() {
        workoutStyle = .strengthTraining
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // GymStreak workouts are routine-based, so a press with no active session
        // just opens the app at the routine list. The complete-set intent is
        // donated from WatchWorkoutViewModel.startWorkout once a session begins,
        // which also covers workouts started from within the app.
        return .result()
    }
}

// MARK: - Complete Set Intent (Primary Action Button function during workout)

struct GymStreakCompleteSetIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Set"

    static var description: IntentDescription {
        IntentDescription("Mark the current exercise set as complete")
    }

    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateProvider.shared.workoutViewModel?.handleActionButtonPress()

        // Re-donate so the next press completes the following set.
        return .result(actionButtonIntent: GymStreakCompleteSetIntent())
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
