import SwiftUI

/// Which side of the schematic body a figure shows.
enum MuscleMapFace: Hashable, Sendable {
    case front
    case back
}

/// One drawable element of the schematic figure.
///
/// The body is authored as a left half only, so a mirrored shape carries its
/// counterpart reflected across the midline (`x = 100`) as a second path.
struct MuscleMapShape: Identifiable {
    let id: Int
    /// `nil` for the silhouette, the non-muscular fillers and the midline detail.
    let region: MuscleMapRegion?
    let paths: [Path]
}

/// Every belly of one region on one figure, mirrors included, as a single design-space path.
///
/// A region is drawn as several separate shapes (the abdominals are six paths, the calves
/// three), and each of those shape views spans the whole figure frame. This union is what
/// gives the region's single VoiceOver element a frame matching what the user sees.
struct MuscleMapRegionOutline: Identifiable {
    let region: MuscleMapRegion
    let outline: Path

    var id: MuscleMapRegion { region }
}

/// The layered shapes of one figure, in draw order.
struct MuscleMapFigure {
    let silhouette: [MuscleMapShape]
    let fillers: [MuscleMapShape]
    let muscles: [MuscleMapShape]
    let details: [MuscleMapShape]
    /// One entry per region this figure draws, in anatomical order. Derived from `muscles`.
    let regionOutlines: [MuscleMapRegionOutline]

    init(
        silhouette: [MuscleMapShape],
        fillers: [MuscleMapShape],
        muscles: [MuscleMapShape],
        details: [MuscleMapShape]
    ) {
        self.silhouette = silhouette
        self.fillers = fillers
        self.muscles = muscles
        self.details = details
        // Runs once per figure, inside `MuscleMapGeometry`'s static storage — never per render.
        self.regionOutlines = MuscleMapRegion.allCases.compactMap { region in
            let paths = muscles
                .filter { $0.region == region }
                .flatMap(\.paths)
            guard !paths.isEmpty else { return nil }
            var outline = Path()
            for path in paths { outline.addPath(path) }
            return MuscleMapRegionOutline(region: region, outline: outline)
        }
    }
}

/// Static geometry of the schematic body, parsed once at first access.
///
/// Source of truth: `muscle-map.jsx` in the Claude Design project
/// `0d4ac3f4-2c40-43cc-b80e-84bd411c334a`. Paths live on a 200 × 474 grid; the
/// visible viewport crops the grid horizontally.
enum MuscleMapGeometry {

    static let viewport = CGRect(x: 14, y: 0, width: 172, height: 474)

    /// Width ÷ height of the visible figure.
    static let aspectRatio: CGFloat = viewport.width / viewport.height

    static func figure(for face: MuscleMapFace) -> MuscleMapFigure {
        switch face {
        case .front: front
        case .back: back
        }
    }

    // MARK: - Figures

    static let front = MuscleMapFigure(
        silhouette: shapes(silhouetteData),
        fillers: shapes(fillerData + pelvisFrontData),
        muscles: shapes(frontMuscleData),
        details: shapes([RawShape(d: "M100,125.1 L100,202.1", mirror: false)])
    )

    static let back = MuscleMapFigure(
        silhouette: shapes(silhouetteData),
        fillers: shapes(fillerData),
        muscles: shapes(backMuscleData),
        details: shapes([RawShape(d: "M100,67.5 L100,205", mirror: false)])
    )

    // MARK: - Building

    private struct RawShape {
        let d: String
        var mirror: Bool = true
        var region: MuscleMapRegion?
    }

    /// Reflection across the body midline: `x' = 200 - x`.
    private static let mirrorTransform = CGAffineTransform(scaleX: -1, y: 1)
        .concatenating(CGAffineTransform(translationX: 200, y: 0))

