//
//  SwiftDataHistoryImportStore.swift
//  GymStreak
//

import Foundation
import SwiftData

/// Constructs the import's SwiftData model actor outside MainActor, then forwards to it.
///
/// Mirrors `SwiftDataLegacyHistoryAttributionProvider`: `Task.detached` construction
/// (Apple does not document construction-site affinity as a `@ModelActor` guarantee),
/// its own context so its `save()`s never land on the context History reads through,
/// and the shared `HistoryStoreGate` around every touch of the session table.
struct SwiftDataHistoryImportProvider: HistoryImporting {
    private let storeTask: Task<SwiftDataHistoryImportStore, Never>
    private let gate: HistoryStoreGate

    /// Workouts written per `save()` and per gate hold. Short holds let a History rebuild
    /// or a delete interleave with a multi-year import instead of queueing behind all of it.
    static let chunkSize = 100

    /// - Parameter gate: **`AppDependencies`' shared gate**. Not defaulted, for the reason
    ///   given on `SwiftDataHistorySnapshotProvider`.
    init(modelContainer: ModelContainer, gate: HistoryStoreGate) {
        self.gate = gate
        self.storeTask = Task.detached(priority: .userInitiated) {
            SwiftDataHistoryImportStore(modelContainer: modelContainer)
        }
    }

    // `@concurrent` on both methods is load-bearing: without it SE-0461 runs the file
    // read, the parse and the inserts on the calling `@MainActor` view model's actor.
    // See `docs/swift6-concurrency.md` §1; pinned by
    // `SwiftDataHistorySnapshotStoreTests.largeHistoryImportKeepsMainActorResponsive`.
    @concurrent func prepareStrongImport(from url: URL) async throws -> HistoryImportPreview {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { throw HistoryImportError.unreadableFile }

        let file = try StrongCSVParser.parse(text)
        let store = await storeTask.value
        return try await gate.withAccess {
            try await store.preview(of: file)
        }
    }

