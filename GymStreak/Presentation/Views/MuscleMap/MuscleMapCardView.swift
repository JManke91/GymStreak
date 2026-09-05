//
//  MuscleMapCardView.swift
//  GymStreak
//
//  The muscle map, shared by workout detail and routine detail: front and back
//  schematic bodies with the regions the source trained — or plans to train —
//  lit in the accent color.
//

import SwiftUI

/// Card wrapping the two schematic figures, with the primary/secondary legend in its header.
struct MuscleMapCardView: View {

    let model: MuscleMapCardModel
    /// Whether the tap gesture still needs explaining. Injected from
    /// `AppDependencies`, never reached through `.shared`, and shared by both
    /// screens so the lesson is taught once across the app.
    let discovery: MuscleMapDiscoveryTracking
    /// Outer margin the caller wants around the card. It is the caller's decision because the
    /// two screens differ: workout detail lays its sections out edge to edge, routine detail
    /// already insets its scroll content.
    var horizontalMargin: CGFloat = 0

    /// The region the user is inspecting. Deliberately local view state: selecting a region
    /// redraws the card and nothing else — it never re-runs the aggregation behind `model`.
    @State private var selection: MuscleMapRegion?

    /// Whether this card carries the one-time discovery hint. Decided **once**,
    /// in `onAppear`, and never re-read from `discovery` afterwards: the store is
    /// not observable, so a `body` that asked it directly would flip the hint off
    /// mid-screen on the appearance that spends the last showing, and without an
    /// animation.
    @State private var showsDiscoveryHint = false
    /// Guards the appearance count against a second `onAppear` for the same card
    /// — returning from a pushed screen, or leaving routine detail's superset
    /// mode. Three showings is the whole budget; re-entering a screen must not
    /// eat one.
    @State private var hasCountedAppearance = false

    private static let figureWidth: CGFloat = 128

