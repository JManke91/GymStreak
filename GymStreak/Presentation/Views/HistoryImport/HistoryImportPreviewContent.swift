//
//  HistoryImportPreviewContent.swift
//  GymStreak
//
//  The preview step of the history import: period, counts, unit, library choice,
//  confirm (docs/history-import.md §5). Counts come precomputed from the view model.
//

import SwiftUI

struct HistoryImportPreviewContent: View {
    @Bindable var viewModel: HistoryImportViewModel
    let onImport: () -> Void

    var body: some View {
        if let summary = viewModel.selection,
           let fromBounds = viewModel.fromBounds,
           let toBounds = viewModel.toBounds {
            ScrollView {
                // Lazy: the new-exercise list is as long as the user's Strong library.
                LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    periodCard(fromBounds: fromBounds, toBounds: toBounds)
                    countsCard(summary)
                    if !viewModel.isWeightUnitCertain {
                        unitPicker
                    }
                    if !summary.newExerciseNames.isEmpty {
                        libraryToggle
                    }
                    OnyxButton("history_import.preview.import".localized, icon: "square.and.arrow.down") {
                        onImport()
                    }
                    .disabled(summary.importableWorkoutCount == 0)
                    .opacity(summary.importableWorkoutCount == 0 ? 0.4 : 1)
                    if !summary.newExerciseNames.isEmpty {
                        newExerciseList(summary.newExerciseNames)
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }
        }
    }

    // MARK: - Sections

    private func periodCard(fromBounds: ClosedRange<Date>, toBounds: ClosedRange<Date>) -> some View {
        OnyxCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack {
                    Text("history_import.preview.period".localized)
                        .font(.onyxSubheadline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Spacer()
                    Menu {
                        ForEach(HistoryImportPeriod.allCases, id: \.self) { period in
                            Button {
                                viewModel.apply(period)
                            } label: {
                                if viewModel.activePeriod == period {
                                    Label(Self.title(of: period), systemImage: "checkmark")
                                } else {
                                    Text(Self.title(of: period))
                                }
                            }
                        }
                    } label: {
                        Text(viewModel.activePeriod.map(Self.title(of:)) ?? "history_import.period.custom".localized)
                            .font(.onyxSubheadline)
                            .foregroundStyle(DesignSystem.Colors.tint)
                    }
                    .accessibilityIdentifier("history-import-period-menu")
                }
                DatePicker(
                    "history_import.period.from".localized,
                    selection: $viewModel.rangeStart,
                    in: fromBounds,
                    displayedComponents: .date
                )
                DatePicker(
                    "history_import.period.to".localized,
                    selection: $viewModel.rangeEnd,
                    in: toBounds,
                    displayedComponents: .date
                )
                Text("history_import.period.footer".localized)
                    .font(.onyxFootnote)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .font(.onyxBody)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .tint(DesignSystem.Colors.tint)
        }
    }

    private func countsCard(_ summary: HistoryImportSelectionSummary) -> some View {
        OnyxCard {
            VStack(spacing: DesignSystem.Spacing.md) {
                HistoryImportCountRow(label: "history_import.preview.workouts".localized, value: summary.workoutCount)
                if summary.workoutCount == 0 {
                    notice("history_import.period.empty".localized)
                } else if summary.importableWorkoutCount == 0 {
                    notice("history_import.period.all_imported".localized)
                }
                if summary.alreadyImportedCount > 0 {
                    HistoryImportCountRow(label: "history_import.preview.already".localized, value: summary.alreadyImportedCount)
                }
                HistoryImportCountRow(label: "history_import.preview.matched".localized, value: summary.matchedExerciseCount)
                HistoryImportCountRow(label: "history_import.preview.new".localized, value: summary.newExerciseNames.count)
                if summary.skippedCardioSetCount > 0 {
                    HistoryImportCountRow(label: "history_import.preview.cardio".localized, value: summary.skippedCardioSetCount)
                }
                if summary.skippedWarmupSetCount > 0 {
                    HistoryImportCountRow(label: "history_import.preview.warmup".localized, value: summary.skippedWarmupSetCount)
                }
            }
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.onyxFootnote)
            .foregroundStyle(DesignSystem.Colors.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unitPicker: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("history_import.preview.unit.title".localized)
                .font(.onyxSubheadline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Picker("history_import.preview.unit.title".localized, selection: $viewModel.weightUnit) {
                ForEach(WeightUnit.allCases, id: \.self) { unit in
                    Text(WeightFormatting.unitName(unit)).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            Text("history_import.preview.unit.footer".localized)
                .font(.onyxFootnote)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }

    private var libraryToggle: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Toggle(isOn: $viewModel.createsMissingExercises) {
                Text("history_import.preview.create_exercises".localized)
                    .font(.onyxSubheadline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
            .tint(DesignSystem.Colors.tint)
            Text(
                viewModel.createsMissingExercises
                    ? "history_import.preview.create_exercises.on".localized
                    : "history_import.preview.create_exercises.off".localized
            )
            .font(.onyxFootnote)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }

    @ViewBuilder
    private func newExerciseList(_ names: [String]) -> some View {
        Text(
            viewModel.createsMissingExercises
                ? "history_import.preview.new_list".localized
                : "history_import.preview.new_list.history_only".localized
        )
        .font(.onyxSubheadline)
        .foregroundStyle(DesignSystem.Colors.textSecondary)
        .padding(.top, DesignSystem.Spacing.sm)
        ForEach(names, id: \.self) { name in
            Text(name)
                .font(.onyxBody)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
    }

    private static func title(of period: HistoryImportPeriod) -> String {
        switch period {
        case .everything: "history_import.period.everything".localized
        case .lastMonth: "history_import.period.last_month".localized
        case .lastThreeMonths: "history_import.period.last_3_months".localized
        case .lastYear: "history_import.period.last_year".localized
        }
    }
}
