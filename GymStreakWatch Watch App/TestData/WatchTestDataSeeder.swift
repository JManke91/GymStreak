//
//  WatchTestDataSeeder.swift
//  GymStreakWatch Watch App
//
//  Provides sample WatchRoutine data for UI testing screenshots.
//  Mirrors the iOS TestDataSeeder exercise/routine names for localization consistency.
//

import Foundation

enum WatchTestDataSeeder {
    /// Returns sample routines matching the iOS test data.
    /// Exercise names are hardcoded per locale since watch UI tests
    /// set the Apple language via Fastlane launch arguments.
    static func sampleRoutines() -> [WatchRoutine] {
        let isGerman = detectGerman()
        let supersetId = UUID()

        return [
            pushDay(isGerman: isGerman, supersetId: supersetId),
            pullDay(isGerman: isGerman),
            legDay(isGerman: isGerman)
        ]
    }

    /// Detect German locale from AppleLanguages user default (set by Fastlane via launch arguments)
    /// or fall back to Locale.current
    private static func detectGerman() -> Bool {
        if let languages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
           let first = languages.first {
            return first.hasPrefix("de")
        }
        return Locale.current.language.languageCode?.identifier == "de"
    }

    // MARK: - Routines

    private static func pushDay(isGerman: Bool, supersetId: UUID) -> WatchRoutine {
        WatchRoutine(
            id: UUID(),
            name: isGerman ? "Drücken-Tag" : "Push Day",
            exercises: [
                WatchExercise(
                    id: UUID(),
                    name: isGerman ? "Bankdrücken" : "Bench Press",
                    muscleGroup: "Chest",
                    sets: makeSets(count: 4, reps: 8, weight: 85, restTime: 120),
                    order: 0,
                    supersetId: nil,
                    supersetOrder: 0
                ),
                WatchExercise(
                    id: UUID(),
                    name: isGerman ? "Schrägbank-Kurzhanteldrücken" : "Incline Dumbbell Press",
                    muscleGroup: "Upper Chest",
                    sets: makeSets(count: 3, reps: 10, weight: 32, restTime: 90),
                    order: 1,
                    supersetId: nil,
                    supersetOrder: 0
                ),
                WatchExercise(
                    id: UUID(),
                    name: isGerman ? "Kabelzug-Fliegende" : "Cable Flyes",
                    muscleGroup: "Chest",
                    sets: makeSets(count: 3, reps: 12, weight: 18, restTime: 60),
                    order: 2,
                    supersetId: nil,
                    supersetOrder: 0
                ),
                // Superset: Lateral Raises + Tricep Pushdowns
                WatchExercise(
                    id: UUID(),
                    name: isGerman ? "Seitheben" : "Lateral Raises",
                    muscleGroup: "Side Delts",
                    sets: makeSets(count: 3, reps: 12, weight: 10, restTime: 60),
                    order: 3,
                    supersetId: supersetId,
                    supersetOrder: 0
                ),
                WatchExercise(
                    id: UUID(),
                    name: isGerman ? "Trizepsdrücken" : "Tricep Pushdowns",
                    muscleGroup: "Triceps",
                    sets: makeSets(count: 3, reps: 12, weight: 27, restTime: 60),
                    order: 4,
                    supersetId: supersetId,
                    supersetOrder: 1
                )
            ]
        )
    }

    private static func pullDay(isGerman: Bool) -> WatchRoutine {
        WatchRoutine(
            id: UUID(),
            name: isGerman ? "Ziehen-Tag" : "Pull Day",
            exercises: [
                WatchExercise(
                    id: UUID(),
                    name: isGerman ? "Kreuzheben" : "Deadlift",
                    muscleGroup: "Lower Back",
                    sets: makeSets(count: 4, reps: 5, weight: 143, restTime: 180),
                    order: 0,
                    supersetId: nil,
                    supersetOrder: 0
                ),
                WatchExercise(
                    id: UUID(),
                    name: isGerman ? "Klimmzüge" : "Pull-ups",
                    muscleGroup: "Lats",
                    sets: makeSets(count: 4, reps: 10, weight: 0, restTime: 90),
                    order: 1,
                    supersetId: nil,
                    supersetOrder: 0
                ),
                WatchExercise(
                    id: UUID(),
                    name: isGerman ? "Langhantelrudern" : "Barbell Rows",
                    muscleGroup: "Upper Back",
                    sets: makeSets(count: 4, reps: 8, weight: 70, restTime: 120),
                    order: 2,
                    supersetId: nil,
                    supersetOrder: 0
                ),
                WatchExercise(
                    id: UUID(),
                    name: "Face Pulls",
                    muscleGroup: "Rear Delts",
                    sets: makeSets(count: 3, reps: 15, weight: 18, restTime: 60),
                    order: 3,
                    supersetId: nil,
                    supersetOrder: 0
                ),
                WatchExercise(
                    id: UUID(),
                    name: isGerman ? "Hammercurls" : "Hammer Curls",
                    muscleGroup: "Biceps",
                    sets: makeSets(count: 3, reps: 10, weight: 18, restTime: 60),
                    order: 4,
                    supersetId: nil,
                    supersetOrder: 0
                )
            ]
        )
    }

    private static func legDay(isGerman: Bool) -> WatchRoutine {
        WatchRoutine(
            id: UUID(),
            name: isGerman ? "Bein-Tag" : "Leg Day",
            exercises: [
                WatchExercise(
                    id: UUID(),
                    name: isGerman ? "Kniebeugen" : "Back Squat",
                    muscleGroup: "Quadriceps",
                    sets: makeSets(count: 4, reps: 8, weight: 102, restTime: 150),
                    order: 0,
                    supersetId: nil,
                    supersetOrder: 0
                ),
                WatchExercise(
                    id: UUID(),
                    name: isGerman ? "Rumänisches Kreuzheben" : "Romanian Deadlift",
                    muscleGroup: "Hamstrings",
                    sets: makeSets(count: 3, reps: 10, weight: 84, restTime: 120),
                    order: 1,
                    supersetId: nil,
                    supersetOrder: 0
                ),
                WatchExercise(
                    id: UUID(),
                    name: isGerman ? "Beinpresse" : "Leg Press",
                    muscleGroup: "Quadriceps",
                    sets: makeSets(count: 3, reps: 12, weight: 163, restTime: 90),
                    order: 2,
                    supersetId: nil,
                    supersetOrder: 0
                ),
                WatchExercise(
                    id: UUID(),
                    name: isGerman ? "Beincurls" : "Leg Curls",
                    muscleGroup: "Hamstrings",
                    sets: makeSets(count: 3, reps: 12, weight: 41, restTime: 60),
                    order: 3,
                    supersetId: nil,
                    supersetOrder: 0
                ),
                WatchExercise(
                    id: UUID(),
                    name: isGerman ? "Wadenheben" : "Calf Raises",
                    muscleGroup: "Calves",
                    sets: makeSets(count: 4, reps: 15, weight: 45, restTime: 45),
                    order: 4,
                    supersetId: nil,
                    supersetOrder: 0
                )
            ]
        )
    }

    // MARK: - Helpers

    private static func makeSets(count: Int, reps: Int, weight: Double, restTime: TimeInterval) -> [WatchSet] {
        (0..<count).map { _ in
            WatchSet(id: UUID(), reps: reps, weight: weight, restTime: restTime)
        }
    }
}
