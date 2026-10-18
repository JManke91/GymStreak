//
//  MatSessionLogView.swift
//  GymStreak
//
//  "Log a mat session" — presented as a sheet from the Conditioning screen.
//  Records training load only: sport, when, how long, how hard, a note.
//  See docs/fight-conditioning.md.
//

import SwiftUI

struct MatSessionLogView: View {
    @State private var viewModel: MatSessionLogViewModel
    @Environment(\.dismiss) private var dismiss
    /// Called when the user taps Save — the round timer uses it to offer the
    /// save once. Cancelling calls nothing.
    private let onSave: (() -> Void)?

    init(viewModel: MatSessionLogViewModel, onSave: (() -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                    sportSection
                    intensitySection
                    timeSection
                    noteSection
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DesignSystem.Colors.background.ignoresSafeArea())
            .navigationTitle("mat.log.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel".localized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save".localized) {
                        HapticManager.shared.success()
                        // The History record is written before the first suspension; the
                        // Apple Health write finishes after the sheet is gone.
                        let viewModel = viewModel
                        Task { await viewModel.save() }
                        onSave?()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Sections

    private var sportSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionLabel("mat.log.sport".localized)
            ScrollView(.horizontal, showsIndicators: false) {
                // Six fixed options — a plain stack is fine.
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(MatSport.allCases) { sport in
                        sportChip(sport)
                    }
                }
            }
        }
    }

    private func sportChip(_ sport: MatSport) -> some View {
        let isSelected = sport == viewModel.sport
        return Button {
            HapticManager.shared.selection()
            viewModel.sport = sport
        } label: {
            Label(MatSessionCopy.sport(sport), systemImage: MatSessionCopy.sportSymbol(sport))
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

    private var intensitySection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionLabel("mat.log.intensity".localized)
            Picker("mat.log.intensity".localized, selection: $viewModel.intensity) {
                ForEach(MatIntensity.allCases) { intensity in
                    Text(MatSessionCopy.intensity(intensity)).tag(intensity)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var timeSection: some View {
        OnyxCard {
            VStack(spacing: DesignSystem.Spacing.md) {
                Stepper(
                    value: $viewModel.durationMinutes,
                    in: MatSessionLogViewModel.durationRange,
                    step: MatSessionLogViewModel.durationStep
                ) {
                    HStack {
                        Text("mat.log.duration".localized)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        Spacer()
                        Text("conditioning.unit.minutes".localized(viewModel.durationMinutes))
                            .monospacedDigit()
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
                Divider()
                DatePicker(
                    "mat.log.start".localized,
                    selection: startBinding,
                    in: ...viewModel.openedAt
                )
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
            .font(.onyxSubheadline)
        }
    }

    /// Writing through `editedStartDate` is what stops the start following the duration.
    private var startBinding: Binding<Date> {
        Binding(
            get: { viewModel.startDate },
            set: { viewModel.editedStartDate = $0 }
        )
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionLabel("mat.log.note".localized)
            TextField("mat.log.note.placeholder".localized, text: $viewModel.note, axis: .vertical)
                .lineLimit(2...5)
                .font(.onyxSubheadline)
                .padding(DesignSystem.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DesignSystem.Colors.card)
                )
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.onyxMonoLabel)
            .kerning(0.7)
            .foregroundStyle(DesignSystem.Colors.textTertiary)
    }
}
