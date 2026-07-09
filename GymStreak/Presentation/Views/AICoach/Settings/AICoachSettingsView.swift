//
//  AICoachSettingsView.swift
//  GymStreak
//
//  AI Coach settings screen pushed from the History tab gear icon.
//  Custom list groups match the design reference (ScreenSettings) — not a stock SwiftUI Form.
//

import SwiftUI

/// Settings screen for the AI Coach feature.
///
/// Reads and writes `AICoachPreferences.shared` via `@Bindable`.
/// Queries `AICoachAvailability.shared` on appear to determine whether
/// the device can run Apple Intelligence.
struct AICoachSettingsView: View {

    // MARK: - Dependencies

    @State private var preferences = AICoachPreferences.shared
    @State private var availability = AICoachAvailability.shared

    @State private var showHowItWorksSheet = false

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(red: 10/255, green: 10/255, blue: 10/255).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // MARK: Hero
                    heroHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 18)

                    // MARK: Unavailability banner
                    if !availability.isAvailable {
                        unavailabilityBanner
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }

                    // MARK: Coach section
                    sectionHeader("ai_coach.settings.section.coach".localized)
                    settingsGroup {
                        masterToggleRow
                    }

                    // MARK: Surfaces section
                    sectionHeader("ai_coach.settings.section.surfaces".localized)
                        .padding(.top, 22)
                    settingsGroup {
                        surfaceToggleRow(
                            icon: "figure.strengthtraining.traditional",
                            title: "ai_coach.settings.surface.post_workout.title".localized,
                            detail: "ai_coach.settings.surface.post_workout.detail".localized,
                            isEnabled: masterActive,
                            binding: bindable.postWorkoutRecapEnabled
                        )

                        Divider()
                            .background(Color.white.opacity(0.06))
                            .padding(.horizontal, 16)

                        surfaceToggleRow(
                            icon: "calendar",
                            title: "ai_coach.settings.surface.monthly.title".localized,
                            detail: "ai_coach.settings.surface.monthly.detail".localized,
                            isEnabled: masterActive,
                            binding: bindable.periodRecapEnabled
                        )

                        Divider()
                            .background(Color.white.opacity(0.06))
                            .padding(.horizontal, 16)

                        surfaceToggleRow(
                            icon: "dumbbell.fill",
                            title: "ai_coach.settings.surface.exercise.title".localized,
                            detail: "ai_coach.settings.surface.exercise.detail".localized,
                            isEnabled: masterActive,
                            binding: bindable.exerciseDeepDiveEnabled
                        )

                        Divider()
                            .background(Color.white.opacity(0.06))
                            .padding(.horizontal, 16)

                        surfaceToggleRow(
                            icon: "list.bullet.rectangle",
                            title: "ai_coach.settings.surface.workout_detail.title".localized,
                            detail: "ai_coach.settings.surface.workout_detail.detail".localized,
                            isEnabled: masterActive,
                            isLast: true,
                            binding: bindable.workoutDetailEnabled
                        )
                    }

                    // MARK: Experimental section
                    sectionHeader("ai_coach.settings.section.experimental".localized)
                        .padding(.top, 22)
                    settingsGroup {
                        surfaceToggleRow(
                            icon: "bubble.left.and.text.bubble.right",
                            title: "ai_coach.chat.experimental.title".localized,
                            detail: "ai_coach.chat.experimental.detail".localized,
                            isEnabled: masterActive,
                            isLast: !preferences.isChatExperimentalEffectivelyEnabled,
                            binding: bindable.chatExperimentalEnabled
                        )

                        if preferences.isChatExperimentalEffectivelyEnabled {
                            Divider()
                                .background(Color.white.opacity(0.06))
                                .padding(.horizontal, 16)

                            NavigationLink {
                                CoachChatView()
                            } label: {
                                navRow(
                                    title: "ai_coach.chat.entry.title".localized,
                                    isLast: true
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("ai_coach.chat.entry.title".localized)
                        }
                    }

                    // MARK: Info section
                    sectionHeader("ai_coach.settings.section.info".localized)
                        .padding(.top, 22)
                    settingsGroup {
                        Button {
                            showHowItWorksSheet = true
                        } label: {
                            navRow(
                                title: "ai_coach.settings.info.how_it_works.title".localized
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("ai_coach.settings.info.how_it_works.title".localized)

                        Divider()
                            .background(Color.white.opacity(0.06))
                            .padding(.horizontal, 16)

                        Button {
                            openAppleIntelligenceSupport()
                        } label: {
                            navRow(
                                title: "ai_coach.settings.info.apple_intelligence.title".localized,
                                isLast: true
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("ai_coach.settings.info.apple_intelligence.title".localized)
                    }

                    // MARK: Footer disclaimer
                    Text("ai_coach.settings.footer".localized)
                        .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineSpacing(3.5)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 60)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            await availability.refresh()
        }
        .sheet(isPresented: $showHowItWorksSheet) {
            HowItWorksSheet()
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            AISparkleView(size: 26, glow: availability.isAvailable)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("ai_coach.settings.hero.title".localized)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.white)
                    .kerning(-0.5)

                Text(availability.isAvailable
                     ? "ai_coach.settings.hero.subtitle.active".localized
                     : "ai_coach.settings.hero.subtitle.unavailable".localized)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
    }

    // MARK: - Unavailability Banner

    private var unavailabilityBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ai_coach.settings.unavailable_banner.body".localized)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.7))
                .lineSpacing(3)

            Button {
                openAppleIntelligenceSupport()
            } label: {
                Text("ai_coach.settings.unavailable_banner.cta".localized)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mehr über Apple Intelligence erfahren – öffnet Apple Support")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Master Toggle Row

    private var masterToggleRow: some View {
        HStack(spacing: 12) {
            iconBadge { AISparkleView(size: 14) }

            VStack(alignment: .leading, spacing: 2) {
                Text("ai_coach.settings.master_toggle.title".localized)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white)

                Text(availability.isAvailable
                     ? "ai_coach.settings.master_toggle.detail.active".localized
                     : "ai_coach.settings.master_toggle.detail.unavailable".localized)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.45))
            }

            Spacer()

            Toggle("", isOn: bindable.isMasterEnabled)
                .labelsHidden()
                .tint(DesignSystem.Colors.tint)
                .disabled(!availability.isAvailable)
                .accessibilityLabel("AI Coach aktivieren")
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 16)
        .opacity(availability.isAvailable ? 1.0 : 0.55)
    }

    // MARK: - Surface Toggle Row

    private func surfaceToggleRow(
        icon: String,
        title: String,
        detail: String,
        isEnabled: Bool,
        isLast: Bool = false,
        binding: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            iconBadge {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white)

                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.45))
            }

            Spacer()

            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(DesignSystem.Colors.tint)
                .disabled(!isEnabled)
                .accessibilityLabel(title)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 16)
        .opacity(isEnabled ? 1.0 : 0.55)
    }

    // MARK: - Nav Row

    private func navRow(title: String, isLast: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Color.white)
                .padding(.vertical, 13)
                .padding(.leading, 16)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.3))
                .padding(.trailing, 16)
        }
    }

    // MARK: - Helpers

    /// Whether the AI Coach is both available and opted-in + master-on.
    private var masterActive: Bool {
        availability.isAvailable && preferences.isMasterEnabled && preferences.hasCompletedOptIn
    }

    /// @Bindable wrapper for the preferences singleton.
    private var bindable: Bindable<AICoachPreferences> {
        Bindable(preferences)
    }

    @ViewBuilder
    private func iconBadge<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(DesignSystem.Colors.tint.opacity(0.12))
                .frame(width: 28, height: 28)

            content()
                .frame(width: 18, height: 18)
        }
        .accessibilityHidden(true)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(Color.white.opacity(0.4))
            .padding(.leading, 22)
            .padding(.bottom, 6)
    }

    @ViewBuilder
    private func settingsGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func openAppleIntelligenceSupport() {
        guard let url = URL(string: "https://support.apple.com/en-us/111900") else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - How It Works Sheet (TODO Wave 3)

/// Placeholder "Wie der Coach funktioniert" sheet.
/// Wave 3 will replace this with the full explanation content.
private struct HowItWorksSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()

            VStack(spacing: 20) {
                AISparkleView(size: 48, glow: true)
                    .accessibilityHidden(true)

                Text("ai_coach.how_it_works.title".localized)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)

                // TODO Wave 3: Replace with full explanation content
                Text("Dieser Bereich erklärt, wie der AI Coach deine Workout-Daten on-device analysiert und Rückblicke generiert.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                Button("Schließen") { dismiss() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.tint)
                    .padding(.bottom, 40)
            }
            .padding(.top, 60)
        }
        .presentationBackground(DesignSystem.Colors.background)
    }
}

// MARK: - Preview

#Preview("Settings – available") {
    NavigationStack {
        AICoachSettingsView()
    }
    .preferredColorScheme(.dark)
}
