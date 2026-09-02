//
//  RoutineSetRowWidthBudgetTests.swift
//  GymStreakTests
//
//  The set row of a routine's exercise card is laid out from fixed widths against
//  a width budget that shrinks with nesting depth, and it shipped over that budget
//  twice: "kg" truncated to "k", and a converted weight like "136,08" clipped to
//  "136…". Both were invisible on the 402 pt device they were built on and only
//  reproduced on a narrower phone inside a superset.
//
//  Nothing about that is catchable by a build, and it is not reliably catchable by
//  eye either — it needs the right device, the right language, a superset, and an
//  expanded alternative all at once. So it is pinned here instead: the row's own
//  constants, summed, against the tightest cell of the matrix.
//
//  `rowWidth` below sums the row's constants by hand, which on its own would be a
//  mirror of `body` rather than a measurement of it — adding an element to the row's
//  HStack would pass and clip on device. `measuredRowMatchesItsConstants` closes
//  that: it lays out the real view and asserts the two agree, so the arithmetic the
//  other tests reason about is checked against the layout it claims to describe.
//
//  What these tests still CANNOT see is whether the host paddings they encode match
//  the view bodies they came from (they are literals in RoutineDetailView and
//  RoutineAlternativesSection). Each is commented with its source; the connector
//  lane is read live. Two further hosts of the same editor are out of the matrix
//  because their budget cannot be summed from repo constants at all —
//  ConfigureExerciseSetsView and PendingAlternativesSection sit inside a `Form`,
//  whose inset-grouped insets are not a literal anywhere. Both are wider contexts
//  than the tightest cell covered here.
//

import SwiftUI
import UIKit
import Testing
@testable import GymStreak

@Suite
@MainActor
struct RoutineSetRowWidthBudgetTests {

    private typealias Metrics = RoutineSetStepperRow.Metrics

    // MARK: - The budget

    /// `LazyVStack.padding(.horizontal, 16)` in RoutineDetailView's normal-mode list.
    private static let listPadding: CGFloat = 32
    /// The exercise card's `.padding(14)`.
    private static let cardPadding: CGFloat = 28
    /// The alternative cell's `.padding(.horizontal, 8)` in RoutineAlternativesSection.
    private static let alternativeCellPadding: CGFloat = 16

    /// Width the row actually asks for. Mirrors `body`: remove column, index
    /// badge, then the two ± groups with the interior spacer at its minimum.
    private static var rowWidth: CGFloat {
        Metrics.rowPadding * 2
            + Metrics.removeButtonWidth
            + Metrics.outerSpacing
            + Metrics.indexWidth
            + Metrics.outerSpacing
            + Metrics.repsGroupWidth
            + Metrics.groupSpacing + 2 + Metrics.groupSpacing
            + Metrics.weightGroupWidth
    }

    /// Every nesting depth the row is reachable at, tightest last. The
    /// alternatives block is rendered unconditionally inside superset member
    /// cards, so the deepest one is real.
    private static func budgets(screenWidth: CGFloat) -> [(String, CGFloat)] {
        let lane = ExerciseHeaderView.connectorLaneWidth
        let base = screenWidth - listPadding - cardPadding
        return [
            ("plain card", base),
            ("superset member", base - lane),
            ("alternative on a plain card", base - alternativeCellPadding),
            ("alternative inside a superset member", base - lane - alternativeCellPadding),
        ]
    }

    /// Every iPhone width the app supports, narrowest last.
    private static let screenWidths: [(String, CGFloat)] = [
        ("iPhone 17/16 Pro", 402),
        ("iPhone 15/16/14 Pro", 393),
        ("iPhone 14/13/12", 390),
        ("iPhone SE / 13 mini", 375),
    ]

    @Test("The set row fits every nesting depth on every supported iPhone width")
    func rowFitsEveryCellOfTheMatrix() {
        for (device, screenWidth) in Self.screenWidths {
            for (host, budget) in Self.budgets(screenWidth: screenWidth) {
                #expect(
                    Self.rowWidth <= budget,
                    """
                    Set row needs \(Self.rowWidth) pt but \(host) on \(device) \
                    offers \(budget) pt — over by \(Self.rowWidth - budget). \
                    Nothing in the row is flexible, so this clips a ± button \
                    rather than degrading. See RoutineSetStepperRow.Metrics.
                    """
                )
            }
        }
    }

    @Test("The row's width does not depend on the display language")
    func rowCarriesNoLocalizedText() {
        // The bug was that "Wdh." (33.9 pt) sat where "reps" (29.1 pt) sat in
        // English, so the row was 4.8 pt wider in German than it was built for.
        // Every width above is now a constant, and this is what keeps it true:
        // the row renders digits and SF Symbols only, and the unit words live in
        // RoutineSetsHeaderRow, one per list, where they have room to scale.
        #expect(Self.rowWidth == 273)
    }

    // MARK: - The fields against their worst-case content

    /// The value fields' font, rebuilt from the row's own constant.
    private static var valueFont: UIFont {
        let base = UIFont.monospacedDigitSystemFont(ofSize: Metrics.valueFontSize, weight: .bold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: Metrics.valueFontSize)
    }

    private static func width(_ string: String, font: UIFont) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }

    @Test("The reps field holds its domain maximum")
    func repsFieldHoldsThreeDigits() {
        // The ± buttons stop at 100, and since the weight-unit work the typed
        // binding clamps to the same maximum — so three digits is the true bound
        // and the field only has to hold that. "250" and "100" are the same
        // width at monospaced digits.
        #expect(Self.width("100", font: Self.valueFont) <= Metrics.repsFieldWidth)
    }

    @Test("The weight field holds a converted value at full precision")
    func weightFieldHoldsConvertedKilograms() {
        // 300 lb is 136,078 kg, so a routine authored in pounds carries
        // six-character kilogram values throughout. This is the string that
        // shipped clipped to "136…".
        for value in ["136,08", "999,99", "136.08"] {
            #expect(Self.width(value, font: Self.valueFont) <= Metrics.weightFieldWidth)
        }
    }

    // MARK: - The arithmetic against the real layout

    /// Hosts the row for measurement. `FocusState` only exists inside a `View`,
    /// so the binding the row needs has to come from a wrapper like this.
    private struct RowHost: View {
        @FocusState private var valueFocus: Bool

        var body: some View {
            RoutineSetStepperRow(
                index: 0,
                reps: 8,
                weight: 20,
                valueFocus: $valueFocus,
                onRepsChange: { _ in },
                onWeightChange: { _ in },
                onRemove: {}
            )
        }
    }

    @Test("The row's measured width matches the constants the budget is summed from")
    func measuredRowMatchesItsConstants() {
        let host = UIHostingController(rootView: RowHost())
        // A zero proposal asks for the compressed size, which is what the budget
        // is about: every child is fixed-width and the interior Spacer collapses
        // to its minLength.
        let measured = host.sizeThatFits(in: .zero)

        // A divergence means something was added to or removed from the row's
        // HStack without the budget following it — every other test in this file
        // reasons about the sum, so they would be measuring a row that no longer
        // exists.
        #expect(abs(measured.width - Self.rowWidth) < 0.5,
                "Row lays out at \(measured.width) pt, constants sum to \(Self.rowWidth) pt")
    }

    @Test("The index badge holds a two-digit set number")
    func indexBadgeHoldsTwoDigits() {
        // At 14 pt this truncated to "1…" from the tenth set on.
        let badge = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        #expect(Self.width("99", font: badge) <= Metrics.indexWidth)
    }
}
