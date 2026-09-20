//
//  ConditioningProgramTodayCard.swift
//  GymStreak
//
//  "Today's conditioning" and the weekly target row of the program screen.
//  Value input only. See docs/fight-conditioning.md.
//

import SwiftUI

struct ConditioningProgramTodayCard: View {
    let suggestion: ConditioningTodaySuggestion
    let onStart: (ConditioningProgramTarget) -> Void

    var body: some View {
        OnyxCard(isHighlighted: true) {
            switch suggestion {
            case .session(let target, let cautions):
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(ConditioningCopy.title(target.session))
                            .font(.onyxTitle2)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        Spacer()
                        Text(ConditioningProgramCopy.volume(target))
                            .font(.onyxNumber)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                    Text(ConditioningCopy.summary(target.session))
                        .font(.onyxFootnote)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(cautions, id: \.self) { caution in
                        Label(ConditioningProgramCopy.caution(caution), systemImage: "exclamationmark.triangle.fill")
                            .font(.onyxFootnote)
                            .foregroundStyle(DesignSystem.Colors.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        HapticManager.shared.light()
                        onStart(target)
                    } label: {
                        Text("conditioning.program.today.open".localized)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.onyxProminent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .rest(let reason):
                HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(DesignSystem.Colors.tint)
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text(ConditioningProgramCopy.restTitle(reason))
                            .font(.onyxHeader)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        Text(ConditioningProgramCopy.restDetail(reason))
                            .font(.onyxFootnote)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct ConditioningTargetProgressRow: View {
    let progress: ConditioningTargetProgress

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ConditioningCopy.title(progress.target.session))
                    .font(.onyxSubheadline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text(ConditioningProgramCopy.volume(progress.target))
                    .font(.onyxFootnote)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(0..<progress.target.count, id: \.self) { index in
                    Circle()
                        .fill(index < progress.completed ? DesignSystem.Colors.tint : DesignSystem.Colors.divider)
                        .frame(width: 10, height: 10)
                }
            }
            Text("conditioning.program.target.progress".localized(progress.completed, progress.target.count))
                .font(.onyxNumberSmall)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
