//
//  AICoachPreferences.swift
//  GymStreak
//
//  Observable singleton that persists all AI Coach user preferences via UserDefaults.
//  Uses @Observable (Swift 6 / iOS 18+) — not ObservableObject.
//

import Foundation
import Observation

/// All persisted settings for the AI Coach feature.
///
/// Use `AICoachPreferences.shared` throughout the app.
/// Effective-state helpers combine `hasCompletedOptIn` with `isMasterEnabled`
/// so call-sites never have to re-implement the AND-logic.
@Observable
final class AICoachPreferences: AICoachPreferencesProviding {

    // MARK: - Singleton

    static let shared = AICoachPreferences()

    // MARK: - Private init

    private init() {
        // Read initial values from UserDefaults so the @Observable storage
        // stays in sync with what was persisted on a previous launch.
        hasCompletedOptIn = UserDefaults.standard.bool(forKey: Keys.optedIn)
        isMasterEnabled = UserDefaults.standard.object(forKey: Keys.masterEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Keys.masterEnabled)
        postWorkoutRecapEnabled = UserDefaults.standard.object(forKey: Keys.postWorkout) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Keys.postWorkout)
        periodRecapEnabled = UserDefaults.standard.object(forKey: Keys.periodRecap) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Keys.periodRecap)
        proactiveMonthlyPromptEnabled = UserDefaults.standard.object(forKey: Keys.proactiveMonthly) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Keys.proactiveMonthly)
        exerciseDeepDiveEnabled = UserDefaults.standard.object(forKey: Keys.exerciseDeepDive) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Keys.exerciseDeepDive)
        workoutDetailEnabled = UserDefaults.standard.object(forKey: Keys.workoutDetail) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Keys.workoutDetail)
        chatEnabled = UserDefaults.standard.object(forKey: Keys.chat) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Keys.chat)
        lastProactivePromptShownForPeriodId = UserDefaults.standard.string(forKey: Keys.lastProactivePeriodId)
        optInDeclinedAt = UserDefaults.standard.object(forKey: Keys.optInDeclinedAt) as? Date
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let optedIn              = "aiCoachOptedIn"
        static let masterEnabled        = "aiCoachEnabled"
        static let postWorkout          = "aiCoachPostWorkoutEnabled"
        static let periodRecap          = "aiCoachPeriodRecapEnabled"
        static let proactiveMonthly     = "aiCoachProactiveMonthlyEnabled"
        static let exerciseDeepDive     = "aiCoachExerciseDeepDiveEnabled"
        static let workoutDetail        = "aiCoachWorkoutDetailEnabled"
        static let chat                 = "aiCoachChatEnabled"
        static let lastProactivePeriodId = "aiCoachLastProactivePromptPeriodId"
        static let optInDeclinedAt      = "aiCoachOptInDeclinedAt"
    }

    // MARK: - Stored Properties
    //
    // Each property is backed by a private stored value that writes through to
    // UserDefaults in a `didSet`. @Observable tracks the stored value directly.

    /// Whether the user has completed (accepted) the opt-in flow.
    /// Key: `aiCoachOptedIn`. Default: `false`.
    var hasCompletedOptIn: Bool = false {
        didSet { UserDefaults.standard.set(hasCompletedOptIn, forKey: Keys.optedIn) }
    }

    /// Master on/off switch for the AI Coach.
    /// Key: `aiCoachEnabled`. Default: `true`.
    /// Effective state is `hasCompletedOptIn && isMasterEnabled`.
    var isMasterEnabled: Bool = true {
        didSet { UserDefaults.standard.set(isMasterEnabled, forKey: Keys.masterEnabled) }
    }

    /// Whether the post-workout recap surface is enabled.
    /// Key: `aiCoachPostWorkoutEnabled`. Default: `true`.
    var postWorkoutRecapEnabled: Bool = true {
        didSet { UserDefaults.standard.set(postWorkoutRecapEnabled, forKey: Keys.postWorkout) }
    }

    /// Whether the monthly period recap surface is enabled.
    /// Key: `aiCoachPeriodRecapEnabled`. Default: `true`.
    var periodRecapEnabled: Bool = true {
        didSet { UserDefaults.standard.set(periodRecapEnabled, forKey: Keys.periodRecap) }
    }

    /// Whether the proactive monthly prompt is enabled.
    /// Key: `aiCoachProactiveMonthlyEnabled`. Default: `true`.
    var proactiveMonthlyPromptEnabled: Bool = true {
        didSet { UserDefaults.standard.set(proactiveMonthlyPromptEnabled, forKey: Keys.proactiveMonthly) }
    }

    /// Whether the exercise deep-dive surface is enabled.
    /// Key: `aiCoachExerciseDeepDiveEnabled`. Default: `true`.
    var exerciseDeepDiveEnabled: Bool = true {
        didSet { UserDefaults.standard.set(exerciseDeepDiveEnabled, forKey: Keys.exerciseDeepDive) }
    }

    /// Whether the workout detail analysis surface is enabled.
    /// Key: `aiCoachWorkoutDetailEnabled`. Default: `true`.
    var workoutDetailEnabled: Bool = true {
        didSet { UserDefaults.standard.set(workoutDetailEnabled, forKey: Keys.workoutDetail) }
    }

    /// Whether the chat assistant surface is enabled.
    /// Key: `aiCoachChatEnabled`. Default: `true`.
    var chatEnabled: Bool = true {
        didSet { UserDefaults.standard.set(chatEnabled, forKey: Keys.chat) }
    }

    /// Tracks the last calendar period for which the proactive monthly prompt was shown,
    /// so Wave 3 can suppress repeated prompts within the same month boundary.
    /// Key: `aiCoachLastProactivePromptPeriodId`. Default: `nil`.
    var lastProactivePromptShownForPeriodId: String? {
        didSet { UserDefaults.standard.set(lastProactivePromptShownForPeriodId, forKey: Keys.lastProactivePeriodId) }
    }

    /// Timestamp of the last time the user dismissed the opt-in with "Vielleicht später".
    /// Used to suppress re-prompting within a 7-day window.
    /// Key: `aiCoachOptInDeclinedAt`. Default: `nil`.
    var optInDeclinedAt: Date? {
        didSet { UserDefaults.standard.set(optInDeclinedAt, forKey: Keys.optInDeclinedAt) }
    }

    // MARK: - Effective State Helpers

    /// `true` when the user has opted in AND the master toggle is on.
    var isEffectivelyEnabled: Bool {
        hasCompletedOptIn && isMasterEnabled
    }

    /// Post-workout recap is active.
    var isPostWorkoutEffectivelyEnabled: Bool {
        isEffectivelyEnabled && postWorkoutRecapEnabled
    }

    /// Monthly period recap is active.
    var isPeriodRecapEffectivelyEnabled: Bool {
        isEffectivelyEnabled && periodRecapEnabled
    }

    /// Proactive monthly prompt is active.
    var isProactiveMonthlyEffectivelyEnabled: Bool {
        isEffectivelyEnabled && proactiveMonthlyPromptEnabled
    }

    /// Exercise deep-dive surface is active.
    var isExerciseDeepDiveEffectivelyEnabled: Bool {
        isEffectivelyEnabled && exerciseDeepDiveEnabled
    }

    /// Workout detail analysis surface is active.
    var isWorkoutDetailEffectivelyEnabled: Bool {
        isEffectivelyEnabled && workoutDetailEnabled
    }

    /// Chat assistant surface is active.
    var isChatEffectivelyEnabled: Bool {
        isEffectivelyEnabled && chatEnabled
    }

    // MARK: - Opt-in Re-prompt Logic

    /// `true` when we should show the opt-in screen.
    ///
    /// Conditions:
    /// 1. User has never completed opt-in.
    /// 2. If the user previously tapped "Vielleicht später", at least 7 days
    ///    must have passed before re-prompting.
    var shouldShowOptIn: Bool {
        guard !hasCompletedOptIn else { return false }
        if let declined = optInDeclinedAt {
            let sevenDays: TimeInterval = 7 * 24 * 60 * 60
            return Date().timeIntervalSince(declined) >= sevenDays
        }
        return true
    }

    /// Records that the user tapped "Vielleicht später", suppressing
    /// re-prompts for 7 days.
    func recordOptInDeclined() {
        optInDeclinedAt = Date()
    }
}
