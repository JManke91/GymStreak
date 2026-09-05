//
//  OnboardingHistorySlideView.swift
//  GymStreak
//
//  Step 5 of the first-run tour: what a session looks like once it is logged.
//  See docs/onboarding.md.
//

import SwiftUI

extension OnboardingFeatureSlideContent {

    static let history = OnboardingFeatureSlideContent(
        breadcrumbKey: "onboarding.history.breadcrumb",
        eyebrowKey: "onboarding.history.eyebrow",
        titleKey: "onboarding.history.title",
        bodyKey: "onboarding.history.body",
        bulletKeys: [
            "onboarding.history.bullet1",
            "onboarding.history.bullet2"
        ],
        // The first slide of the tour that carries the marker. It advertises
        // Pro; it gates nothing — see the copy note in docs/onboarding.md, which
        // is why the body says out loud which half of this screen is free.
        showsProBadge: true,
        // Measured, like step 4's, rather than rounded: the header, the stat
        // grid, the exercise block and the two 16 pt gaps between them, plus the
        // panel's breadcrumb and padding. The block is the point of the slide —
        // the per-set chips are the last thing in it — so it must be whole, and
        // a fade would land exactly on them. It is measured against the *worst*
        // case, a 390 pt phone in German, where the third set's "−1 Wdh." chip
        // takes two lines and the grid is ~20 pt taller than it is at 402 pt.
        plateHeight: 462,
        plateFadesOutBottom: false,
        // Same escape hatch step 4 needed, for the same reason: four stat tiles
        // and a four-cell set grid are the two densest rows the app draws, and
        // at the default inset both broke on a 390 pt phone — the intensity
        // label ellipsised and the "+2,5 kg" delta chip wrapped mid-figure. Four
        // points still reads as a panel with something laid on it, and the
        // breadcrumb keeps the full inset either way.
        plateContentInset: 4
    )
}

/// The "History" slide: one recorded session, above the copy.
struct OnboardingHistorySlideView: View {

    var body: some View {
        OnboardingFeatureSlideView(content: .history) {
            OnboardingHistoryPreview()
        }
    }
}

// MARK: - The preview inside the plate

/// The top of a workout-detail screen: the session header, the four stat tiles
/// and the first exercise block, with its record, its comparison strip and its
/// per-set deltas.
///
/// All three are the production views — `WorkoutSessionHeaderView`,
/// `WorkoutStatGrid` and `WorkoutDetailExerciseBlock`, the first two extracted
/// out of `WorkoutDetailView` by ticket 02 for exactly this. Nothing is redrawn
/// here, and nothing in them acts on appear, so the slide needs no guard of its
/// own beyond the plate's inert mount.
///
/// What is *not* shown: the "Exercises" section heading above the blocks, the
/// muscle-map card and the remaining two exercises of the session. The plate is
/// a slice of the screen, and those are the parts a reader learns nothing from
/// at a third of their real width.
private struct OnboardingHistoryPreview: View {

    @Environment(\.weightUnit) private var weightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            WorkoutSessionHeaderView(
                type: OnboardingSampleHistory.workoutType,
                dateText: Self.dateText,
                title: OnboardingSampleHistory.routineName
            )
            // The real screen holds its header 20 pt off the edge and the
            // sections below it 16 pt. The plate supplies the 16; this is the
            // difference, so the rhythm inside the panel is the screen's.
            .padding(.horizontal, 4)

            WorkoutStatGrid(
                // The screen's own format — a bare minute count with an "m" —
                // reproduced rather than reinvented, because `WorkoutStatGrid`
                // takes pre-formatted strings by design (ticket 02).
                durationText: "\(Int(OnboardingSampleHistory.duration / 60))m",
                setsText: "\(OnboardingSampleHistory.sessionSetCount)",
                volumeText: WeightFormatting.volume(
                    OnboardingSampleHistory.sessionVolumeKilograms,
                    in: weightUnit
                ),
                intensityText: "\(OnboardingSampleHistory.completionPercentage)"
            )
            // The German "INTENSITÄT" is one word wider than a quarter of this
            // plate, and a word with no break opportunity does not wrap politely
            // — the tile split it mid-word ("INTENSIT / ÄT") or ellipsised it,
            // depending on how much vertical room was left. Both modifiers reach
            // the tiles' `Text`s through the environment, so the shipped
            // component is untouched and the values, which fit, never scale.
            // The reduced `plateContentInset` alone was not enough at 390 pt.
            // See docs/onboarding.md for the finding this is working around.
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            WorkoutDetailExerciseBlock(
                display: OnboardingSampleHistory.exerciseDisplay,
                prDetail: OnboardingSampleHistory.prDetail,
                comparison: OnboardingSampleHistory.comparison
            )
        }
    }

    /// Hoisted out of the render path, and out of `dateText` with it: building a
    /// `DateFormatter` where a body can reach it is the allocation
    /// `docs/history-performance.md` was written about (rendering rule 2). The
    /// template is `WorkoutDetailView`'s, so the plate prints the date in the
    /// same shape — and the same locale's order — as the screen it pictures.
    /// `@MainActor` is already inferred from the `View` conformance; it is
    /// written out because a shared mutable formatter is only safe while every
    /// access comes from a view body, and that argument should be visible rather
    /// than deduced. `ExerciseComparisonStrip` states it the same way.
    @MainActor
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEE d. MMM")
        return formatter
    }()

    private static let dateText = dateFormatter.string(from: OnboardingSampleHistory.sessionDate)
}

#Preview {
    ScrollView {
        OnboardingHistorySlideView()
            .padding(DesignSystem.Spacing.xl)
    }
    .background(DesignSystem.Colors.background.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
