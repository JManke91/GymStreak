//
//  PostWorkoutRecapAggregator.swift
//  GymStreak
//

import Foundation
import SwiftData

/// Builds a `PostWorkoutRecapInput` from a completed `WorkoutSession` for the AI Coach.
/// All heavy computation is synchronous — SwiftData queries are performed via the injected
/// `ModelContext` which must be used on the correct actor (call site is responsible).
struct PostWorkoutRecapAggregator {

    // MARK: - Public API

    /// Builds the AI Coach input for a post-workout recap.
    /// - Parameters:
    ///   - session: The just-completed workout session.
    ///   - locale: The user's current locale.
    ///   - modelContext: The SwiftData context to query history from.
    ///   - now: Injection point for the current date; defaults to `Date()` for production.
    func buildInput(
        session: WorkoutSession,
        locale: Locale,
        modelContext: ModelContext,
        now: Date = Date()
    ) -> PostWorkoutRecapInput {
        let muscleGroupsTrained = buildMuscleGroupSummaries(
            session: session,
            modelContext: modelContext,
            now: now
        )
        let newPRs = detectNewPRs(session: session, modelContext: modelContext)
        let sessionsThisWeek = countSessionsThisWeek(
            session: session,
            modelContext: modelContext,
            now: now
        )

        return PostWorkoutRecapInput(
            locale: locale.identifier,
            workoutVolumeKg: session.totalVolume,
            totalSets: session.totalSetsCount,
            durationMinutes: Int(session.duration / 60),
            muscleGroupsTrained: muscleGroupsTrained,
            newPRs: newPRs,
            sessionsThisWeek: sessionsThisWeek
        )
    }

    // MARK: - Prior Session Count (data-threshold gate)

