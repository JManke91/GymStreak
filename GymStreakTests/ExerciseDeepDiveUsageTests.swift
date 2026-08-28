//
//  ExerciseDeepDiveUsageTests.swift
//  GymStreakTests
//
//  The AI Coach's exercise deep-dive describes the body of work the screen above it is
//  showing: the selected usage, at the live library's load behaviour.
//
//  Before this it resolved rows by identity alone, so it folded every usage of an
//  exercise into one series and narrated an est-1RM trend over the blend. Observed on
//  device: `Biceps Curls (Kurzhantel)` with `4–6 Wdh. · Pull` selected read
//  20.0 kg / +0.0% / 6 Workouts, while the coach directly beneath it narrated
//  "in den letzten 15 Sitzungen … +4.4 kg … +22%". Both numbers were arithmetically
//  right for what they measured, and nothing on screen said they measured different
//  things.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct ExerciseDeepDiveUsageTests {

    // MARK: - The selection decides what is described

    /// One exercise trained two ways: a heavy slot climbing 20 → 26 kg, and a light slot
    /// flat at 10 kg. The selected usage's count and trend are its own, not the blend's.
    @Test("A selected usage is counted and trended on its own sessions only")
    func selectedUsageDescribesOnlyItself() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        context.insert(curls)

        let heavySlot = UUID()
        let lightSlot = UUID()
        // Four workouts, each training both slots — heavy climbing, light flat.
        for (index, heavyWeight) in [20.0, 22.0, 24.0, 26.0].enumerated() {
            let session = makeSession(at: Double(10_000 * (index + 1)), in: context)
            addRow(
                exercise: curls, slot: heavySlot, order: 0,
                weight: heavyWeight, reps: 5, to: session, context: context
            )
            addRow(
                exercise: curls, slot: lightSlot, order: 1,
                weight: 10.0, reps: 12, to: session, context: context
            )
        }
        try context.save()

        let aggregator = ExerciseDeepDiveAggregator()

        let heavy = try #require(
            aggregator.buildAggregate(
                exerciseId: curls.id,
                exerciseName: curls.name,
                locale: .init(identifier: "en_US"),
                modelContext: context,
                usage: DeepDiveUsage(selection: .usage(.routineSlot(heavySlot)), label: "4–6 · Pull")
            ).input
        )
        #expect(heavy.totalSessions == 4)
        #expect(heavy.blendedUsageCount == 1)
        #expect(heavy.peak.weightKg == 26)
        // 26 × 5 vs 20 × 5 in Epley terms: +30.3% — the heavy slot's own progression.
        let heavyProgression = try #require(heavy.overallProgression)
        #expect(heavyProgression.percentChange == 30)
        #expect(heavyProgression.estimatedOneRMDeltaKg > 0)

        let light = try #require(
            aggregator.buildAggregate(
                exerciseId: curls.id,
                exerciseName: curls.name,
                locale: .init(identifier: "en_US"),
                modelContext: context,
                usage: DeepDiveUsage(selection: .usage(.routineSlot(lightSlot)), label: "8–12 · Pull")
            ).input
        )
        #expect(light.totalSessions == 4)
        #expect(light.peak.weightKg == 10)
        // Flat, and it is allowed to say so — a single usage still gets its trend.
        #expect(try #require(light.overallProgression).percentChange == 0)
    }

    /// The variant's label reaches the **reader** (via `CoachDeepDiveSurface`'s caption),
    /// never the model. Asked to name the variant, the on-device model expanded
    /// `4–6 Wdh. · Pull` into "die 4-6-Woche-Biceps-Curls-Variante", reading the German
    /// abbreviation for *Wiederholungen* as *Woche*. A label the user must be able to
    /// trust is rendered, not narrated — so the prompt carries only the *fact* that one
    /// variant is being described.
    @Test("The variant label never reaches the prompt, only the fact of one variant")
    func variantLabelIsWithheldFromThePrompt() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        context.insert(curls)

        let heavySlot = UUID()
        let lightSlot = UUID()
        for index in 0..<4 {
            let session = makeSession(at: Double(10_000 * (index + 1)), in: context)
            session.routineName = "Pull"
            addRow(exercise: curls, slot: heavySlot, order: 0, weight: 20, reps: 5, to: session, context: context)
            addRow(exercise: curls, slot: lightSlot, order: 1, weight: 10, reps: 12, to: session, context: context)
        }
        try context.save()

        let pickerLabel = "4–6 Wdh. · Pull"
        let input = try #require(
            ExerciseDeepDiveAggregator().buildAggregate(
                exerciseId: curls.id,
                exerciseName: curls.name,
                locale: .init(identifier: "en_US"),
                modelContext: context,
                usage: DeepDiveUsage(selection: .usage(.routineSlot(heavySlot)), label: pickerLabel)
            ).input
        )

        // The input records which variant it describes...
        #expect(input.usageLabel == pickerLabel)
        let prompt = input.toPromptText()
        // ...and the prompt says a variant is being described...
        #expect(prompt.contains("Variant: one specific variant"))
        // ...without ever handing the model the string.
        #expect(!prompt.contains(pickerLabel))
        #expect(!prompt.contains("Wdh."))
    }

    /// The whole exercise gets no `Variant:` line at all — there is nothing to narrow to.
    @Test("A one-usage exercise is not described as a variant")
    func combinedOverOneUsageEmitsNoVariantLine() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        context.insert(curls)

        let slot = UUID()
        for (index, weight) in [20.0, 22.0, 24.0, 26.0].enumerated() {
            let session = makeSession(at: Double(10_000 * (index + 1)), in: context)
            addRow(exercise: curls, slot: slot, order: 0, weight: weight, reps: 5, to: session, context: context)
        }
        try context.save()

        let input = try #require(
            ExerciseDeepDiveAggregator().buildAggregate(
                exerciseId: curls.id,
                exerciseName: curls.name,
                locale: .init(identifier: "en_US"),
                modelContext: context,
                usage: .combined
            ).input
        )
        #expect(input.usageLabel == nil)
        #expect(!input.toPromptText().contains("Variant:"))
    }

    /// The period is handed over in the reader's own language. It used to be
    /// `"2026-07 to 2026-08"`, and the model echoed that machine format straight into
    /// prose: "in den letzten 2026-07 und 2026-08".
    @Test("The history range is localized month names, never a machine format")
    func historyRangeIsLocalizedMonths() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        context.insert(curls)

        let slot = UUID()
        // 1970-01 through 1970-04, so the labels are stable regardless of "today".
        for (index, weight) in [20.0, 22.0, 24.0, 26.0].enumerated() {
            let session = makeSession(at: Double(index) * 2_678_400, in: context)
            addRow(exercise: curls, slot: slot, order: 0, weight: weight, reps: 5, to: session, context: context)
        }
        try context.save()

        let input = try #require(
            ExerciseDeepDiveAggregator().buildAggregate(
                exerciseId: curls.id,
                exerciseName: curls.name,
                locale: .init(identifier: "en_US"),
                modelContext: context,
                usage: .combined
            ).input
        )

        #expect(input.historyRange.contains("January 1970"))
        #expect(input.historyRange.contains("–"))
        // No machine format anywhere near the model.
        #expect(!input.historyRange.contains("1970-01"))
        #expect(!input.toPromptText().contains("1970-01"))
    }

    /// `DeepDiveUsage` drops a label handed to `.combined`: the view model's
    /// `selectedUsageLabel` returns "Alle Varianten" there, and a narrative must never
    /// present the blend as one named variant.
    @Test("A label handed to .combined is dropped rather than narrated")
    func combinedNeverCarriesAVariantLabel() {
        let usage = DeepDiveUsage(selection: .combined, label: "Alle Varianten")
        #expect(usage.label == nil)
        #expect(DeepDiveUsage.combined.label == nil)
    }

    // MARK: - The blended view states no trend

    /// `.combined` over several usages is the number the Trend stat card withholds by
    /// printing *Gemischt*. The coach withholds it too — and it withholds the segments
    /// with it, since a segment magnitude is a first-to-last delta of the same blend.
    @Test("A blended combined view states no progression at all")
    func combinedOverSeveralUsagesWithholdsTheTrend() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        context.insert(curls)

        let heavySlot = UUID()
        let lightSlot = UUID()
        for (index, heavyWeight) in [20.0, 22.0, 24.0, 26.0].enumerated() {
            let session = makeSession(at: Double(10_000 * (index + 1)), in: context)
            addRow(exercise: curls, slot: heavySlot, order: 0, weight: heavyWeight, reps: 5, to: session, context: context)
            addRow(exercise: curls, slot: lightSlot, order: 1, weight: 10.0, reps: 12, to: session, context: context)
        }
        try context.save()

        let combined = try #require(
            ExerciseDeepDiveAggregator().buildAggregate(
                exerciseId: curls.id,
                exerciseName: curls.name,
                locale: .init(identifier: "en_US"),
                modelContext: context,
                usage: .combined
            ).input
        )

        #expect(combined.blendedUsageCount == 2)
        #expect(combined.overallProgression == nil)
        #expect(combined.strongestSegment == nil)
        #expect(combined.currentSegment == nil)
        #expect(combined.usageLabel == nil)
        // The record survives — it is the best this exercise was ever lifted, which is
        // what the Rekord card also keeps for the combined view.
        #expect(combined.peak.weightKg == 26)

        // And nothing that looks like a trend reaches the model.
        let prompt = combined.toPromptText()
        #expect(prompt.contains("BLENDED VIEW"))
        #expect(!prompt.contains("Percent change"))
        #expect(!prompt.contains("Overall progression"))
        #expect(!prompt.contains("Classification"))
    }

    /// An exercise trained exactly one way keeps its trend under `.combined`: combined
    /// *is* that usage, and withholding there would strip a correct number from nearly
    /// every exercise in the app. Same clause as `chartsSeveralUsagesTogether`.
    @Test("Combined over a single usage keeps its progression")
    func combinedOverOneUsageKeepsItsTrend() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        context.insert(curls)

        let slot = UUID()
        for (index, weight) in [20.0, 22.0, 24.0, 26.0].enumerated() {
            let session = makeSession(at: Double(10_000 * (index + 1)), in: context)
            addRow(exercise: curls, slot: slot, order: 0, weight: weight, reps: 5, to: session, context: context)
        }
        try context.save()

        let input = try #require(
            ExerciseDeepDiveAggregator().buildAggregate(
                exerciseId: curls.id,
                exerciseName: curls.name,
                locale: .init(identifier: "en_US"),
                modelContext: context,
                usage: .combined
            ).input
        )

        #expect(input.blendedUsageCount == 1)
        #expect(input.overallProgression != nil)
        #expect(input.strongestSegment != nil)
    }

    /// A blended view gets instructions that never mention progression at all.
    ///
    /// It used to get the single-variant prompt with a late "Exception — BLENDED VIEW"
    /// bullet, and on a device check the model followed the dominant four-paragraph
    /// progression structure instead: from an input holding no trend, no segment and no
    /// frequency it produced "1.5 kg mehr geschätztes 1RM", "zwischen 22.5 kg und
    /// 24.5 kg", "2.2 pro Woche" and a "3-wöchige Phase zwischen April und Juni 2026" —
    /// every number invented. Leaving no structure to fill in is the fix.
    @Test("A blended view gets instructions with no progression vocabulary")
    func blendedViewGetsItsOwnInstructions() {
        let blended = ExerciseDeepDiveInstructions.systemPrompt(forBlendedView: true, localeIdentifier: "en_US")
        let single = ExerciseDeepDiveInstructions.systemPrompt(forBlendedView: false, localeIdentifier: "en_US")

        #expect(blended != single)
        #expect(blended == ExerciseDeepDiveInstructions.blendedViewPrompt)
        #expect(single == ExerciseDeepDiveInstructions.singleVariantPrompt)

        // Nothing that describes a progression paragraph survives into the blended prompt,
        // so there is no shape for the model to complete with numbers it does not have.
        for forbidden in [
            "Overall progression",
            "strongest improvement segment",
            "current segment",
            "percentChange",
            "estimatedOneRMDelta",
            "3 to 4 short paragraphs"
        ] {
            #expect(!blended.contains(forbidden), "blended prompt must not mention \(forbidden)")
        }
        // And it says so outright.
        #expect(blended.contains("There is no progression data"))
        #expect(blended.contains("2 short paragraphs"))

        // Neither prompt uses Markdown emphasis. The model mirrors the style of its
        // instructions, and the narrative is rendered as plain text — asterisks in the
        // prompt came back as literal "**15**" and "**20,0 kg**" on screen.
        #expect(!blended.contains("**"))
        #expect(!single.contains("**"))
        #expect(blended.contains("DO NOT use Markdown"))
        #expect(single.contains("DO NOT use Markdown"))
    }

    /// Apple's documented pattern for a non-English reader: English instructions, plus an
    /// explicit output-language directive whose *English* phrasing is the one the model was
    /// trained on. Writing the instructions in German was tried first and reverted — Apple
    /// documents no such approach.
    @Test("A non-English locale prepends Apple's output-language directive")
    func nonEnglishLocalePrependsTheLanguageDirective() {
        let german = ExerciseDeepDiveInstructions.systemPrompt(forBlendedView: false, localeIdentifier: "de_DE")

        #expect(german.hasPrefix("The person's locale is de_DE.\nYou MUST respond in German.\n"))
        // The instructions themselves stay English.
        #expect(german.contains(ExerciseDeepDiveInstructions.singleVariantPrompt))
        #expect(!german.contains("Antworte"))

        // US English is the model's own default and gets no directive at all.
        let english = ExerciseDeepDiveInstructions.systemPrompt(forBlendedView: false, localeIdentifier: "en_US")
        #expect(english == ExerciseDeepDiveInstructions.singleVariantPrompt)
    }

    /// Figures are written in the reader's own convention, so the model only copies them
    /// rather than converting separators — one fewer transformation it can get wrong.
    @Test("Decimals are formatted in the reader's locale")
    func decimalsUseTheReadersSeparator() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        context.insert(curls)
        let slot = UUID()
        for (index, weight) in [20.0, 22.0, 24.0, 26.5].enumerated() {
            let session = makeSession(at: Double(10_000 * (index + 1)), in: context)
            addRow(exercise: curls, slot: slot, order: 0, weight: weight, reps: 5, to: session, context: context)
        }
        try context.save()

        let aggregator = ExerciseDeepDiveAggregator()
        let german = try #require(
            aggregator.buildAggregate(
                exerciseId: curls.id,
                exerciseName: curls.name,
                locale: .init(identifier: "de_DE"),
                modelContext: context,
                usage: .combined
            ).input
        )
        #expect(german.toPromptText().contains("26,5 kg"))

        let english = try #require(
            aggregator.buildAggregate(
                exerciseId: curls.id,
                exerciseName: curls.name,
                locale: .init(identifier: "en_US"),
                modelContext: context,
                usage: .combined
            ).input
        )
        #expect(english.toPromptText().contains("26.5 kg"))
    }

    // MARK: - Load behaviour homogeneity

    /// The library exercise is a counterweight-assisted machine today; four of its
    /// workouts were logged while it was still a plain resistance exercise. Those rows
    /// hold physical loads, the newer ones hold *assistance* values, and a series mixing
    /// them means nothing (`docs/assisted-exercise-progress.md`).
    @Test("Rows logged under a different load behaviour are not part of the series")
    func mixedLoadBehaviourHistoryIsFilteredToTheLiveBehaviour() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let pullUps = Exercise(name: "Assisted Pull-Ups", equipmentType: .machine, loadBehavior: .counterweightAssistance)
        context.insert(pullUps)

        let slot = UUID()
        // Old rows, recorded as a plain resistance exercise: physical loads.
        for (index, weight) in [60.0, 62.0, 64.0, 66.0].enumerated() {
            let session = makeSession(at: Double(1_000 * (index + 1)), in: context)
            addRow(
                exercise: pullUps, slot: slot, order: 0, weight: weight, reps: 5,
                loadBehavior: .resistance, to: session, context: context
            )
        }
        // Current rows: counterweight assistance, falling as the user gets stronger.
        for (index, assistance) in [30.0, 28.0, 26.0, 24.0].enumerated() {
            let session = makeSession(at: Double(100_000 * (index + 1)), in: context)
            addRow(
                exercise: pullUps, slot: slot, order: 0, weight: assistance, reps: 5,
                loadBehavior: .counterweightAssistance, to: session, context: context
            )
        }
        try context.save()

        let input = try #require(
            ExerciseDeepDiveAggregator().buildAggregate(
                exerciseId: pullUps.id,
                exerciseName: pullUps.name,
                locale: .init(identifier: "en_US"),
                modelContext: context,
                usage: .combined
            ).input
        )

        // Four, not eight: the physical-load rows describe a different exercise than the
        // one the library now holds, so they are not in this series.
        #expect(input.totalSessions == 4)
        #expect(input.peak.weightKg == 30)
        // Still one usage, so the combined view keeps its trend.
        #expect(input.blendedUsageCount == 1)
    }

    // MARK: - Cache key

    /// The narrative is per usage, so the key is per usage. Without the token, switching
    /// usage serves the previous usage's sentences; and switching back would either
    /// re-serve them or cost a second monthly allowance unit.
    @Test("The cache key distinguishes usages, and a switch back is still a hit")
    func cacheKeyDistinguishesUsages() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        context.insert(curls)

        let heavySlot = UUID()
        let lightSlot = UUID()
        for index in 0..<4 {
            let session = makeSession(at: Double(10_000 * (index + 1)), in: context)
            addRow(exercise: curls, slot: heavySlot, order: 0, weight: 20, reps: 5, to: session, context: context)
            addRow(exercise: curls, slot: lightSlot, order: 1, weight: 10, reps: 12, to: session, context: context)
        }
        try context.save()

        let heavyKey = try #require(
            cacheKey(exerciseId: curls.id, usageSelection: .usage(.routineSlot(heavySlot)), context: context)
        )
        let lightKey = try #require(
            cacheKey(exerciseId: curls.id, usageSelection: .usage(.routineSlot(lightSlot)), context: context)
        )
        let combinedKey = try #require(
            cacheKey(exerciseId: curls.id, usageSelection: .combined, context: context)
        )

        #expect(heavyKey != lightKey)
        #expect(heavyKey != combinedKey)
        #expect(lightKey != combinedKey)
        // Switching back lands on the same key, so the cached narrative is re-read
        // rather than regenerated.
        #expect(
            cacheKey(exerciseId: curls.id, usageSelection: .usage(.routineSlot(heavySlot)), context: context)
                == heavyKey
        )
    }

    /// The timestamp half of the key is resolved for the selected usage too: training the
    /// light slot does not invalidate the heavy slot's narrative, whose history is
    /// unchanged.
    @Test("Training one usage does not move another usage's cache key")
    func loggingOneUsageLeavesTheOthersKeyAlone() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        context.insert(curls)

        let heavySlot = UUID()
        let lightSlot = UUID()
        for index in 0..<4 {
            let session = makeSession(at: Double(10_000 * (index + 1)), in: context)
            addRow(exercise: curls, slot: heavySlot, order: 0, weight: 20, reps: 5, to: session, context: context)
        }
        try context.save()

        let heavyBefore = try #require(
            cacheKey(exerciseId: curls.id, usageSelection: .usage(.routineSlot(heavySlot)), context: context)
        )
        let combinedBefore = try #require(
            cacheKey(exerciseId: curls.id, usageSelection: .combined, context: context)
        )

        // A later workout that trained only the light slot.
        let lightDay = makeSession(at: 900_000, in: context)
        addRow(exercise: curls, slot: lightSlot, order: 0, weight: 10, reps: 12, to: lightDay, context: context)
        try context.save()

        let heavyAfter = try #require(
            cacheKey(exerciseId: curls.id, usageSelection: .usage(.routineSlot(heavySlot)), context: context)
        )
        #expect(heavyAfter == heavyBefore)

        // The combined view *did* change — it describes that workout too. Asserting the
        // change rather than mere non-nil-ness is what pins the fetch's newest-first
        // order: reverse it and the key would freeze at the *oldest* session, so every
        // deep-dive narrative would silently stop invalidating.
        let combinedAfter = try #require(
            cacheKey(exerciseId: curls.id, usageSelection: .combined, context: context)
        )
        #expect(combinedAfter != combinedBefore)
    }

    /// One generation walks history **once** (ticket 02), so the timestamp it keys the
    /// narrative by no longer comes from the same fetch the appear-time probe uses. The
    /// two must still answer identically — otherwise a narrative would be written under
    /// one key and looked up under another, and every screen open would regenerate it at
    /// the cost of a monthly allowance unit.
    ///
    /// They are also derived differently on purpose: the probe returns the first match of
    /// a newest-first fetch, the aggregate takes a `max` over an unordered graph.
    @Test("The aggregate's cache timestamp agrees with the appear-time probe")
    func aggregateTimestampAgreesWithTheProbe() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        context.insert(curls)

        let heavySlot = UUID()
        let lightSlot = UUID()
        for index in 0..<4 {
            let session = makeSession(at: Double(10_000 * (index + 1)), in: context)
            addRow(exercise: curls, slot: heavySlot, order: 0, weight: 20, reps: 5, to: session, context: context)
        }
        // A later workout of the *other* usage, so a path that ignored the selection would
        // answer with this session's date instead.
        let lightDay = makeSession(at: 900_000, in: context)
        addRow(exercise: curls, slot: lightSlot, order: 0, weight: 10, reps: 12, to: lightDay, context: context)
        try context.save()

        let aggregator = ExerciseDeepDiveAggregator()
        for selection: ExerciseUsageSelection in [
            .combined,
            .usage(.routineSlot(heavySlot)),
            .usage(.routineSlot(lightSlot))
        ] {
            let probed = aggregator.lastCompletedSetTimestamp(
                exerciseId: curls.id,
                modelContext: context,
                usageSelection: selection
            )
            let aggregated = aggregator.buildAggregate(
                exerciseId: curls.id,
                exerciseName: curls.name,
                locale: .init(identifier: "en_US"),
                modelContext: context,
                usage: DeepDiveUsage(selection: selection, label: nil)
            ).lastCompletedSetTimestamp
            #expect(probed == aggregated)
        }

        // And it is the selected usage's own newest session, not history's.
        #expect(
            aggregator.lastCompletedSetTimestamp(
                exerciseId: curls.id,
                modelContext: context,
                usageSelection: .usage(.routineSlot(heavySlot))
            ) == Date(timeIntervalSince1970: 40_000)
        )
    }

    // MARK: - Fixtures

    /// The key a deep-dive would cache under, assembled exactly as production assembles
    /// it — and, since ticket 02, from both sides of the model-actor boundary: the
    /// aggregator resolves the timestamp for that usage, the ViewModel stamps it into a
    /// key. Spanning both is the point: the two halves are what must agree.
    private func cacheKey(
        exerciseId: UUID,
        usageSelection: ExerciseUsageSelection,
        context: ModelContext
    ) -> String? {
        ExerciseDeepDiveAggregator()
            .lastCompletedSetTimestamp(
                exerciseId: exerciseId,
                modelContext: context,
                usageSelection: usageSelection
            )
            .map {
                ExerciseDeepDiveViewModel.cacheKey(
                    exerciseId: exerciseId,
                    usageSelection: usageSelection,
                    timestamp: $0
                )
            }
    }

    private func makeSession(at timestamp: TimeInterval, in context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(routine: nil)
        session.startTime = Date(timeIntervalSince1970: timestamp)
        session.endTime = Date(timeIntervalSince1970: timestamp + 600)
        context.insert(session)
        return session
    }

    private func addRow(
        exercise: Exercise,
        slot: UUID?,
        order: Int,
        weight: Double,
        reps: Int,
        targetReps: (Int, Int)? = nil,
        loadBehavior: ExerciseLoadBehavior? = nil,
        to session: WorkoutSession,
        context: ModelContext
    ) {
        let row = WorkoutExercise(
            exerciseName: exercise.name,
            muscleGroups: ["Arms"],
            order: order,
            exerciseId: exercise.id,
            routineExerciseId: slot,
            loadBehavior: loadBehavior ?? exercise.loadBehavior
        )
        row.targetRepMin = targetReps?.0
        row.targetRepMax = targetReps?.1
        row.workoutSession = session
        context.insert(row)
        // Two completed sets per row, so four sessions clear the four-set floor.
        for index in 0..<2 {
            let set = WorkoutSet(
                plannedReps: reps,
                actualReps: reps,
                plannedWeight: weight,
                actualWeight: weight,
                restTime: 60,
                order: index
            )
            set.isCompleted = true
            set.workoutExercise = row
            context.insert(set)
        }
    }
}
