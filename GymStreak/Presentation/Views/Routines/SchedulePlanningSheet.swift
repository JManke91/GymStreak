//
//  SchedulePlanningSheet.swift
//  GymStreak
//
//  Editor for a routine's training plan (see docs/workout-planning.md): pick a
//  rolling cadence ("every N days") or a fixed weekday split, with a live
//  preview of the next few sessions. Persists via `RoutinesViewModel`.
//

import SwiftUI

struct SchedulePlanningSheet: View {
    let routine: Routine
    @ObservedObject var viewModel: RoutinesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var mode: RoutineScheduleType
    @State private var intervalDays: Int
    @State private var weekdays: Set<Int>
    @State private var startDate: Date
    private let isEditing: Bool

    init(routine: Routine, viewModel: RoutinesViewModel) {
        self.routine = routine
        self.viewModel = viewModel
        let schedule = routine.schedule
        self.isEditing = schedule != nil
        _mode = State(initialValue: schedule?.type ?? .everyNDays)
        _intervalDays = State(initialValue: schedule?.intervalDays ?? 3)
        _weekdays = State(initialValue: schedule?.weekdays ?? [])
        // Default the reference date to the last completed workout (so the
        // cadence rolls off it by default); fall back to today when there's no
        // history. An existing plan keeps its previously chosen reference date.
        _startDate = State(initialValue:
            schedule?.startDate
            ?? viewModel.lastPerformedByRoutine[routine.id]
            ?? Date()
        )
    }

    private var canSave: Bool {
        mode == .everyNDays || !weekdays.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        modePicker

                        if mode == .everyNDays {
                            intervalEditor
                            referenceDateEditor
                        } else {
                            weekdayEditor
                        }

                        previewSection

                        if isEditing {
                            removeButton
                        }

                        Color.clear.frame(height: 12)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("schedule.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel".localized) { dismiss() }
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save".localized) { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? DesignSystem.Colors.tint : Color.white.opacity(0.35))
                        .disabled(!canSave)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Mode picker

    private var modePicker: some View {
        HStack(spacing: 0) {
            modeButton(.everyNDays, title: "schedule.mode.interval".localized, icon: "repeat")
            modeButton(.weekdays, title: "schedule.mode.weekdays".localized, icon: "calendar")
        }
        .padding(4)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func modeButton(_ target: RoutineScheduleType, title: String, icon: String) -> some View {
        Button {
            HapticManager.shared.selection()
            withAnimation(DesignSystem.Animation.easeOut) { mode = target }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(mode == target ? DesignSystem.Colors.textOnTint : Color.white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(mode == target ? DesignSystem.Colors.tint : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Interval editor

    private var intervalEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("schedule.interval.label".localized.uppercased())
                .font(.system(size: 11, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(Color.white.opacity(0.45))

            HStack(spacing: 18) {
                stepperButton(icon: "minus") {
                    if intervalDays > 1 { intervalDays -= 1; HapticManager.shared.selection() }
                }
                .disabled(intervalDays <= 1)

                VStack(spacing: 0) {
                    Text("\(intervalDays)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(intervalDays == 1 ? "schedule.interval.unit_one".localized : "schedule.interval.unit".localized)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)

                stepperButton(icon: "plus") {
                    if intervalDays < 30 { intervalDays += 1; HapticManager.shared.selection() }
                }
                .disabled(intervalDays >= 30)
            }

            Text("schedule.interval.hint".localized)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .padding(18)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Reference date

    private var referenceDateEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("schedule.reference.label".localized.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .kerning(0.6)
                    .foregroundStyle(Color.white.opacity(0.45))
                Spacer()
                DatePicker(
                    "",
                    selection: $startDate,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(DesignSystem.Colors.tint)
            }

            if isReferenceLastWorkout {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("schedule.reference.is_last_workout".localized)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(DesignSystem.Colors.tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DesignSystem.Colors.tint.opacity(0.12))
                .clipShape(Capsule())
                .transition(.opacity)
            }

            Text("schedule.reference.hint".localized)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .padding(18)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(DesignSystem.Animation.easeOut, value: isReferenceLastWorkout)
    }

    /// True when the chosen reference date is the routine's last workout day.
    private var isReferenceLastWorkout: Bool {
        guard let last = viewModel.lastPerformedByRoutine[routine.id] else { return false }
        let calendar = HistoryStatsService.isoGermanCalendar()
        return calendar.startOfDay(for: last) == calendar.startOfDay(for: startDate)
    }

    private func stepperButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.tint)
                .frame(width: 48, height: 48)
                .background(DesignSystem.Colors.tint.opacity(0.14))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Weekday editor

    private var weekdayEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("schedule.weekdays.label".localized.uppercased())
                .font(.system(size: 11, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(Color.white.opacity(0.45))

            HStack(spacing: 7) {
                ForEach(ScheduleFormatter.weekdayShortLabels(), id: \.weekday) { entry in
                    weekdayChip(weekday: entry.weekday, label: entry.label)
                }
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func weekdayChip(weekday: Int, label: String) -> some View {
        let selected = weekdays.contains(weekday)
        return Button {
            HapticManager.shared.selection()
            withAnimation(DesignSystem.Animation.easeOut) {
                if selected { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
            }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? DesignSystem.Colors.textOnTint : Color.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(selected ? DesignSystem.Colors.tint : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("schedule.preview.title".localized.uppercased())
                .font(.system(size: 11, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(Color.white.opacity(0.45))

            let dates = previewDates()
            if dates.isEmpty {
                Text("schedule.weekdays.none".localized)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.4))
            } else {
                HStack(spacing: 8) {
                    ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                        VStack(spacing: 3) {
                            Text(previewWeekday(date))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(DesignSystem.Colors.tint)
                            Text(previewDay(date))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(DesignSystem.Colors.tint.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    /// Up to three upcoming occurrences for the current (unsaved) selection.
    /// The cadence preview is anchored on the chosen reference date / last
    /// completion via the shared `WorkoutPlanningService` helper.
    private func previewDates() -> [Date] {
        switch mode {
        case .everyNDays:
            return WorkoutPlanningService.upcomingCadenceDates(
                startDate: startDate,
                lastCompleted: viewModel.lastPerformedByRoutine[routine.id],
                intervalDays: intervalDays,
                count: 3
            )
        case .weekdays:
            guard !weekdays.isEmpty else { return [] }
            let calendar = HistoryStatsService.isoGermanCalendar()
            let today = calendar.startOfDay(for: Date())
            var result: [Date] = []
            for offset in 0...20 where result.count < 3 {
                guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                if weekdays.contains(WorkoutPlanningService.isoWeekday(from: date, calendar: calendar)) {
                    result.append(date)
                }
            }
            return result
        }
    }

    private func previewWeekday(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale.current; f.setLocalizedDateFormatFromTemplate("EEE")
        return String(f.string(from: date).filter(\.isLetter).prefix(2))
    }

    private func previewDay(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale.current; f.setLocalizedDateFormatFromTemplate("d")
        return f.string(from: date)
    }

    // MARK: Remove

    private var removeButton: some View {
        Button {
            HapticManager.shared.light()
            viewModel.removeSchedule(from: routine)
            dismiss()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trash").font(.system(size: 13, weight: .semibold))
                Text("schedule.remove".localized).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(DesignSystem.Colors.destructive)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(DesignSystem.Colors.destructive.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard canSave else { return }
        HapticManager.shared.success()
        viewModel.setSchedule(
            for: routine,
            type: mode,
            intervalDays: intervalDays,
            weekdays: weekdays,
            referenceDate: startDate
        )
        dismiss()
    }
}
