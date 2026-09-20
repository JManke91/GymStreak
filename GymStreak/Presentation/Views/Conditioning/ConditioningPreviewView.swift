//
//  ConditioningPreviewView.swift
//  GymStreak
//
//  Configure and preview one session: modality, volume, the beginner
//  sub-maximal variant, and the resulting structure. See
//  docs/fight-conditioning.md.
//

import SwiftUI

struct ConditioningPreviewView: View {
    let definition: ConditioningSessionDefinition
    let viewModel: ConditioningLibraryViewModel

    @State private var modality: ConditioningModality
    @State private var volume: Int
    @State private var isSubMaximal = false
    @State private var preview: ConditioningPreview?
    @State private var heartRateEditor: HeartRateProfileEditorViewModel?

    /// - Parameter initialOptions: a program target's volume; the lowest option otherwise.
    init(
        definition: ConditioningSessionDefinition,
        viewModel: ConditioningLibraryViewModel,
        initialOptions: ConditioningSessionOptions? = nil
    ) {
        self.definition = definition
        self.viewModel = viewModel
        _modality = State(initialValue: definition.modalities.first ?? .run)
        _volume = State(initialValue: initialOptions?.volume ?? definition.defaultVolume)
        _isSubMaximal = State(initialValue: initialOptions?.isSubMaximal ?? false)
    }

    private var plan: ConditioningSessionPlan {
        ConditioningSessionPlan(
            definition: definition,
            options: ConditioningSessionOptions(volume: volume, isSubMaximal: isSubMaximal),
            modality: modality
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                Text(ConditioningCopy.summary(definition.id))
                    .font(.onyxBody)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                modalitySection
                volumeSection
                if definition.supportsSubMaximal {
                    subMaximalSection
                }
                ConditioningHeartRateCard(
                    guidance: viewModel.heartRateGuidance(for: definition),
                    onEdit: { heartRateEditor = viewModel.makeHeartRateEditor() }
                )
                structureSection

                Button {
                    HapticManager.shared.medium()
                    viewModel.start(plan)
                } label: {
                    Text("conditioning.preview.start".localized)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DesignSystem.Dimensions.buttonHeight - 24)
                }
                .buttonStyle(.onyxProminent)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.xxl)
        }
        .background(DesignSystem.Colors.background.ignoresSafeArea())
        .navigationTitle(ConditioningCopy.title(definition.id))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $heartRateEditor) { editor in
            HeartRateProfileSheet(viewModel: editor)
        }
        .onAppear { preview = viewModel.preview(for: plan) }
        .onChange(of: plan) { _, newPlan in preview = viewModel.preview(for: newPlan) }
    }

    // MARK: - Sections

    private var modalitySection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionLabel("conditioning.preview.modality".localized)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(definition.modalities) { option in
                        modalityChip(option)
                    }
                }
            }
        }
    }

    private func modalityChip(_ option: ConditioningModality) -> some View {
        let isSelected = option == modality
        return Button {
            HapticManager.shared.selection()
            modality = option
        } label: {
            Label(ConditioningCopy.modality(option), systemImage: ConditioningCopy.modalitySymbol(option))
                .font(.onyxSubheadline)
                .foregroundStyle(isSelected ? DesignSystem.Colors.textOnTint : DesignSystem.Colors.textPrimary)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    Capsule().fill(isSelected ? DesignSystem.Colors.tint : DesignSystem.Colors.card)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionLabel(volumeLabel)
            Picker(volumeLabel, selection: $volume) {
                ForEach(definition.volume.options, id: \.self) { option in
                    Text(volumeOptionText(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var volumeLabel: String {
        switch definition.volume {
        case .minutes: "conditioning.preview.duration".localized
        case .rounds: "conditioning.preview.rounds".localized
        case .sets: "conditioning.preview.sets_label".localized
        }
    }

    private func volumeOptionText(_ option: Int) -> String {
        if case .minutes = definition.volume {
            return "conditioning.unit.minutes".localized(option)
        }
        return "\(option)"
    }

    private var subMaximalSection: some View {
        OnyxCard {
            Toggle(isOn: $isSubMaximal) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("conditioning.preview.submaximal.title".localized)
                        .font(.onyxSubheadline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("conditioning.preview.submaximal.detail".localized)
                        .font(.onyxFootnote)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(DesignSystem.Colors.tint)
        }
    }

    private var structureSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionLabel("conditioning.preview.structure".localized)
            OnyxCard {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    if let preview {
                        ForEach(preview.blocks) { block in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(block.title)
                                    .font(.onyxSubheadline)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                if let detail = block.detail {
                                    Text(detail)
                                        .font(.onyxFootnote)
                                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                                }
                            }
                        }
                        Divider().overlay(DesignSystem.Colors.divider)
                        HStack {
                            Text("conditioning.preview.total".localized)
                                .font(.onyxSubheadline)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                            Spacer()
                            Text(ConditioningCopy.clock(preview.totalDuration))
                                .font(.onyxNumber)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.onyxMonoLabel)
            .kerning(0.7)
            .foregroundStyle(DesignSystem.Colors.textTertiary)
    }
}