    private static func shapes(_ raw: [RawShape]) -> [MuscleMapShape] {
        raw.enumerated().map { index, item in
            let base = MuscleMapPathParser.path(from: item.d)
            return MuscleMapShape(
                id: index,
                region: item.region,
                paths: item.mirror ? [base, base.applying(mirrorTransform)] : [base]
            )
        }
    }

    // MARK: - Path data

    private static let silhouetteData: [RawShape] = [
        RawShape(d: "M100,4 L100,233 C96.6,256.7 94.4,277.1 93.3,300.2 C92.4,328.3 91.5,349.5 90.7,371.1 C89.9,394.6 89,417 89,437 C89,446.4 85,455.8 77,458.9 C67,462 57,460.4 55,452.6 C53,444.8 57,437 62,429 C68,419 72,407 72.8,393.3 C73.2,373.7 71.5,352.9 68.8,337.7 C65.8,313 64.2,290 63,273.4 C60.8,254.8 60.8,241 65.4,228.8 C69.6,219 72.2,213.4 74.9,206.4 C73,197.9 71,189.3 71,180.7 C71,167.9 73,151.3 75,134.6 C77,118 79,110.6 80,103.1 C78,97 71,92 58,92.6 C68,83.8 78,77.3 87,72.4 C89,70.8 90,69.2 90,67.5 L90,61 C82,57.1 74,47.2 74,32.5 C74,16.8 85,4 100,4 Z"),
        RawShape(d: "M58,92.6 C50,96.3 45,103.1 44,111.2 C42,122.9 40,135.7 37,148.6 C34,160.8 31,172.5 29,184.7 C27,198.3 25,212.6 25,223.4 C25,233.8 27,248.7 31,261.8 C35,274.8 44,274.8 48,263.1 C52,251.3 53,235.1 53,224.7 C54,214.2 56,199.9 58,186.2 C60,173.7 63,162 65,151.1 C67,139.5 69,127.9 70,118 C71,109.3 71,99.4 68,92 Z"),
    ]

    private static let fillerData: [RawShape] = [
        RawShape(d: "M100,4 C85,4 74,16.8 74,32.5 C74,47.2 82,57.1 90,61 L90,69.2 C94,67.5 100,65.9 100,65.9 Z"),
        RawShape(d: "M47,174.8 C52,178.2 59,178.9 63,176 C64,181.1 62,186.2 60,189.1 C54,192 47,190.5 44,186.9 C43,181.8 45,177.5 47,174.8 Z"),
        RawShape(d: "M44,240.9 C48,250 48,261.8 44,270.9 C39,280 31,280 28,269.6 C25,259.2 26,247.4 30,239.6 C34,244.8 40,244.8 44,240.9 Z"),
        RawShape(d: "M66.6,335 C72.2,340 83.9,340 90.3,335 C91.5,342 90.5,348 88.4,351.5 C82.1,355 72.7,355 68.3,351 C66,346 65.7,340 66.6,335 Z"),
        RawShape(d: "M86,430 C87,444 83,452.5 76,455.5 C67,458 59,457 57,450.5 C55,444.5 59,437.5 64,430.5 C69,423 72,413 72.8,403 C77,413 82,424 86,430 Z"),
    ]

    private static let pelvisFrontData: [RawShape] = [
        RawShape(d: "M78,204 C86,201 96,201 100,203 L100,241 C92,243 82,239 77,231 C74,221 75,211 78,204 Z"),
    ]

