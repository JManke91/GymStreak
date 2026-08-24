//
//  ExerciseUsageMenu.swift
//  GymStreak
//
//  The exercise detail screen's usage picker (2026-08-23): which way of training this
//  exercise the chart and the recent-sets list describe.
//

import SwiftUI

/// Picks the routine slot the exercise detail screen charts.
///
/// Sits next to the exercise switcher and mirrors its chrome, because the two answer the
/// same shape of question — *what* am I looking at — and a user who trains one exercise
/// two ways switches between them as often as between exercises.
///
/// Only rendered when there is more than one usage (`ExerciseProgressViewModel
/// .showsUsagePicker`); with a single usage the menu's one entry would chart exactly
/// what is already on screen.
struct ExerciseUsageMenu: View {
    /// Already labelled and de-duplicated by the view model — no string building here.
    let options: [ExerciseUsagePickerItem]
    let selection: ExerciseUsageSelection
    let selectedLabel: String
    let onSelect: (ExerciseUsageSelection) -> Void

    var body: some View {
        Menu {
            Section("chart.usage.title".localized) {
                ForEach(options) { option in
                    Button {
                        onSelect(.usage(option.key))
                    } label: {
                        menuRow(title: option.label, isSelected: selection == .usage(option.key))
                    }
                }
                // Last, not first: the combined view is the one that mixes two different
                // pieces of work into one line, so it is offered rather than suggested.
                Button {
                    onSelect(.combined)
                } label: {
                    menuRow(title: "chart.usage.combined".localized, isSelected: selection == .combined)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 12, weight: .semibold))
                Text(selectedLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .frame(maxWidth: 150)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel("chart.usage.a11y".localized(selectedLabel))
    }

    private func menuRow(title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
            if isSelected {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }
}
