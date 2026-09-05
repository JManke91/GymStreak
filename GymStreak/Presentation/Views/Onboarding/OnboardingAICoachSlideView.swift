//
//  OnboardingAICoachSlideView.swift
//  GymStreak
//
//  Step 6 of the first-run tour: the on-device coach, as a teaser.
//  See docs/onboarding.md.
//

import SwiftUI

extension OnboardingFeatureSlideContent {

    static let aiCoach = OnboardingFeatureSlideContent(
        breadcrumbKey: "onboarding.coach.breadcrumb",
        eyebrowKey: "onboarding.coach.eyebrow",
        titleKey: "onboarding.coach.title",
        bodyKey: "onboarding.coach.body",
        bulletKeys: [
            "onboarding.coach.bullet1",
            "onboarding.coach.bullet2"
        ],
        // The second badged slide. Like step 5 it advertises rather than gates:
        // the coach's free tier is a monthly taster, not a lock, and the strip
        // inside the plate says so in the same breath as the badge.
        showsProBadge: true,
        // Measured, like steps 3–5, rather than rounded: the surface (its
        // header, four lines of answer and the two-line privacy footer), the
        // two-line user bubble and the two-line allowance strip, plus the two
        // 10 pt gaps and the panel's own breadcrumb and padding — about 9 pt of
        // slack on top. Measured against the *German* rendering at both 402 pt
        // and 375 pt, which is the tall case: the answer, the footer and the
        // strip each wrap one line further than they do in English.
        plateHeight: 376,
        // The allowance strip is the last thing in the plate and the one line on
        // this slide that names the offer. Fading it out would crop exactly the
        // sentence the Pro badge above the copy is promising to explain.
        plateFadesOutBottom: false
    )
}

/// The "AI Coach" slide: one coach answer and the question it invites, above the
/// copy.
struct OnboardingAICoachSlideView: View {

    var body: some View {
        OnboardingFeatureSlideView(content: .aiCoach) {
            OnboardingCoachPreview()
        }
    }
}

// MARK: - The preview inside the plate

/// A coach answer about the routine the tour just built, the follow-up question
/// it invites, and what the free tier gets.
///
/// The answer is the production `AISurface` — its gradient edge, its sparkle,
/// its "Coach" eyebrow and its on-device privacy footer are all the shipped
/// chrome, not a copy of it — and the question is the production `MessageBubble`
/// in its `.user` shape. Neither is redrawn here.
///
/// **Nothing acts.** No coach request is issued and no ViewModel is built, so
/// the slide renders identically on a device that cannot run Apple Intelligence.
/// `AISurface`'s and `AISparkleView`'s `onAppear` work is animation that both
/// guard behind their streaming/pulse flags, and neither is set here; the plate
/// mounts the whole subtree with hit testing off on top of that.
private struct OnboardingCoachPreview: View {

    @Environment(\.weightUnit) private var weightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            answer

            MessageBubble(message: Self.question)