    private static let frontMuscleData: [RawShape] = [
        RawShape(d: "M100,67.5 C93,69.2 86,73.2 79,78.9 C74,83 69,87.9 65,92 C74,87.9 87,83.8 96,82.2 C99,81.4 100,81.4 100,81.4 Z", region: .trapezius),
        RawShape(d: "M63,91 C55,95.1 48,101.9 47,110.5 C47,116.1 49,121.7 53,126 C59,124.1 64,118.6 67,111.8 C69,104.4 68,96.9 65,91 Z", region: .shoulders),
        RawShape(d: "M53,127.3 C51,131.8 51,137 53,141.5 C59,140.8 64,136.3 67,130.5 C68,125.4 68,120.4 67,115.5 C64,121.7 59,126 53,127.3 Z", region: .shoulders),
        RawShape(d: "M100,85.5 C93,83.8 85,84.7 79,88.7 C75,92 73,97 73,103.1 C73,109.3 76,114.9 82,118 C89,121.6 96,116.8 100,111.2 Z", region: .chest),
        RawShape(d: "M76,109.3 C73,113 71,118 71,129.9 C76,129.9 81,125.1 84,117.4 C83,113 80,110.6 76,109.3 Z", region: .abs),
        RawShape(d: "M84,127.5 C90,125.1 99,125.1 99,125.1 L99,146.5 C92,147.7 87,146.5 84,144.1 C83,138.2 83,132.3 84,127.5 Z", region: .abs),
        RawShape(d: "M83,150.1 L99,150.1 L99,171.4 C92,172.6 86,170.3 83,166.7 C82,160.8 82,154.8 83,150.1 Z", region: .abs),
        RawShape(d: "M83,175 L99,175 L99,187.9 C93,189.3 87,187.1 84,184.3 C82,180.7 82,177.9 83,175 Z", region: .abs),
        RawShape(d: "M84,190 L99,190 L99,202.1 C93,203.6 88,200.7 85,197.1 C83,194.3 83,192.1 84,190 Z", region: .abs),
        RawShape(d: "M78,122.8 C73,137 71,160.8 72,180.7 C73,190.7 77,197.9 82,202.1 C80,185 78,153.6 79,122.8 Z", region: .abs),
        RawShape(d: "M52,127.9 C47,135 44,144 44,155 C44,163.8 48,171.3 54,176 C61,173.1 65,163.8 65,154.4 C65,142.8 59,133.1 55,127.9 Z", region: .biceps),
        RawShape(d: "M55,177.5 C51,183.3 49,190.5 48,198.3 C52,196.8 57,191.3 60,184.7 C61,180.4 58,178.9 55,177.5 Z", region: .forearms),
        RawShape(d: "M50,181.8 C42,190.5 38,202.3 36,215 C35,223.4 37,231.2 41,237 C47,233.8 52,224.7 55,215 C58,202.3 55,189.1 52,181.8 Z", region: .forearms),
        RawShape(d: "M77.7,239 C67.5,249 64.2,269.6 64.2,290 C64.6,311.7 68.4,325.8 74.1,334.7 C78.1,321.9 78.7,292.6 78.7,271.5 C78.7,256.7 78.7,247 79.9,239 Z", region: .quadriceps),
        RawShape(d: "M82.1,239 C78.7,251 77.6,269.6 78.7,290 C80.1,311.7 83.6,324.5 88.1,334.7 C91.3,321.9 92.2,292.6 92.2,271.5 C92.2,256.7 88.8,245 85.5,239 Z", region: .quadriceps),
        RawShape(d: "M85,292 C91,298 94,308 93,318 C90,326 82,326 78,318 C76,308 80,298 85,292 Z", region: .quadriceps),
        RawShape(d: "M78.7,351 C72.7,360 70.4,381.5 72,405 C73,422 77,430 81,433 C86,421 86.8,389.3 86.5,365.8 C86.3,356 83,352 78.7,351 Z", region: .calves),
        RawShape(d: "M72.6,353 C68.9,367 68.6,389.3 70,404 C74,402.5 76.8,391.9 77.3,373.7 C77,362 75.8,355 72.6,353 Z", region: .calves),
    ]