    @concurrent func importHistory(
        _ file: ParsedHistoryFile,
        weightUnit: WeightUnit,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> HistoryImportResult {
        let store = await storeTask.value
        let (pending, exercises, created) = try await gate.withAccess {
            try await store.prepareWrite(of: file)
        }

        let total = max(file.workouts.count, 1)
        var done = file.workouts.count - pending.count
        progress(Double(done) / Double(total))
        var start = 0
        while start < pending.count {
            let chunk = Array(pending[start..<min(start + Self.chunkSize, pending.count)])
            try await gate.withAccess {
                try await store.insert(chunk, exercises: exercises, weightUnit: weightUnit)
            }
            start += chunk.count
            done += chunk.count
            progress(Double(done) / Double(total))
        }

        return HistoryImportResult(
            importedWorkoutCount: pending.count,
            skippedDuplicateCount: file.workouts.count - pending.count,
            createdExerciseCount: created,
            skippedCardioSetCount: file.skippedCardioSetCount
        )
    }
}

/// The library exercise imported history attaches to. Handed from `prepareWrite` to every
/// `insert` call by value, so the actor holds **no state between calls** — two imports
/// interleaving between gate holds cannot overwrite each other's mapping.
struct HistoryImportResolvedExercise: Sendable {
    let id: UUID
    let name: String
    let muscleGroups: [String]
    let loadBehavior: ExerciseLoadBehavior
}

@ModelActor
actor SwiftDataHistoryImportStore {

    func preview(of file: ParsedHistoryFile) throws -> HistoryImportPreview {
        let library = HistoryImportMatching.libraryIndex(try libraryEntries().map(\.entry))
        let names = HistoryImportMatching.distinctExerciseNames(in: file)
        let newNames = names.filter { library[HistoryImportMatching.normalizedName($0)] == nil }
        let existing = try existingKeys(for: file)
        let dates = file.workouts.map(\.startTime)
        return HistoryImportPreview(
            file: file,
            earliest: dates.min() ?? Date(),
            latest: dates.max() ?? Date(),
            alreadyImportedCount: file.workouts.filter { existing.contains(key(of: $0)) }.count,
            matchedExerciseCount: names.count - newNames.count,
            newExerciseNames: newNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        )
    }

    /// Resolves every exercise name — creating the missing ones as custom exercises — and
    /// returns the workouts not yet in history plus how many exercises were created.
    ///
    /// Workouts are deduplicated before exercises are created, so a re-import of an
    /// already-imported file creates nothing at all.
    func prepareWrite(of file: ParsedHistoryFile) throws -> (
        pending: [ImportedWorkout],
        exercises: [String: HistoryImportResolvedExercise],
        createdExercises: Int
    ) {
        let existing = try existingKeys(for: file)
        let pending = file.workouts.filter { !existing.contains(key(of: $0)) }

        let rows = try libraryEntries()
        let byId = Dictionary(rows.map { ($0.entry.id, $0.model) }, uniquingKeysWith: { first, _ in first })
        let library = HistoryImportMatching.libraryIndex(rows.map(\.entry))
        var resolved: [String: HistoryImportResolvedExercise] = [:]
        var created = 0

        let pendingFile = ParsedHistoryFile(workouts: pending, skippedCardioSetCount: 0, detectedWeightUnit: nil)
        for name in HistoryImportMatching.distinctExerciseNames(in: pendingFile) {
            let key = HistoryImportMatching.normalizedName(name)
            if let entry = library[key], let exercise = byId[entry.id] {
                resolved[key] = HistoryImportResolvedExercise(
                    id: exercise.id, name: exercise.name,
                    muscleGroups: exercise.muscleGroups, loadBehavior: exercise.loadBehavior
                )
                continue
            }
            // The user-created path: no `seedKey`, the model's default muscle group.
            let (equipment, behavior) = HistoryImportMatching.customExerciseTraits(for: name)
            let exercise = Exercise(name: name, muscleGroups: ["General"], equipmentType: equipment, loadBehavior: behavior)
            modelContext.insert(exercise)
            resolved[key] = HistoryImportResolvedExercise(
                id: exercise.id, name: name, muscleGroups: exercise.muscleGroups, loadBehavior: behavior
            )
            created += 1
        }
        if created > 0 { try saveOrRollBack() }
        return (pending, resolved, created)
    }

    /// Writes one chunk of workouts as completed, routine-less sessions and saves once.
    func insert(
        _ workouts: [ImportedWorkout],
        exercises: [String: HistoryImportResolvedExercise],
        weightUnit: WeightUnit
    ) throws {
        for workout in workouts {
            let session = WorkoutSession(routine: nil)
            session.routineName = workout.name
            session.startTime = workout.startTime
            session.endTime = workout.startTime.addingTimeInterval(workout.duration)
            session.notes = workout.notes
            modelContext.insert(session)

            for (order, imported) in workout.exercises.enumerated() {
                // `prepareWrite` resolves every name of every pending workout, so a miss is a
                // programming error — fail loudly rather than write a session missing a block.
                guard let exercise = exercises[HistoryImportMatching.normalizedName(imported.name)] else {
                    assertionFailure("Unresolved exercise \(imported.name)")
                    modelContext.rollback()
                    throw HistoryImportError.writeFailed
                }
                let row = WorkoutExercise(
                    exerciseName: exercise.name,
                    muscleGroups: exercise.muscleGroups,
                    order: order,
                    exerciseId: exercise.id,
                    loadBehavior: exercise.loadBehavior
                )
                row.workoutSession = session
                modelContext.insert(row)
                session.workoutExercises?.append(row)

                for (setOrder, imported) in imported.sets.enumerated() {
                    let kilograms = HistoryImportMatching.storedKilograms(imported.weight, fileUnit: weightUnit)
                    let set = WorkoutSet(
                        plannedReps: imported.reps, actualReps: imported.reps,
                        plannedWeight: kilograms, actualWeight: kilograms,
                        restTime: 60, order: setOrder
                    )
                    set.isCompleted = true
                    set.completedAt = workout.startTime
                    set.workoutExercise = row
                    modelContext.insert(set)
                    row.sets?.append(set)
                }
            }
        }
        try saveOrRollBack()
    }

    /// A failed save must not leave the chunk pending in this long-lived context: the next
    /// dedupe fetch would count it as existing, and a later save could persist it half-written.
    private func saveOrRollBack() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    // MARK: - Reads

    private func key(of workout: ImportedWorkout) -> String {
        HistoryImportMatching.dedupeKey(name: workout.name, startTime: workout.startTime)
    }

    /// Dedupe keys of the sessions inside the file's date range — bounded by the file,
    /// never a whole-history scan, and projected to strings before the gate is released.
    private func existingKeys(for file: ParsedHistoryFile) throws -> Set<String> {
        let dates = file.workouts.map(\.startTime)
        guard let earliest = dates.min(), let latest = dates.max() else { return [] }
        let lower = earliest.addingTimeInterval(-1)
        let upper = latest.addingTimeInterval(1)
        let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.startTime >= lower && $0.startTime <= upper }
        ))
        return Set(sessions.map { HistoryImportMatching.dedupeKey(name: $0.routineName, startTime: $0.startTime) })
    }

    private func libraryEntries() throws -> [(entry: HistoryImportLibraryEntry, model: Exercise)] {
        try modelContext.fetch(FetchDescriptor<Exercise>()).map {
            (HistoryImportLibraryEntry(id: $0.id, name: $0.name, createdAt: $0.createdAt), $0)
        }
    }
}
