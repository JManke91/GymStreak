//
//  OnboardingPlate.swift
//  GymStreak
//
//  The raised, dark panel a feature slide shows a real piece of the app in.
//  See docs/onboarding.md.
//

import SwiftUI

/// Plate measurements a slide may need to name. Not nested in `OnboardingPlate`
/// itself, which is generic over its content — `OnboardingPlate<EmptyView>.x` is
/// not a sentence anyone should have to write to reach a constant.
enum OnboardingPlateMetrics {
    /// The inset a preview gets from the panel's side edges unless a slide asks
    /// for less. Declared once so the stored property, the initialiser and
    /// `OnboardingFeatureSlideContent` cannot drift apart.
    static let contentInset: CGFloat = 12
}

/// A fixed-height panel holding a preview of a real screen, headed by a mono
/// breadcrumb that names where in the app the feature lives.
///
/// The breadcrumb is the reason the plate exists at all: a slide that only shows
/// a screenshot teaches what the app can do, and a slide that also says
/// "Routines › Upper Body A" teaches where to find it afterwards.
///
/// **The height is fixed and the bottom fades out.** Both are the same idea —
/// the real screen continues below, and cropping it at a hard edge would read as
/// "this is all there is". The plate therefore never sizes to its content: a
/// preview shorter than `height` leaves empty panel below it, and a taller one
/// runs into the fade, which is the intended look.
///
/// **Its content is fixed-scale.** A panel with a hard height cannot also honour
/// AX5 type, and enlarging a picture of a screen is not what the reader needs
/// anyway — the copy *below* the plate is the part that must scale, and it does.
struct OnboardingPlate<Content: View>: View {

    /// Where in the app this lives, e.g. "Routines › Upper Body A". Localized.
    let breadcrumb: String
    /// The panel's height. Chosen per slide so the fade lands inside the
    /// content rather than under it.
    let height: CGFloat
    /// Whether the bottom edge dissolves. Off for a preview that genuinely ends
    /// inside the plate.
    var fadesOutBottom: Bool = true
    /// How far the preview is held off the panel's side edges.
    ///
    /// The default reads as a panel with something laid on it. A slide may claim
    /// some of it back when the surface it previews is *dense* horizontally: the
    /// plate is already about 50 pt narrower than the screen it is picturing
    /// (the slide's margins plus this inset), and a production row that fits in
    /// the app can cross into truncation here — which turns a preview meant to
    /// show two numbers into a preview of two ellipses. Step 4's workout set
    /// rows are that case. The breadcrumb keeps the full inset either way.
    var contentInset: CGFloat = OnboardingPlateMetrics.contentInset
    private let content: Content

    init(
        breadcrumb: String,
        height: CGFloat,
        fadesOutBottom: Bool = true,
        contentInset: CGFloat = OnboardingPlateMetrics.contentInset,
        @ViewBuilder content: () -> Content
    ) {
        self.breadcrumb = breadcrumb
        self.height = height
        self.fadesOutBottom = fadesOutBottom
        self.contentInset = contentInset
        self.content = content()
    }

    /// How much of the bottom edge the fade covers.
    private static var fadeHeight: CGFloat { 46 }

    private static var surface: Color { Color(red: 14/255, green: 14/255, blue: 15/255) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            breadcrumbRow
                .padding(.horizontal, OnboardingPlateMetrics.contentInset)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, contentInset)

            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height, alignment: .top)
        .background(Self.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .mask(fadeMask)
        // After the mask, so the shadow dissolves with the edge it belongs to
        // instead of outlining a panel whose bottom is no longer there.
        .shadow(color: .black.opacity(0.45), radius: 20, y: 12)
        // The whole panel, breadcrumb included: the height is a constant, so
        // nothing inside it may grow with the type setting.
        .dynamicTypeSize(.large)
    }

    @ViewBuilder
    private var fadeMask: some View {
        if fadesOutBottom {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: max(0, (height - Self.fadeHeight) / height)),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Color.black
        }
    }

    private var breadcrumbRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 3, height: 3)

            Text(breadcrumb.uppercased())
                .font(.onyxMonoLabel)
                .tracking(1.3)
                .foregroundStyle(Color.white.opacity(0.35))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }
}

#Preview {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        OnboardingPlate(breadcrumb: "Routines › Upper Body A", height: 220) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 38)
                }
            }
        }
        .padding(DesignSystem.Spacing.xl)
    }
    .preferredColorScheme(.dark)
}
