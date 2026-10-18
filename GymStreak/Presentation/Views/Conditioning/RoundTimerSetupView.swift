//
//  RoundTimerSetupView.swift
//  GymStreak
//
//  The round timer's setup: a sport preset, the rounds, the warning, Start.
//  Pushed from the Conditioning screen; the run itself is a full-screen cover.
//  Free by Rule 3 — no Pro surface anywhere in the timer.
//  See docs/fight-conditioning.md, "Round timer".
//

import SwiftUI

struct RoundTimerSetupView: View {
    @State private var viewModel: RoundTimerSetupViewModel

    init(viewModel: RoundTimerSetupViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                presetSection
                settingsCard
                summary
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
        }
        .background(DesignSystem.Colors.background.ignoresSafeArea())
        .navigationTitle("roundtimer.title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { startButton }
        .fullScreenCover(item: $viewModel.activeRun) { run in
            RoundTimerRunnerView(viewModel: run)
        }
    }

    // MARK: - Presets

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionLabel("roundtimer.setup.preset".localized)
            ScrollView(.horizontal, showsIndicators: false) {
                // Five fixed options — a plain stack is fine.
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(RoundTimerPreset.allCases) { preset in
                        presetChip(preset)
                    }
                }
            }
        }
    }

    private func presetChip(_ preset: RoundTimerPreset) -> some View {
        let isSelected = preset == viewModel.configuration.preset
        return Button {
            HapticManager.shared.selection()
            viewModel.select(preset)
        } label: {
            VStack(spacing: 2) {
                Label(RoundTimerCopy.preset(preset), systemImage: RoundTimerCopy.presetSymbol(preset))
                    .font(.onyxSubheadline)
                if let round = preset.roundDuration, let rest = preset.restDuration {
                    Text("\(ConditioningCopy.clock(round)) / \(ConditioningCopy.clock(rest))")
                        .font(.onyxFootnote)
                        .monospacedDigit()
                        .opacity(0.8)
                }
            }
            .foregroundStyle(isSelected ? DesignSystem.Colors.textOnTint : DesignSystem.Colors.textPrimary)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? DesignSystem.Colors.tint : DesignSystem.Colors.card)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Settings

    private var settingsCard: some View {
        OnyxCard {
            VStack(spacing: DesignSystem.Spacing.md) {
                durationRow(
                    "roundtimer.setup.round".localized,
                    value: $viewModel.configuration.customRoundDuration,
                    shown: viewModel.configuration.roundDuration,
                    range: RoundTimerConfiguration.roundDurationRange,
                    step: 30
                )
                Divider()
                durationRow(
                    "roundtimer.setup.rest".localized,
                    value: $viewModel.configuration.customRestDuration,
                    shown: viewModel.configuration.restDuration,
                    range: RoundTimerConfiguration.restDurationRange,
                    step: 15
                )
                Divider()
                if !viewModel.isOpenEnded {
                    Stepper(value: $viewModel.rounds, in: RoundTimerConfiguration.roundsRange) {
                        valueLabel("roundtimer.setup.rounds".localized, value: "\(viewModel.rounds)")
                    }
                }
                Toggle("roundtimer.setup.open_ended".localized, isOn: $viewModel.isOpenEnded)
                    .tint(DesignSystem.Colors.tint)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Divider()
                Stepper(
                    value: $viewModel.configuration.warning,
                    in: RoundTimerConfiguration.warningRange,
                    step: 5
                ) {
                    valueLabel(
                        "roundtimer.setup.warning".localized,
                        value: RoundTimerCopy.warning(viewModel.configuration.warning)
                    )
                }
            }
            .font(.onyxSubheadline)
        }
    }

    /// Editable for the custom preset; a fixed value for the sport presets.
    @ViewBuilder
    private func durationRow(
        _ title: String,
        value: Binding<TimeInterval>,
        shown: TimeInterval,
        range: ClosedRange<TimeInterval>,
        step: TimeInterval
    ) -> some View {
        if viewModel.isCustom {
            Stepper(value: value, in: range, step: step) {
                valueLabel(title, value: ConditioningCopy.clock(shown))
            }
        } else {
            valueLabel(title, value: ConditioningCopy.clock(shown))
        }
    }

    private func valueLabel(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(RoundTimerCopy.summary(viewModel.configuration))
                .font(.onyxSubheadline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Text("roundtimer.setup.save_hint".localized)
                .font(.onyxFootnote)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var startButton: some View {
        Button {
            HapticManager.shared.medium()
            viewModel.start()
        } label: {
            Label("roundtimer.setup.start".localized, systemImage: "play.fill")
                .frame(maxWidth: .infinity, minHeight: DesignSystem.Dimensions.buttonHeight - 24)
        }
        .buttonStyle(.onyxProminent)
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.background.ignoresSafeArea())
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.onyxMonoLabel)
            .kerning(0.7)
            .foregroundStyle(DesignSystem.Colors.textTertiary)
    }
}
