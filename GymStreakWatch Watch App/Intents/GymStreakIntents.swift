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
    // `let`, not `var`: a mutable static is global shared mutable state and is
    // rejected under strict concurrency. `AppIntent.title` is a get-only
    // requirement, so an immutable constant satisfies it.
    static let title: LocalizedStringResource = "Start Workout"

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
    static let title: LocalizedStringResource = "Complete Set"

    static var description: IntentDescription {
        IntentDescription("Mark the current exercise set as complete")
    }

    /// Runs in the background — no foreground activation. The legacy
    /// `openAppWhenRun = true` (deprecated in watchOS 26) forced a full
    /// foreground-activation handshake on EVERY press; with the app already
    /// frontmost during a workout that handshake could stall past the system's
    /// intent timeout, leaving the orange Action Button overlay stuck until
    /// "»Satz abschließen« … ist fehlgeschlagen" (observed on device,
    /// July 2026). perform() only calls into the live view model and presents
    /// no UI, so background mode is correct: a press completes the set (with
    /// haptic) even from the watch face, and during a workout the app is
    /// visible anyway. Do NOT reintroduce a foreground requirement here —
    /// GymStreakStartWorkoutIntent must keep openAppWhenRun (StartWorkoutIntent
    /// requires it) but this intent must not.
    static let supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some IntentResult {
        print("Action Button: complete-set perform() started")
        AppStateProvider.shared.workoutViewModel?.handleActionButtonPress()

        // The donated next action persists for the active workout session.
        // Do not launch another donation here: an unstructured registration
        // races this intent finishing and can make the following press vanish.
        // Apple's workout example donates once and returns a plain result for
        // every invocation of its session action.
        print("Action Button: complete-set perform() finished")
        return .result()
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
