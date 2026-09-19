//
//  HeartRateProfileView.swift
//  GymStreak
//
//  Edit the conditioning heart-rate profile. Pushed from Settings and presented
//  as a sheet from a session preview (`HeartRateProfileSheet`).
//  See docs/fight-conditioning.md.
//

import SwiftUI

struct HeartRateProfileView: View {
    @State private var viewModel: HeartRateProfileEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditingNumber: Bool

    init(viewModel: HeartRateProfileEditorViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                maxSection
                restingSection
                if viewModel.canPrefillFromHealth {
                    healthSection
                }
                medicationSection
                resultSection
            }
            .padding(.top, DesignSystem.Spacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DesignSystem.Colors.background.ignoresSafeArea())
        .navigationTitle("conditioning.hr.title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("action.save".localized) {
                    if viewModel.save() { dismiss() }
                }
                .disabled(!viewModel.canSave)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("action.done".localized) { isEditingNumber = false }
            }
        }
    }

    // MARK: - Sections

    private var maxSection: some View {
        SettingsSectionView(
            header: "conditioning.hr.section.max".localized,
            footer: maxFooter
        ) {
            Picker("conditioning.hr.section.max".localized, selection: $viewModel.draft.maxSource) {
                Text("conditioning.hr.source.age".localized).tag(HeartRateProfile.MaxHeartRateSource.estimatedFromAge)
                Text("conditioning.hr.source.measured".localized).tag(HeartRateProfile.MaxHeartRateSource.measured)
            }
            .pickerStyle(.segmented)
            .padding(DesignSystem.Spacing.md)

            if viewModel.draft.maxSource == .estimatedFromAge {
                numberRow(title: "conditioning.hr.age".localized, unit: nil, value: \.age, isLast: true)
            } else {
                numberRow(title: "conditioning.hr.max".localized, unit: "conditioning.hr.bpm".localized,
                          value: \.measuredMaxHeartRate, isLast: true)
            }
        }
    }

    private var maxFooter: String {
        guard viewModel.draft.maxSource == .estimatedFromAge else {
            return "conditioning.hr.max.footer_measured".localized
        }
        guard let estimate = viewModel.estimatedMaxHeartRate, HeartRateZones.ageRange.contains(viewModel.draft.age ?? 0) else {
            return "conditioning.hr.max.footer_age".localized(HeartRateZones.estimateUncertainty)
        }
        return "conditioning.hr.max.footer_estimate".localized(estimate, HeartRateZones.estimateUncertainty)
    }

    private var restingSection: some View {
        SettingsSectionView(
            header: "conditioning.hr.section.resting".localized,
            footer: "conditioning.hr.resting.footer".localized
        ) {
            numberRow(title: "conditioning.hr.resting".localized, unit: "conditioning.hr.bpm".localized,
                      value: \.restingHeartRate, isLast: true)
        }
    }

    private var healthSection: some View {
        SettingsSectionView(footer: healthFooter) {
            SettingsActionRowView(
                icon: "heart.text.square",
                iconTint: DesignSystem.Colors.destructive,
                title: "conditioning.hr.health.title".localized,
                subtitle: "conditioning.hr.health.subtitle".localized,
                showsChevron: false,
                isLast: viewModel.suggestedMaxHeartRate == nil
            ) {
                Task { await viewModel.prefillFromHealth() }
            }
            .disabled(viewModel.prefillState == .reading)

            if let peak = viewModel.suggestedMaxHeartRate {
                SettingsRowView(
                    title: "conditioning.hr.peak.title".localized(peak),
                    subtitle: "conditioning.hr.peak.subtitle".localized(HeartRateZones.peakLookbackMonths),
                    isLast: true
                ) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Button("conditioning.hr.peak.dismiss".localized, action: viewModel.dismissSuggestedMax)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        Button("conditioning.hr.peak.use".localized, action: viewModel.useSuggestedMax)
                            .fontWeight(.semibold)
                            .foregroundStyle(DesignSystem.Colors.tint)
                    }
                    .font(.onyxSubheadline)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var healthFooter: String {
        if viewModel.suggestedMaxHeartRate != nil {
            return "conditioning.hr.peak.footer".localized
        }
        return switch viewModel.prefillState {
        case .idle, .reading: "conditioning.hr.health.footer".localized
        case .filled: "conditioning.hr.health.filled".localized
        case .nothingFound: "conditioning.hr.health.nothing".localized
        }
    }

    private var medicationSection: some View {
        SettingsSectionView(footer: "conditioning.hr.medication.footer".localized) {
            SettingsRowView(
                icon: "pills",
                title: "conditioning.hr.medication.title".localized,
                isLast: true
            ) {
                Toggle("", isOn: $viewModel.draft.usesHeartRateMedication)
                    .labelsHidden()
                    .tint(DesignSystem.Colors.tint)
            }
        }
    }

    private var resultSection: some View {
        SettingsSectionView(header: "conditioning.hr.section.zone".localized) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                if viewModel.draft.usesHeartRateMedication {
                    Text("conditioning.hr.rpe_only".localized)
                        .font(.onyxSubheadline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                } else if let target = viewModel.aerobicTarget {
                    Text(ConditioningCopy.heartRateRange(target))
                        .font(.onyxNumber)
                        .foregroundStyle(DesignSystem.Colors.tint)
                    Text("conditioning.hr.zone.aerobic".localized(ConditioningCopy.heartRateBasis(target)))
                        .font(.onyxFootnote)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                } else {
                    ForEach(viewModel.issues, id: \.self) { issue in
                        Text(ConditioningCopy.heartRateIssue(issue))
                            .font(.onyxFootnote)
                            .foregroundStyle(DesignSystem.Colors.warning)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSystem.Spacing.md)
        }
    }

    // MARK: - Number input

    /// A string-backed field so every keystroke lands in the draft at once —
    /// `TextField(value:format:)` commits only on focus loss, which a Save tap
    /// in the toolbar would race.
    private func numberRow(
        title: String,
        unit: String?,
        value: WritableKeyPath<HeartRateProfile, Int?>,
        isLast: Bool
    ) -> some View {
        SettingsRowView(title: title, isLast: isLast) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                TextField("—", text: Binding(
                    get: { viewModel.draft[keyPath: value].map(String.init) ?? "" },
                    set: { viewModel.draft[keyPath: value] = Int($0.filter(\.isNumber).prefix(3)) }
                ))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.onyxNumber)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(width: 64)
                .focused($isEditingNumber)
                if let unit {
                    Text(unit)
                        .font(.onyxFootnote)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
    }
}

/// The editor as a modal from a session preview: its own navigation bar with Cancel.
struct HeartRateProfileSheet: View {
    let viewModel: HeartRateProfileEditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HeartRateProfileView(viewModel: viewModel)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("action.cancel".localized) { dismiss() }
                    }
                }
        }
    }
}
