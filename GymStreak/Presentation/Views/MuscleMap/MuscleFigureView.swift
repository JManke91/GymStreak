import SwiftUI

/// Schematic human body with the trained muscle bellies highlighted, and tappable.
///
/// Purely presentational: it renders whatever highlights the caller hands it, reports taps
/// back, and reads no workout data itself. Each belly is an individually addressable shape,
/// which is what makes per-belly hit-testing and per-region dimming possible.
struct MuscleFigureView: View {

    let face: MuscleMapFace
    /// Regions to highlight; everything absent renders in the idle grey.
    let highlights: [MuscleMapRegion: MuscleEngagement]
    var width: CGFloat = 128
    /// The region under inspection. Every other belly dims; `nil` draws the figure at full strength.
    var selection: MuscleMapRegion?
    /// Spoken label per region, built once by the caller — formatting them here would put a
    /// dozen `String(format:)` calls in `body`. Falls back to the plain region name.
    var regionLabels: [MuscleMapRegion: String] = [:]
    /// Called when a *trained* belly is tapped, with its region. Untrained bellies are inert.
    var onSelect: ((MuscleMapRegion) -> Void)?

    // Fills from the design reference.
    private static let bodyFill = Color.white.opacity(0.055)
    private static let fillerFill = Color.white.opacity(0.12)
    private static let idleFill = Color.white.opacity(0.2)
    private static let outline = Color(red: 11 / 255, green: 11 / 255, blue: 11 / 255)
    private static let detailStroke = Color.black.opacity(0.45)

    private var figure: MuscleMapFigure { MuscleMapGeometry.figure(for: face) }

    /// Design-space units → points, so stroke weights scale with the figure.
    private var scale: CGFloat { width / MuscleMapGeometry.viewport.width }

    var body: some View {
        drawing
            // The ~55 paths per figure mean nothing one by one, so they are replaced in the
            // accessibility tree by one element per region. `accessibilityChildren` hides the
            // real subtree itself — this is Apple's documented pattern for custom drawing.
            .accessibilityChildren { regionAccessibilityProxies }
            .frame(width: width, height: width / MuscleMapGeometry.aspectRatio)
            .animation(.easeInOut(duration: 0.3), value: highlights)
            .animation(.easeInOut(duration: 0.25), value: selection)
    }

    private var drawing: some View {
        ZStack {
            ForEach(figure.silhouette) { shape in
                shapeLayer(shape, fill: Self.bodyFill, lineWidth: 1.4)
            }
            ForEach(figure.fillers) { shape in
                shapeLayer(shape, fill: Self.fillerFill, lineWidth: 1.4)
            }
            ForEach(figure.muscles) { shape in
                shapeLayer(
                    shape,
                    fill: fill(for: shape.region),
                    lineWidth: 1.5,
                    onTap: tapHandler(for: shape.region)
                )
                .opacity(opacity(for: shape.region))
            }
            ForEach(figure.details) { shape in
                shapeLayer(shape, fill: .clear, stroke: Self.detailStroke, lineWidth: 1.2)
            }
        }
    }

    /// One VoiceOver element per region the figure draws, shaped like that region's bellies.
    ///
    /// These views are never rendered — SwiftUI only reads them to synthesize accessibility
    /// elements. Untrained regions are exposed too: dimming and inertness are visual
    /// affordances and must not cost the map its information.
    private var regionAccessibilityProxies: some View {
        ZStack {
            ForEach(figure.regionOutlines) { entry in
                proxy(for: entry)
            }
        }
    }

    @ViewBuilder
    private func proxy(for entry: MuscleMapRegionOutline) -> some View {
        let shape = MuscleMapPathShape(designPath: entry.outline)
        let label = regionLabels[entry.region] ?? entry.region.displayName
        // Without the accessibility content shape every proxy would report the whole figure
        // as its frame, since a `Shape` fills whatever it is offered.
        if let handler = tapHandler(for: entry.region) {
            shape
                .contentShape(.accessibility, shape)
                .accessibilityLabel(label)
                .accessibilityAddTraits(entry.region == selection ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { handler() }
        } else {
            // No action and no button trait: an untrained belly must not announce itself as
            // something to activate.
            shape
                .contentShape(.accessibility, shape)
                .accessibilityLabel(label)
        }
    }

    private func fill(for region: MuscleMapRegion?) -> Color {
        guard let region, let engagement = highlights[region] else { return Self.idleFill }
        switch engagement {
        case .primary: return DesignSystem.Colors.tint
        case .secondary: return DesignSystem.Colors.tint.opacity(0.42)
        }
    }

    /// Everything but the inspected region steps back while a selection is open.
    private func opacity(for region: MuscleMapRegion?) -> Double {
        guard let selection else { return 1 }
        return region == selection ? 1 : 0.3
    }

    /// `nil` for an untrained belly, which makes it non-tappable rather than tappable-but-silent.
    private func tapHandler(for region: MuscleMapRegion?) -> (() -> Void)? {
        guard let region, highlights[region] != nil, let onSelect else { return nil }
        return { onSelect(region) }
    }

    /// Draws the authored half and, for mirrored shapes, its reflected counterpart. Both
    /// halves carry the same tap handler, so either biceps selects the biceps.
    private func shapeLayer(
        _ shape: MuscleMapShape,
        fill: Color,
        stroke: Color = Self.outline,
        lineWidth: CGFloat,
        onTap: (() -> Void)? = nil
    ) -> some View {
        ForEach(shape.paths.indices, id: \.self) { index in
            MuscleMapShapeView(
                designPath: shape.paths[index],
                fill: fill,
                stroke: stroke,
                lineWidth: lineWidth * scale,
                onTap: onTap
            )
        }
    }
}

/// A single filled and outlined path of the figure.
private struct MuscleMapShapeView: View {
    let designPath: Path
    let fill: Color
    let stroke: Color
    let lineWidth: CGFloat
    var onTap: (() -> Void)?

    var body: some View {
        ZStack {
            MuscleMapPathShape(designPath: designPath)
                .fill(fill)
            MuscleMapPathShape(designPath: designPath)
                .stroke(stroke, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        // Each shape view spans the whole figure, so without this the tap area would be the
        // full frame and the topmost belly would swallow every tap.
        .contentShape(MuscleMapPathShape(designPath: designPath))
        .onTapGesture { onTap?() }
        .allowsHitTesting(onTap != nil)
    }
}

#Preview("Muscle figures") {
    let highlights: [MuscleMapRegion: MuscleEngagement] = [
        .chest: .primary,
        .quadriceps: .primary,
        .back: .primary,
        .triceps: .secondary,
        .shoulders: .secondary,
        .hamstrings: .secondary,
    ]

    return HStack(alignment: .top, spacing: 16) {
        VStack(spacing: 6) {
            MuscleFigureView(face: .front, highlights: highlights)
            Text(verbatim: "Front")
                .font(.caption2)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        VStack(spacing: 6) {
            MuscleFigureView(face: .back, highlights: highlights)
            Text(verbatim: "Back")
                .font(.caption2)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DesignSystem.Colors.background)
}
