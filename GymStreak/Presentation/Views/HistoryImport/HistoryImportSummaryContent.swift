//
//  HistoryImportSummaryContent.swift
//  GymStreak
//
//  The preview (before writing) and result (after writing) screens of the
//  history import. Counts are label/value rows so no string needs plural rules.
//

import SwiftUI

/// What will happen, with the unit choice and the confirm button.
struct HistoryImportPreviewContent: View {
    let preview: HistoryImportPreview
    @Binding var weightUnit: WeightUnit
    let onImport: () -> Void

    var body: some View {
        ScrollView {
            // Lazy: the new-exercise list is as long as the user's Strong library.
            LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                OnyxCard {
                    VStack(spacing: DesignSystem.Spacing.md) {
                        HistoryImportCountRow(label: "history_import.preview.workouts".localized, value: preview.workoutCount)
                        HistoryImportTextRow(
                            label: "history_import.preview.period".localized,
                            value: "\(preview.earliest.formatted(date: .abbreviated, time: .omitted)) – \(preview.latest.formatted(date: .abbreviated, time: .omitted))"
                        )
                        if preview.alreadyImportedCount > 0 {
                            HistoryImportCountRow(label: "history_import.preview.already".localized, value: preview.alreadyImportedCount)
                        }
                        HistoryImportCountRow(label: "history_import.preview.matched".localized, value: preview.matchedExerciseCount)
                        HistoryImportCountRow(label: "history_import.preview.new".localized, value: preview.newExerciseNames.count)
                        if preview.file.skippedCardioSetCount > 0 {
                            HistoryImportCountRow(label: "history_import.preview.cardio".localized, value: preview.file.skippedCardioSetCount)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("history_import.preview.unit.title".localized)
                        .font(.onyxSubheadline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Picker("history_import.preview.unit.title".localized, selection: $weightUnit) {
                        ForEach(WeightUnit.allCases, id: \.self) { unit in
                            Text(WeightFormatting.unitName(unit)).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("history_import.preview.unit.footer".localized)
                        .font(.onyxFootnote)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                OnyxButton("history_import.preview.import".localized, icon: "square.and.arrow.down") {
                    onImport()
                }

                if !preview.newExerciseNames.isEmpty {
                    Text("history_import.preview.new_list".localized)
                        .font(.onyxSubheadline)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .padding(.top, DesignSystem.Spacing.sm)
                    ForEach(preview.newExerciseNames, id: \.self) { name in
                        Text(name)
                            .font(.onyxBody)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                    }
                }
            }
            .padding(DesignSystem.Spacing.lg)
        }
    }
}

/// What happened.
struct HistoryImportResultContent: View {
    let result: HistoryImportResult
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.tint)
            Text("history_import.result.title".localized)
                .font(.onyxTitle2)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            if result.importedWorkoutCount == 0 {
                Text("history_import.result.none".localized)
                    .font(.onyxBody)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            OnyxCard {
                VStack(spacing: DesignSystem.Spacing.md) {
                    HistoryImportCountRow(label: "history_import.result.imported".localized, value: result.importedWorkoutCount)
                    HistoryImportCountRow(label: "history_import.result.duplicates".localized, value: result.skippedDuplicateCount)
                    HistoryImportCountRow(label: "history_import.result.exercises".localized, value: result.createdExerciseCount)
                    if result.skippedCardioSetCount > 0 {
                        HistoryImportCountRow(label: "history_import.preview.cardio".localized, value: result.skippedCardioSetCount)
                    }
                }
            }
            OnyxButton("history_import.done".localized, action: onDone)
        }
        .padding(DesignSystem.Spacing.xl)
    }
}

private struct HistoryImportCountRow: View {
    let label: String
    let value: Int

    var body: some View {
        HistoryImportTextRow(label: label, value: value.formatted())
    }
}

private struct HistoryImportTextRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.onyxBody)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Spacer(minLength: DesignSystem.Spacing.md)
            Text(value)
                .font(.onyxNumber)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
