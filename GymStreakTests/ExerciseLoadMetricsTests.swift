import XCTest
@testable import GymStreak

final class ExerciseLoadMetricsTests: XCTestCase {

    func testCounterweightAssistanceConvertsToEffectiveLoad() {
        XCTAssertEqual(
            ExerciseLoadMetrics.effectiveWeight(
                enteredWeight: 70,
                behavior: .counterweightAssistance,
                bodyWeightKg: 100
            ),
            30
        )
    }

    func testCounterweightAssistanceRequiresBodyWeight() {
        XCTAssertNil(
            ExerciseLoadMetrics.effectiveWeight(
                enteredWeight: 70,
                behavior: .counterweightAssistance,
                bodyWeightKg: nil
            )
        )
    }

    func testLessAssistanceIsAnImprovement() {
        XCTAssertTrue(
            ExerciseLoadMetrics.isImprovement(
                current: 65,
                previous: 70,
                behavior: .counterweightAssistance
            )
        )
        XCTAssertEqual(
            ExerciseLoadMetrics.signedEnteredWeightDelta(
                current: 65,
                previous: 70,
                behavior: .counterweightAssistance
            ),
            5
        )
    }

    func testMoreResistanceIsAnImprovement() {
        XCTAssertTrue(
            ExerciseLoadMetrics.isImprovement(
                current: 75,
                previous: 70,
                behavior: .resistance
            )
        )
    }
}