    var body: some View {
        // A source whose exercises map to no region (only "General", nothing completed, or a
        // routine stripped of its sets) would render an all-grey body that says nothing — the
        // card stays away instead. Hiding here rather than at the call site also keeps the
        // margin below from leaving a gap where the card would have been.
        if model.hasTraining {
            VStack(spacing: 0) {
                header
                if showsDiscoveryHint {
                    discoveryHint
                }
                figures
                if let detail = selectedDetail {
                    detailChip(detail)
                } else {
                    pillRow
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, horizontalMargin)
            .accessibilityElement(children: .contain)
            // Appearance, not render: `body` re-runs on every scroll invalidation
            // and on every selection change, and a counter driven from there
            // would spend all three showings before the first was read.
            .onAppear(perform: decideDiscoveryHint)
        }
    }

    /// Dictionary lookup, not a scan — selecting a region must stay free of work in `body`.
    private var selectedDetail: MuscleMapDetail? {
        guard let selection else { return nil }
        return model.details[selection]
    }

    /// What the figures dim against. A selection the model no longer knows — the session was
    /// edited while the chip was open — reads as no selection rather than dimming everything.
    private var activeSelection: MuscleMapRegion? {
        selectedDetail == nil ? nil : selection
    }

    /// The one funnel for both entry points — a pill tap and a belly tap both
    /// arrive here — which is why the hint's dismissal needs no second hook in
    /// `MuscleFigureView`.
    private func select(_ region: MuscleMapRegion) {
        HapticManager.shared.light()
        discovery.recordSelection()
        withAnimation(.easeInOut(duration: 0.25)) {
            selection = selection == region ? nil : region
            showsDiscoveryHint = false
        }
    }

    /// Reads the flag *before* recording the appearance, so the third showing is
    /// still shown rather than being retired by the very write that counts it.
    private func decideDiscoveryHint() {
        guard !hasCountedAppearance else { return }
        hasCountedAppearance = true
        guard !discovery.hasDiscoveredMuscleMap else { return }
        // `onAppear` runs after the first render, so an unanimated assignment
        // would shove `figures` down a frame late. The same 0.25 s the dismissal
        // uses turns that jump into a fade.
        withAnimation(.easeInOut(duration: 0.25)) {
            showsDiscoveryHint = true
        }
        discovery.recordShown()
    }

    private func clearSelection() {
        HapticManager.shared.light()
        withAnimation(.easeInOut(duration: 0.25)) {
            selection = nil
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(model.title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .kerning(-0.2)
                .foregroundStyle(Color.white)
                // The overview VoiceOver used to get from the card as a whole; the figures
                // below now expose one element per region.
                .accessibilityValue(model.accessibilitySummary)
            Spacer(minLength: 8)
            legendEntry(
                color: DesignSystem.Colors.tint,
                label: "history.detail.muscle_map.primary".localized
            )
            legendEntry(
                color: DesignSystem.Colors.tint.opacity(0.4),
                label: "history.detail.muscle_map.secondary".localized
            )
        }
    }

    private func legendEntry(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
        }
    }

    /// One line of copy, spent once. Deliberately ranked *below* everything
    /// around it — lighter than the 13 pt bold title, lighter than the 10 pt
    /// semibold legend and captions — because a tip that matches the weight of
    /// the content it explains reads as a banner the card grew rather than as a
    /// note. Leading-aligned for the same reason; centered, it becomes an
    /// announcement.
    private var discoveryHint: some View {
        HStack(spacing: 5) {
            Image(systemName: "hand.tap")
                .font(.system(size: 10))
            Text("history.detail.muscle_map.discovery_hint".localized)
                .font(.system(size: 10.5))
        }
        .foregroundStyle(Color.white.opacity(0.45))
        .frame(maxWidth: .infinity, alignment: .leading)
        // Reuses the spacing budget `figures` already carries below it.
        .padding(.top, 6)
        .transition(.opacity)
        // Hidden from VoiceOver on purpose, and this is not an oversight:
        // `MuscleFigureView`'s region proxies carry `.isButton` on exactly the
        // trained regions, so VoiceOver has always announced the bellies as
        // buttons and the gesture was never undiscoverable there. Exposed, this
        // line would be a redundant sentence spoken ahead of information
        // VoiceOver already delivers per region — and it would go stale the
        // moment the flag flips. See docs/muscle-map.md, "Discoverability".
        .accessibilityHidden(true)
    }

    private var figures: some View {
        HStack(alignment: .top, spacing: 6) {
            figureColumn(face: .front, caption: "history.detail.muscle_map.front".localized)
            figureColumn(face: .back, caption: "history.detail.muscle_map.back".localized)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    /// The trained regions spelled out beneath the figures: accent-tinted pills with their set
    /// count for the primary movers, muted ones for the supporting work. Tapping one selects
    /// the same region tapping its belly does.
    private var pillRow: some View {
        FlowLayout(spacing: 6) {
            ForEach(model.pills) { pill in
                self.pillView(pill)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .transition(.opacity)
    }

    @ViewBuilder
    private func pillView(_ pill: MuscleMapPill) -> some View {
        let isPrimary = pill.engagement == .primary
        Button {
            select(pill.region)
        } label: {
            HStack(spacing: 5) {
                Text(pill.name)
                    .font(.system(size: 11.5, weight: isPrimary ? .semibold : .medium))
                    .foregroundStyle(isPrimary ? Color.white : Color.white.opacity(0.6))
                if isPrimary {
                    Text("\(pill.setCount)")
                        .font(.system(size: 10.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(DesignSystem.Colors.tint)
                }
                // Sitting directly under an anatomical drawing, the pill row otherwise reads as
                // a caption for the picture and never gets tapped. `chevron.down` and not
                // `chevron.right`: tapping swaps this row for the detail chip in place, it does
                // not push a screen — see docs/muscle-map.md.
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(
                        isPrimary ? DesignSystem.Colors.tint.opacity(0.5) : Color.white.opacity(0.35)
                    )
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(isPrimary ? DesignSystem.Colors.tint.opacity(0.14) : Color.white.opacity(0.04))
            .overlay(
                Capsule()
                    .stroke(
                        isPrimary ? DesignSystem.Colors.tint.opacity(0.26) : Color.white.opacity(0.07),
                        lineWidth: 1
                    )
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        // Without this the set count is spoken as a bare number after the region name.
        .accessibilityLabel(model.accessibilityLabels[pill.region] ?? pill.name)
    }

    /// Replaces the pill row while a region is selected: what it was, how hard, and what did it.
    private func detailChip(_ detail: MuscleMapDetail) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(detail.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                Text(detail.stateLabel.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(DesignSystem.Colors.tint)
                Spacer(minLength: 8)
                Button(action: clearSelection) {
                    Text("history.detail.muscle_map.reset".localized)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.45))
                        // The label is 11 pt type at the edge of the chip: without a padded
                        // hit area of its own it is a near-unhittable tap target.
                        .padding(.vertical, 8)
                        .padding(.leading, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if !detail.exercises.isEmpty {
                Text(detail.exercises)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A 9 % tint over the card, not a solid accent plate, so the white text keeps its
        // contrast and `textOnTint` does not come into play.
        .background(DesignSystem.Colors.tint.opacity(0.09))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignSystem.Colors.tint.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 8)
        .transition(.opacity)
    }

    private func figureColumn(face: MuscleMapFace, caption: String) -> some View {
        VStack(spacing: 4) {
            MuscleFigureView(
                face: face,
                highlights: model.highlights,
                width: Self.figureWidth,
                selection: activeSelection,
                regionLabels: model.accessibilityLabels,
                onSelect: select
            )
            Text(caption.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.4))
        }
    }
}

/// An undiscovered user that records nothing, so the preview always shows the
/// hint and never spends the real install's three appearances. A stub rather
/// than the Data store: a Presentation preview depends on the Domain protocol.
private final class PreviewMuscleMapDiscovery: MuscleMapDiscoveryTracking {
    let hasDiscoveredMuscleMap = false
    func recordSelection() {}
    func recordShown() {}
}

#Preview("Muscle map card — both readings") {
    let loads: [MuscleMapRegion: MuscleLoad] = [
        .chest: MuscleLoad(engagement: .primary, setCount: 8, exerciseNames: ["Bankdrücken"]),
        .triceps: MuscleLoad(engagement: .primary, setCount: 4, exerciseNames: ["Dips"]),
        .shoulders: MuscleLoad(engagement: .secondary, setCount: 0, exerciseNames: ["Bankdrücken"]),
        .quadriceps: MuscleLoad(engagement: .secondary, setCount: 0, exerciseNames: ["Dips"]),
    ]

    return ScrollView {
        VStack(spacing: 16) {
            MuscleMapCardView(
                model: .make(from: loads, reading: .performed),
                discovery: PreviewMuscleMapDiscovery(),
                horizontalMargin: 16
            )
            MuscleMapCardView(
                model: .make(from: loads, reading: .planned),
                discovery: PreviewMuscleMapDiscovery(),
                horizontalMargin: 16
            )
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DesignSystem.Colors.background)
}
