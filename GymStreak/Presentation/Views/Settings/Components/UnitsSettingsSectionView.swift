//
//  UnitsSettingsSectionView.swift
//  GymStreak
//
//  Settings section for display units — currently just the weight unit.
//  See docs/weight-unit-preference.md.
//

import SwiftUI

/// Kilograms or pounds, for everything the app shows and everything the user
/// types. Nothing is rewritten in the store when this changes: kilograms stay
/// the canonical unit, so switching back restores exactly the old numbers.
struct UnitsSettingsSectionView: View {

    let preference: any WeightUnitPreferenceProviding

    var body: some View {
        SettingsSectionView(
            header: "settings.section.units".localized,
            footer: "settings.section.units.footer".localized
        ) {
            SettingsRowView(
                icon: "scalemass",
                title: "settings.units.weight.row.title".localized,
                subtitle: "settings.units.weight.row.subtitle".localized,
                isLast: true
            ) {
                Picker("", selection: selection) {
                    ForEach(WeightUnit.allCases, id: \.self) { unit in
                        Text(WeightFormatting.unitName(unit)).tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(DesignSystem.Colors.tint)
                .accessibilityIdentifier("settings-weight-unit-picker")
            }
        }
    }

    private var selection: Binding<WeightUnit> {
        Binding(
            get: { preference.weightUnit },
            set: { preference.weightUnit = $0 }
        )
    }
}

// MARK: - Preview

#Preview("Units") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        // A throwaway suite, not `.shared`: a preview must not seed the unit
        // into the real `UserDefaults` and thereby make a first-launch decision.
        UnitsSettingsSectionView(
            preference: WeightUnitPreference(
                defaults: UserDefaults(suiteName: "preview.units")!
            )
        )
    }
    .preferredColorScheme(.dark)
}
