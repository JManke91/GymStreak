//
//  HistoryImportSummaryContent.swift
//  GymStreak
//
//  The result screen of the history import, and the label/value rows it shares with
//  the preview (`HistoryImportPreviewContent`). Counts are label/value rows so no
//  string needs plural rules.
//

import SwiftUI

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

struct HistoryImportCountRow: View {
    let label: String
    let value: Int

    var body: some View {
        HistoryImportTextRow(label: label, value: value.formatted())
    }
}

struct HistoryImportTextRow: View {
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
