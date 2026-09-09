//
//  FunnelAttributes.swift
//  GymStreak
//
//  The four anonymous, bucketed facts the purchase backend is tagged with, so
//  its charts can be read as a funnel. See docs/funnel-instrumentation.md.
//

import Foundation

/// How this copy of the app was installed, reduced to the only distinction the
/// charts need.
///
/// **Two cases, not four.** `docs/acquisition-strategy.md` §1.1 is the reason
/// this exists at all: 30% of the customer records came from builds that were
/// never on the App Store, which made every chart unreadable. Separating
/// TestFlight from Xcode from the simulator would answer a question nobody is
/// asking; excluding all three from an App Store reading is the whole point.
///
/// The raw values are the literal strings the dashboard segments on.
enum AppBuildChannel: String, Equatable, Sendable {

    /// Provably a production App Store install. The **only** value that may be
    /// inferred from a positive proof — never from the absence of one.
    case appStore = "appstore"

    /// Everything else: TestFlight, the simulator, a local Xcode run, and every
    /// case where the answer could not be established at all. The attribute
    /// exists to *exclude* noise, so it fails toward this value.
    case other
}

/// One complete report of where this install stands in the funnel.
///
/// **Every field is a bucket, and that is not a preference.** A precise workout
/// count plus a storefront plus a first-seen timestamp is re-identifying; a
/// bucket is not, and it answers "does anyone reach the value moment?" just as
/// well. The app's positioning is the no-account privacy promise
/// (`docs/monetization-strategy.md` §1), and a re-identifying analytics
/// attribute would contradict it directly.
///
/// **Nothing ever reads these back.** They are analytics exactly as `founder`
/// is: no gate, no entitlement, no UI and no business rule may branch on any of
/// them, or the no-account promise starts leaking into behaviour.
///
/// The fields are `String` because every RevenueCat subscriber attribute is —
/// there is no boolean or numeric attribute type, and the dashboard segments on
/// the literal text, so the bucket vocabulary *is* the wire format. Building it
/// here rather than at the call site is what keeps the spelling in one place:
/// a chart filtered on `"2-4"` silently matches nothing if some other site ever
/// writes `"2–4"`.
struct FunnelAttributes: Equatable, Sendable {

    /// `"true"` / `"false"` — do they finish the tour, or bail inside it?
    let onboardingCompleted: String

    /// `"0"` / `"1"` / `"2-4"` / `"5+"` — the activation question.
    let workoutsCompleted: String

    /// `"0"` / `"1"` / `"2+"` — does the starter routine carry them, or do they
    /// build their own?
    let routinesCreated: String

    /// `"appstore"` / `"other"`.
    let buildChannel: String

    /// - Parameter completedWorkoutCount: completed sessions, all time.
    /// - Parameter userCreatedRoutineCount: routines the **user** made. The
    ///   seeded starter routine must already be excluded — a fresh install that
    ///   created nothing has to report `"0"`, or the attribute answers the
    ///   opposite of the question it was added for
    ///   (`RoutineCapPolicy.countableRoutineCount(in:)` is the one counting rule).
    static func make(
        hasCompletedOnboarding: Bool,
        completedWorkoutCount: Int,
        userCreatedRoutineCount: Int,
        buildChannel: AppBuildChannel
    ) -> FunnelAttributes {
        FunnelAttributes(
            onboardingCompleted: hasCompletedOnboarding ? "true" : "false",
            workoutsCompleted: workoutsBucket(completedWorkoutCount),
            routinesCreated: routinesBucket(userCreatedRoutineCount),
            buildChannel: buildChannel.rawValue
        )
    }

    /// The activation ladder: nobody, once, warming up, habit. The boundaries
    /// are where the product's own thresholds already sit — §8 placement B and
    /// the rating prompt both act around the first handful of workouts — so a
    /// chart split on this bucket lines up with the decisions it informs.
    ///
    /// A negative count is impossible from a `fetchCount`, but it buckets as
    /// `"0"` rather than falling through to a fifth value the dashboard has no
    /// filter for.
    private static func workoutsBucket(_ count: Int) -> String {
        switch count {
        case ..<1: "0"
        case 1: "1"
        case 2...4: "2-4"
        default: "5+"
        }
    }

    /// One is the interesting number here: it separates "the starter routine was
    /// enough" from "they built something of their own", which is the question
    /// §4.11 asks. Everything past that is one bucket.
    private static func routinesBucket(_ count: Int) -> String {
        switch count {
        case ..<1: "0"
        case 1: "1"
        default: "2+"
        }
    }
}