    /// Counts completed sessions other than `session`, used by `PostWorkoutRecapViewModel`
    /// to gate generation until enough history exists for comparison content.
    func countPriorSessions(excludingSession session: WorkoutSession, modelContext: ModelContext) -> Int {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { s in s.endTime != nil }
        )
        guard let all = try? modelContext.fetch(descriptor) else { return 0 }
        return all.filter { $0.id != session.id }.count
    }

    // MARK: - Muscle Group Summaries

    private func buildMuscleGroupSummaries(
        session: WorkoutSession,
        modelContext: ModelContext,
        now: Date
    ) -> [MuscleGroupSummary] {
        // Step 1: compute per-group volume for this session
        var sessionVolumeByGroup: [String: Double] = [:]
        for exercise in session.workoutExercisesList {
            let primaryGroup = exercise.muscleGroups.first ?? "General"
            let usePlanned = exercise.progressiveOverloadApplied
            let volume = exercise.setsList.filter(\.isCompleted).reduce(0.0) { total, set in
                let w = usePlanned ? set.plannedWeight : set.actualWeight
                let r = usePlanned ? set.plannedReps : set.actualReps
                return total + (w * Double(r))
            }
            sessionVolumeByGroup[primaryGroup, default: 0] += volume
        }

        // Step 2: compute four-week average per group (excluding current session)
        let fourWeekAvgByGroup = computeFourWeekAverageVolumeByGroup(
            excludingSession: session,
            modelContext: modelContext,
            now: now
        )

        // Step 3: build summaries sorted by volume descending
        return sessionVolumeByGroup
            .map { group, volume -> MuscleGroupSummary in
                let avg = fourWeekAvgByGroup[group] ?? 0
                let pct: Int = avg > 0
                    ? Int(((volume - avg) / avg * 100).rounded())
                    : 0
                return MuscleGroupSummary(
                    name: group,
                    volumeKg: volume,
                    percentVsFourWeekAverage: pct
                )
            }
            .sorted { $0.volumeKg > $1.volumeKg }
    }

    /// Computes the average per-muscle-group volume over the last 28 days,
    /// averaged across the number of distinct training days each group appeared,
    /// excluding the current session.
    private func computeFourWeekAverageVolumeByGroup(
        excludingSession: WorkoutSession,
        modelContext: ModelContext,
        now: Date
    ) -> [String: Double] {
        let windowStart = Calendar.current.date(byAdding: .day, value: -28, to: now) ?? now

        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.startTime >= windowStart && session.endTime != nil
            }
        )

        guard let sessions = try? modelContext.fetch(descriptor) else { return [:] }
        let historySessions = sessions.filter { $0.id != excludingSession.id }

        guard !historySessions.isEmpty else { return [:] }

        // Accumulate total volume and day-count per group
        var totalVolumeByGroup: [String: Double] = [:]
        var trainingDaysByGroup: [String: Set<String>] = [:]
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"

        for session in historySessions {
            let dayKey = dayFormatter.string(from: session.startTime)
            for exercise in session.workoutExercisesList {
                let primaryGroup = exercise.muscleGroups.first ?? "General"
                let usePlanned = exercise.progressiveOverloadApplied
                let volume = exercise.setsList.filter(\.isCompleted).reduce(0.0) { total, set in
                    let w = usePlanned ? set.plannedWeight : set.actualWeight
                    let r = usePlanned ? set.plannedReps : set.actualReps
                    return total + (w * Double(r))
                }
                totalVolumeByGroup[primaryGroup, default: 0] += volume
                trainingDaysByGroup[primaryGroup, default: Set()].insert(dayKey)
            }
        }

        // Average = total volume / number of distinct training days for that group
        var averages: [String: Double] = [:]
        for (group, total) in totalVolumeByGroup {
            let dayCount = Double(trainingDaysByGroup[group]?.count ?? 1)
            averages[group] = total / dayCount
        }
        return averages
    }

    // MARK: - PR Detection

    /// Detects exercises in `session` that set a new all-time estimated-1RM PR.
    /// Uses the Epley formula: weight * (1 + reps / 30.0).
    /// Delegates to `PersonalRecordService.computePRs` by building a slice of
    /// history up to and including the current session.
    private func detectNewPRs(
        session: WorkoutSession,
        modelContext: ModelContext
    ) -> [PRSummary] {
        // Fetch all sessions up to and including this one
        let sessionStart = session.startTime
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { s in
                s.startTime <= sessionStart && s.endTime != nil
            },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        guard let allSessions = try? modelContext.fetch(descriptor) else { return [] }

        // Build prior bests excluding the current session
        let priorSessions = allSessions.filter { $0.id != session.id }
        var priorBestByKey: [String: Double] = [:]
        for s in priorSessions {
            for exercise in s.workoutExercisesList {
                let key = exercise.stableKey
                let usePlanned = exercise.progressiveOverloadApplied
                for set in exercise.setsList where set.isCompleted {
                    let w = usePlanned ? set.plannedWeight : set.actualWeight
                    let r = usePlanned ? set.plannedReps : set.actualReps
                    guard w > 0, r > 0 else { continue }
                    let est = w * (1.0 + Double(r) / 30.0)
                    priorBestByKey[key] = max(priorBestByKey[key] ?? 0, est)
                }
            }
        }

        // Find new PRs in the current session
        var prs: [PRSummary] = []
        for exercise in session.workoutExercisesList {
            let key = exercise.stableKey
            let usePlanned = exercise.progressiveOverloadApplied
            let priorBest = priorBestByKey[key] ?? 0

            var bestSetFor1RM: (w: Double, r: Int, est: Double)?
            for set in exercise.setsList where set.isCompleted {
                let w = usePlanned ? set.plannedWeight : set.actualWeight
                let r = usePlanned ? set.plannedReps : set.actualReps
                guard w > 0, r > 0 else { continue }
                let est = w * (1.0 + Double(r) / 30.0)
                if est > (bestSetFor1RM?.est ?? 0) {
                    bestSetFor1RM = (w, r, est)
                }
            }

            guard let best = bestSetFor1RM, best.est > priorBest else { continue }
            prs.append(PRSummary(
                exerciseName: exercise.exerciseName,
                weightKg: best.w,
                reps: best.r
            ))
        }

        return prs
    }

    // MARK: - Sessions This Week

    /// Counts distinct workout sessions in the rolling 7-day window ending at `now`,
    /// including the current session even if it has no `endTime` yet.
    private func countSessionsThisWeek(
        session: WorkoutSession,
        modelContext: ModelContext,
        now: Date
    ) -> Int {
        let windowStart = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now

        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { s in
                s.startTime >= windowStart && s.endTime != nil
            }
        )
        let historySessions = (try? modelContext.fetch(descriptor)) ?? []
        let ids = Set(historySessions.map(\.id))

        // Always count the current session
        var count = ids.count
        if !ids.contains(session.id) && session.startTime >= windowStart {
            count += 1
        }
        return count
    }
}
