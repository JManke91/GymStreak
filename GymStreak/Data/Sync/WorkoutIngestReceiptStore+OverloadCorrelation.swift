//
//  WorkoutIngestReceiptStore+OverloadCorrelation.swift
//  GymStreak
//
//  Which recorded workouts already had a weight increase applied from the
//  Watch's post-workout recap (progressive-overload ticket 05).
//
//  Split out of `WorkoutIngestReceiptStore.swift` to keep both files within the
//  repository's file-length convention. It lives on that store rather than in a
//  home of its own because it is written by the transaction path that already
//  owns receipts — a second ledger would be a second thing to keep in step.
//
//  DISPLAY STATE ONLY. A recap increase is a template-only transaction that
//  never amends the frozen completed workout, so History has no other way to
//  know it happened and would offer the same increase again. Losing an entry
//  costs at most one redundant suggestion — never a wrong template value, and
//  never history.
//
//  Order-independent by construction: written when the transaction applies,
//  read when the workout is displayed. It does not matter whether the recap's
//  transaction or the workout itself reached iOS first, nor whether the workout
//  is ever ingested at all.
//
//  Retention matches the receipts beside it — one tiny file per workout that
//  had a recap apply, kept indefinitely. Stale WatchConnectivity delivery has no
//  published lifetime bound, so this directory is pruned only if and when the
//  receipt history gets a proven compaction scheme.
//

import Foundation

extension WorkoutIngestReceiptStore {

    /// One applied increase, as stored.
    ///
    /// `newWeight` is nil when the target's sets do not all share one weight —
    /// a pyramid or drop scheme, where naming the first set's result would
    /// misstate every other set. The Watch recap is careful not to claim a
    /// single number there, and History must not either.
    struct StoredOverload: Codable, Equatable {
        var newWeight: Double?
    }

    // Hoisted rather than allocated per call: `JSONDecoder`/`JSONEncoder` are
    // expensive to construct, and the read runs on a view's load path.
    // `nonisolated` so the off-main read can reach them.
    private nonisolated static let decoder = JSONDecoder()
    private nonisolated static let encoder = JSONEncoder()

    /// `nonisolated` so the off-main read below does not hop back to the main
    /// actor just to append a path component.
    nonisolated func overloadCorrelationURL(forWorkout workoutID: UUID) -> URL? {
        overloadCorrelationDirectory?.appendingPathComponent("\(workoutID.uuidString).json")
    }

    /// Records one applied overload against its source workout. Merges rather
    /// than replaces, so several exercises of the same workout each keep their
    /// own weight, and re-recording the same slot is idempotent.
    ///
    /// Non-throwing by design: this runs after the template mutation has already
    /// committed, and no failure here may undo an applied transaction.
    func recordAppliedOverload(
        workoutID: UUID, routineExerciseID: UUID, newWeight: Double?
    ) {
        guard let url = overloadCorrelationURL(forWorkout: workoutID) else { return }
        var stored = Self.read(at: url)
        stored[routineExerciseID.uuidString] = StoredOverload(newWeight: newWeight)
        do {
            try Self.encoder.encode(stored).write(to: url, options: .atomic)
        } catch {
            print("WorkoutIngestReceiptStore: overload correlation write failed — \(error.localizedDescription)")
        }
    }

    /// Reads off the main actor: this is a disk read on the History detail
    /// screen's load path, and `.task` runs synchronously up to its first await.
    /// The overwhelmingly common answer is "nothing", so the cost is a failed
    /// open — but the main thread should not be the one paying it.
    nonisolated func appliedOverloads(forWorkout workoutID: UUID) async -> [UUID: AppliedOverloadRecord] {
        guard let url = overloadCorrelationURL(forWorkout: workoutID) else { return [:] }
        return await Task.detached(priority: .userInitiated) {
            Self.read(at: url).reduce(into: [:]) { result, pair in
                guard let id = UUID(uuidString: pair.key) else { return }
                result[id] = AppliedOverloadRecord(newWeight: pair.value.newWeight)
            }
        }.value
    }

    private nonisolated static func read(at url: URL) -> [String: StoredOverload] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? decoder.decode([String: StoredOverload].self, from: data)) ?? [:]
    }
}