    private static let backMuscleData: [RawShape] = [
        RawShape(d: "M100,67.5 C92,69.2 84,73.2 77,78.9 C71,83 66,87.9 63,92 C70,94.5 80,95.7 90,94.5 C95,93.2 99,91.2 100,89.6 Z", region: .trapezius),
        RawShape(d: "M100,92.6 C93,93.9 85,95.1 78,96.3 C80,105.6 87,116.8 94,132.3 C97,139.4 99,144.1 100,146.5 Z", region: .trapezius),
        RawShape(d: "M63,91 C55,95.1 48,101.9 47,110.5 C47,116.1 49,121.7 53,126 C59,124.1 64,118.6 67,111.8 C69,104.4 68,96.9 65,91 Z", region: .shoulders),
        RawShape(d: "M53,127.3 C51,131.8 51,137 53,141.5 C59,140.8 64,136.3 67,130.5 C68,125.4 68,120.4 67,115.5 C64,121.7 59,126 53,127.3 Z", region: .shoulders),
        RawShape(d: "M77,98.2 C71,106.9 68,122.8 70,146.5 C72,165.5 79,176.4 88,180.7 C93,175 97,156 98,134.6 C99,118 98,110.6 96,104.4 C90,100.7 84,98.8 77,98.2 Z", region: .back),
        RawShape(d: "M89,137 C94,135.8 99,135.8 99,135.8 L99,177.9 L88,177.9 C86,165.5 86,150.1 89,137 Z", region: .lowerBack),
        RawShape(d: "M83,180.7 C90,179.3 100,179.3 100,179.3 L100,205 C93,205.7 86,202.9 83,197.1 C81,192.1 82,185 83,180.7 Z", region: .lowerBack),
        RawShape(d: "M54,127.9 C49,135 46,144 46,154.4 C46,163.2 49,170.8 54,176 C59,172.5 62,163.8 62,154.4 C62,142.8 58,132.4 54,127.9 Z", region: .triceps),
        RawShape(d: "M49,131.2 C45,137.6 43,145.3 43,154.4 C43,161.4 45,168.4 49,173.7 C52,168.4 53,160.3 53,151.1 C53,142.1 51,135 49,131.2 Z", region: .triceps),
        RawShape(d: "M55,177.5 C51,183.3 49,190.5 48,198.3 C52,196.8 57,191.3 60,184.7 C61,180.4 58,178.9 55,177.5 Z", region: .forearms),
        RawShape(d: "M50,181.8 C42,190.5 38,202.3 36,215 C35,223.4 37,231.2 41,237 C47,233.8 52,224.7 55,215 C58,202.3 55,189.1 52,181.8 Z", region: .forearms),
        RawShape(d: "M81.7,209.2 C70.2,213.4 64,222.5 63.9,232.3 C64.2,245 74.2,253 86.6,253 C94.4,253 100,250 100,244 L100,213.4 C93.9,209.2 87.9,207.1 81.7,209.2 Z", region: .glutes),
        RawShape(d: "M77.6,256.7 C67.5,267.8 64.2,288.1 65.9,315.6 C67.6,333.4 72.3,344.5 77.8,351.2 C80.7,341.9 81.3,318.1 79.8,290 C78.7,273.4 77.6,262.3 78.7,254.8 Z", region: .hamstrings),
        RawShape(d: "M83.2,256.7 C79.8,267.8 78.7,288.1 80.2,315.6 C81.6,333.4 85.1,344.5 89.4,351.2 C92.5,341.9 93.4,318.1 93.3,290 C93.3,271.5 88.8,260.4 85.4,256.7 Z", region: .hamstrings),
        RawShape(d: "M72.6,353 C68.8,366 67.5,386.7 69,403 C72,412 76,412 78,403 C78.6,385.4 77.1,363 75.7,353 Z", region: .calves),
        RawShape(d: "M83.1,353 C86.5,366 87.8,386.7 87,403 C85,412 81,412 79,403 C77.6,385.4 80.2,363 81,353 Z", region: .calves),
        RawShape(d: "M79,406 C73,418 71,428 72,434 C77,439 85,439 87,434 C88,426 85,418 82,406 Z", region: .calves),
    ]
}
