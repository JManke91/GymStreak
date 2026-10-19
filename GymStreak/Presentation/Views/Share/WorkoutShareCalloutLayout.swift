//
//  WorkoutShareCalloutLayout.swift
//  GymStreak
//
//  Where the share card's figures and muscle callouts sit. A port of the approved design's
//  `Main.dc.html` layout (docs/workout-sharing.md); every constant here is a design value.
//

import CoreGraphics

/// The figure stage of the share card: two muscle figures side by side, front-figure callouts
/// in the left column and back-figure callouts in the right, each joined to its muscle by a
/// leader line.
enum WorkoutShareCalloutLayout {

    /// The card's content width: 1080 minus 80 of padding on each side.
    static let stageWidth: CGFloat = 920

    struct Stage: Equatable {
        let figureWidth: CGFloat
        let frontX: CGFloat
        let backX: CGFloat
        let height: CGFloat
        let labelWidth: CGFloat
    }

    /// One primary region's label and leader line, in stage coordinates.
    struct Callout: Equatable, Identifiable {
        let region: MuscleMapRegion
        let anchor: CGPoint
        let elbow: CGPoint
        let end: CGPoint
        /// Top-left of the label box, which is `Stage.labelWidth` wide.
        let labelOrigin: CGPoint
        /// Left column (front figure): the label right-aligns against its line.
        let isLeftColumn: Bool

        var id: MuscleMapRegion { region }
    }

    /// The figures grow when no callouts compete for the width.
    static func stage(showsCallouts: Bool) -> Stage {
        let figureWidth: CGFloat = showsCallouts ? 200 : 280
        let frontX = 440 - figureWidth
        return Stage(
            figureWidth: figureWidth,
            frontX: frontX,
            backX: 480,
            height: (474 * figureWidth / designFigureWidth).rounded(),
            labelWidth: frontX - 40
        )
    }

    /// Places one callout per region, in the order given.
    ///
    /// Regions visible on only one figure go to that figure's column; regions visible on both
    /// go to whichever column holds fewer labels at that point. Within a column a label centres
    /// its first line on the anchor, a collision pushes it down, and the column then shifts back
    /// up by the mean displacement so the lines fan out evenly.
    static func callouts(for regions: [MuscleMapRegion], in stage: Stage) -> [Callout] {
        var left: [MuscleMapRegion] = []
        var right: [MuscleMapRegion] = []
        for region in regions {
            switch anchors[region]?.side {
            case .front: left.append(region)
            case .back: right.append(region)
            case .either, nil: break
            }
        }
        for region in regions where anchors[region]?.side == .either {
            if left.count <= right.count { left.append(region) } else { right.append(region) }
        }
        return column(left, isLeft: true, stage: stage) + column(right, isLeft: false, stage: stage)
    }

    // MARK: - Private

    /// The design's figure grid is 172 units wide (the visible part of the 200-unit body grid).
    private static let designFigureWidth: CGFloat = 172
    private static let labelHeight: CGFloat = 84
    private static let labelGap: CGFloat = 40

    private enum Side { case front, back, either }

    /// Leader-line anchor per region on the 200 × 474 design grid, on the left half's outer
    /// edge so lines do not cross the body. `either` = visible on both figures.
    private static let anchors: [MuscleMapRegion: (side: Side, x: CGFloat, y: CGFloat)] = [
        .chest: (.front, 78, 98), .biceps: (.front, 48, 150), .abs: (.front, 84, 165),
        .quadriceps: (.front, 70, 285),
        .shoulders: (.either, 52, 110), .forearms: (.either, 42, 205), .calves: (.either, 72, 385),
        .trapezius: (.either, 82, 82),
        .back: (.back, 74, 130), .triceps: (.back, 46, 152), .lowerBack: (.back, 90, 190),
        .glutes: (.back, 72, 228), .hamstrings: (.back, 70, 300)
    ]

    private static func column(_ regions: [MuscleMapRegion], isLeft: Bool, stage: Stage) -> [Callout] {
        let scale = stage.figureWidth / designFigureWidth
        var items: [(region: MuscleMapRegion, anchor: CGPoint, top: CGFloat)] = regions.compactMap { region in
            guard let a = anchors[region] else { return nil }
            // The back figure is labelled on its right edge: mirror the left-half anchor.
            let x = isLeft
                ? stage.frontX + (a.x - 14) * scale
                : stage.backX + (200 - a.x - 14) * scale
            return (region, CGPoint(x: x.rounded(), y: (a.y * scale).rounded()), 0)
        }
        items.sort { $0.anchor.y < $1.anchor.y }

        var previousBottom = -CGFloat.infinity
        var displacement: CGFloat = 0
        for index in items.indices {
            let ideal = items[index].anchor.y - 16
            let top = max(ideal, previousBottom + labelGap)
            items[index].top = top
            previousBottom = top + labelHeight
            displacement += top - ideal
        }
        let shift = items.isEmpty ? 0 : min(displacement / CGFloat(items.count), items.map(\.top).min() ?? 0)

        let endX = isLeft ? stage.frontX - 16 : stage.backX + stage.figureWidth + 16
        let elbowX = isLeft ? endX + 24 : endX - 24
        return items.map { item in
            let top = (item.top - shift).rounded()
            let lineY = top + 16
            return Callout(
                region: item.region,
                anchor: item.anchor,
                elbow: CGPoint(x: elbowX, y: lineY),
                end: CGPoint(x: endX, y: lineY),
                labelOrigin: CGPoint(x: isLeft ? endX - 8 - stage.labelWidth : endX + 8, y: top),
                isLeftColumn: isLeft
            )
        }
    }
}
