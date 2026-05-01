//
//  WorkoutDetailView.swift
//  GymStreak
//
//  Redesigned per History Redesign (2026-04-22):
//  - Editorial header with type chip + date
//  - 4-metric stat grid (Duration / Sets / Volume / Intensity)
//  - Apple Health banner when session was written to HealthKit
//  - Per-exercise block with highlighted best set and PR badge
//

import SwiftUI
import HealthKit

struct WorkoutDetailView: View {
    let workout: WorkoutSession
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var prExerciseNames: Set<String> = []
    @State private var healthKitKcal: Double?

    private var workoutType: WorkoutType {
        WorkoutType.classify(routineName: workout.routineName)
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    topBar
                    header
                    statsGrid
                    if workout.healthKitWorkoutId != nil {
                        healthKitBanner
                    }
                    if !workout.notes.isEmpty {
                        notesSection
                    }
                    exercisesSection
                    Color.clear.frame(height: 40)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadPRs()
            await loadHealthKitKcal()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                HapticManager.shared.light()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                WorkoutTypeChip(type: workoutType)
                Text(dateString)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            Text(workout.routineName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .kerning(-0.6)
                .foregroundStyle(Color.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private var dateString: String {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.setLocalizedDateFormatFromTemplate("EEE d. MMM")
        return fmt.string(from: workout.startTime)
    }

    // MARK: - Stats grid

    private var statsGrid: some View {
        HStack(spacing: 6) {
            statCard(
                icon: "clock.fill",
                color: Color(red: 90/255, green: 180/255, blue: 255/255),
                value: "\(Int(workout.duration / 60))m",
                label: "history.detail.duration".localized
            )
            statCard(
                icon: "dumbbell.fill",
                color: DesignSystem.Colors.tint,
                value: "\(workout.completedSetsCount)",
                label: "history.detail.sets".localized
            )
            statCard(
                icon: "bolt.fill",
                color: Color(red: 200/255, green: 140/255, blue: 255/255),
                value: formatVolume(workout.totalVolume),
                label: "history.detail.volume".localized
            )
            statCard(
                icon: "flame.fill",
                color: Color(red: 255/255, green: 159/255, blue: 90/255),
                value: "\(workout.completionPercentage)",
                label: "history.detail.intensity".localized
            )
        }
        .padding(.horizontal, 16)
    }

    private func statCard(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .kerning(-0.4)
                .monospacedDigit()
                .foregroundStyle(Color.white)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func formatVolume(_ kg: Double) -> String {
        if kg >= 1000 {
            return String(format: "%.1ft", kg / 1000)
        }
        return "\(Int(kg))kg"
    }

    // MARK: - HealthKit banner

    private var healthKitBanner: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(red: 1, green: 0.42, blue: 0.42))
                    .frame(width: 24, height: 24)
                Image(systemName: "heart.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("history.detail.healthkit.title".localized)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text(healthKitSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(red: 1, green: 0.42, blue: 0.42).opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(red: 1, green: 0.42, blue: 0.42).opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var healthKitSubtitle: String {
        let minutes = Int(workout.duration / 60)
        let durationString = "\(minutes) Min"
        if let kcal = healthKitKcal {
            return String(format: "history.detail.healthkit.subtitle_with_kcal".localized,
                          durationString, "\(Int(kcal))")
        } else {
            return String(format: "history.detail.healthkit.subtitle".localized, durationString)
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("history.detail.notes".localized.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Color.white.opacity(0.45))
            Text(workout.notes)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Exercises

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("history.detail.exercises".localized)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 4)

            let exercises = workout.workoutExercisesList.sorted(by: { $0.order < $1.order })
            VStack(spacing: 8) {
                ForEach(exercises, id: \.id) { exercise in
                    WorkoutDetailExerciseBlock(
                        exercise: exercise,
                        isPR: prExerciseNames.contains(exercise.exerciseName.lowercased())
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Data loading

    @MainActor
    private func loadPRs() async {
        let service = ExerciseProgressService(modelContext: modelContext)
        _ = service // silence if unused
        // Compute PRs by scanning all finished sessions up to and including this one.
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endTime != nil }
        )
        do {
            let all = try modelContext.fetch(descriptor)
            let prs = PersonalRecordService.computePRs(sessions: all)
            prExerciseNames = prs.prExerciseNamesBySession[workout.id] ?? []
        } catch {
            prExerciseNames = []
        }
    }

    @MainActor
    private func loadHealthKitKcal() async {
        guard let externalId = workout.healthKitWorkoutId else { return }
        let store = HKHealthStore()
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            operatorType: .equalTo,
            value: externalId.uuidString
        )
        let result: Double? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                let workout = samples?.first as? HKWorkout
                let kcal = workout?.statistics(for: HKQuantityType(.activeEnergyBurned))?
                    .sumQuantity()?.doubleValue(for: .kilocalorie())
                continuation.resume(returning: kcal)
            }
            store.execute(query)
        }
        healthKitKcal = result
    }
}

// MARK: - Exercise block

import SwiftData

struct WorkoutDetailExerciseBlock: View {
    let exercise: WorkoutExercise
    let isPR: Bool

    private var sortedSets: [WorkoutSet] {
        exercise.setsList.sorted(by: { $0.order < $1.order })
    }

    private var topSet: WorkoutSet? {
        let usePlanned = exercise.progressiveOverloadApplied
        return sortedSets
            .filter(\.isCompleted)
            .max(by: { a, b in
                let aWeight = usePlanned ? a.plannedWeight : a.actualWeight
                let bWeight = usePlanned ? b.plannedWeight : b.actualWeight
                return aWeight < bWeight
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleRow
            setsGrid
        }
        .padding(14)
        .background(Color.white.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(exercise.exerciseName)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .kerning(-0.2)
                .foregroundStyle(Color.white)
                .lineLimit(1)
            if isPR {
                prBadge
            }
            Spacer()
            Text("history.card.sets".localized(exercise.setsList.count))
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }

    private var prBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 9, weight: .bold))
            Text("history.detail.pr".localized)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(Color(red: 1, green: 0.8, blue: 0))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Color(red: 1, green: 0.8, blue: 0).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var setsGrid: some View {
        let sets = sortedSets
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: max(1, min(sets.count, 6)))
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(sets.enumerated()), id: \.offset) { index, set in
                setCell(index: index, set: set, isTop: topSet.map { $0.id == set.id } ?? false)
            }
        }
    }

    private func setCell(index: Int, set: WorkoutSet, isTop: Bool) -> some View {
        let usePlanned = exercise.progressiveOverloadApplied
        let weight = usePlanned ? set.plannedWeight : set.actualWeight
        let reps = usePlanned ? set.plannedReps : set.actualReps
        let weightText = weight > 0 ? String(format: "%gkg", weight) : "history.detail.bw".localized
        let isCompleted = set.isCompleted

        return VStack(spacing: 2) {
            Text(String(format: "history.detail.set_n".localized, index + 1))
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Color.white.opacity(0.4))
            Text(weightText)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .kerning(-0.3)
                .monospacedDigit()
                .foregroundStyle(isCompleted ? Color.white : Color.white.opacity(0.4))
            Text("\(reps) \("history.detail.reps".localized)")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(isTop ? DesignSystem.Colors.tint.opacity(0.1) : Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isTop ? DesignSystem.Colors.tint.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(isCompleted ? 1 : 0.5)
    }
}