            OnboardingCoachAllowanceStrip()
        }
    }

    // MARK: - The answer

    /// The shipped AI surface, with the tour's own "BETA" marker on its header
    /// row.
    ///
    /// `headerLabel` is the app's own name for the screen (`ai_coach.chat.title`
    /// — "Coach") rather than the component's hard-coded English default, so the
    /// eyebrow reads in the reader's language. The footer is on: the privacy line
    /// is half of what this slide is selling.
    private var answer: some View {
        AISurface(
            showFooter: true,
            headerLabel: "ai_coach.chat.title".localized,
            compact: true
        ) {
            Text(accentedAnswer)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.88))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .overlay(alignment: .topTrailing) {
            // Tour chrome, in `textSecondary` rather than the accent, so it does
            // not compete with the "COACH" eyebrow it sits opposite. **The app
            // itself does not call the coach a beta** — see docs/onboarding.md
            // for the finding — which is exactly why this is the tour's declared
            // pill rather than something added to `AISurface`.
            OnboardingChromePill(
                text: "onboarding.coach.beta".localized,
                color: DesignSystem.Colors.textSecondary
            )
            // Onto the surface's header row: `compact` holds it 14 pt from the
            // top and 16 pt from the trailing edge, and the pill is a couple of
            // points taller than the eyebrow beside it.
            .padding(.top, 11)
            .padding(.trailing, 14)
        }
    }

    /// The answer with the figure the translator marked in `**…**` coloured.
    ///
    /// Parsing markdown is not free, so the parse is hoisted out of `body` —
    /// rendering rule 2. It cannot be a plain `static let`, because the weight in
    /// the sentence is formatted in the reader's own unit, so it is keyed on the
    /// unit and computed once per value of it.
    private var accentedAnswer: AttributedString {
        // The cache is built from `WeightUnit.allCases`, so the lookup cannot
        // miss. The fallback is deliberately empty rather than a re-parse: this
        // expression is read from `body`, and a branch that formats a weight and
        // resolves two strings there is a render-path cost waiting for the day a
        // unit is added.
        Self.accentedAnswers[weightUnit] ?? AttributedString()
    }

    private static func rawAnswer(in unit: WeightUnit) -> String {
        OnboardingSampleCoach.answer(
            weightLabel: WeightFormatting.label(OnboardingSampleCoach.stagnatingKilograms, in: unit)
        )
    }

    /// Both units' answers, parsed once. Two entries — the tour cannot switch
    /// unit while it is on screen, but the reader's own setting decides which one
    /// is read, and building both costs one extra parse at first use.
    ///
    /// `@MainActor` is already inferred from the enclosing `View`; it is written
    /// out because a shared cache is only safe while every read comes from a view
    /// body, and that argument should be visible rather than deduced —
    /// `OnboardingHistoryPreview.dateFormatter` states it the same way.
    @MainActor
    private static let accentedAnswers: [WeightUnit: AttributedString] = {
        var parsed: [WeightUnit: AttributedString] = [:]
        for unit in WeightUnit.allCases {
            parsed[unit] = accented(rawAnswer(in: unit))
        }
        return parsed
    }()

    /// Colours the `**bold**` runs of a localized sentence with the AI accent —
    /// the same two lines `ProgressiveOverloadCard.accentedText` uses, because
    /// this is the same job: one figure inside a sentence carries it.
    private static func accented(_ string: String) -> AttributedString {
        var attributed = (try? AttributedString(markdown: string)) ?? AttributedString(string)
        for run in attributed.runs
        where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            attributed[run.range].foregroundColor = AICoachTheme.accent
            attributed[run.range].font = .system(size: 13, weight: .semibold)
        }
        return attributed
    }

    // MARK: - The question

    /// Built once as a `static let`: `MessageBubble` takes a `CoachChatMessage`
    /// whose `id` is a fresh `UUID()` per initialisation, and a value that
    /// changes identity on every render is a row SwiftUI has to rebuild.
    private static let question = CoachChatMessage(
        role: .user,
        text: OnboardingSampleCoach.question,
        phase: .final
    )
}

// MARK: - The allowance strip

/// What the free tier gets, and what Pro adds — one line, with the Pro badge.
///
/// **This is tour chrome, like `OnboardingChromePill`**, and the two shipped
/// candidates were both considered first. `PeriodRecapAllowanceCard` is the
/// recap's *gate*: it carries a headline, recap-specific copy and a primary
/// button that spends a generation and fires a haptic — an affordance that
/// cannot be tapped has no business in a plate. `OnyxCapNudge` is the strip the
/// real Coach Chat screen shows above its input field, but it draws a consumption
/// meter, and the tour has no consumption to report: an empty meter beside this
/// sentence would state a count nobody has spent. So the strip states the offer
/// instead, which is the one thing the badge above the copy has to be able to
/// explain (§8 C).
///
/// **The number comes from `ProFeatureCaps`.** Retuning the taster cap is meant
/// to be a one-line diff (§4), and a slide with a hard-coded "5" in it is a
/// slide that starts lying the day that line changes.
private struct OnboardingCoachAllowanceStrip: View {

    var body: some View {
        HStack(spacing: 10) {
            OnyxProBadge()

            Text(OnboardingSampleCoach.allowanceLine)
                .font(.onyxFootnote)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignSystem.Colors.tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DesignSystem.Colors.tint.opacity(0.26), lineWidth: 1)
        )
    }
}

#Preview {
    ScrollView {
        OnboardingAICoachSlideView()
            .padding(DesignSystem.Spacing.xl)
    }
    .background(DesignSystem.Colors.background.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
