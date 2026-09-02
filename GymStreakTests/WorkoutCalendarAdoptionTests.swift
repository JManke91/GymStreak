//
//  WorkoutCalendarAdoptionTests.swift
//  GymStreakTests
//
//  The duplicate guard (docs/calendar-sync.md §4a). This rule is the only thing
//  standing between a reinstalling user and a growing pile of "Gym Streak"
//  calendars, and it is the one piece of that path that can be tested — the
//  gateway around it owns an `EKEventStore` and cannot be.
//

import Testing
@testable import GymStreak

@MainActor
struct WorkoutCalendarAdoptionTests {

    private let ourSource = "icloud-source"
    private let ourTitle = "Gym Streak"

    private func candidate(
        _ identifier: String,
        source: String? = nil,
        title: String? = nil,
        isWritable: Bool = true
    ) -> WorkoutCalendarCandidate {
        WorkoutCalendarCandidate(
            identifier: identifier,
            sourceIdentifier: source ?? ourSource,
            title: title ?? ourTitle,
            isWritable: isWritable
        )
    }

    private func adopt(_ candidates: [WorkoutCalendarCandidate]) -> String? {
        WorkoutCalendarAdoption.adoptableCalendarIdentifier(
            from: candidates,
            sourceIdentifier: ourSource,
            title: ourTitle
        )
    }

    // MARK: - The reinstall case

    @Test("A calendar left by a previous install is adopted, not duplicated")
    func adoptsTheCalendarFromAPreviousInstall() {
        #expect(adopt([candidate("A")]) == "A")
    }

    @Test("Nothing to adopt means a new calendar is created")
    func noMatchReturnsNil() {
        #expect(adopt([]) == nil)
    }

    // MARK: - Never touching a calendar the app does not own

    @Test("A same-named calendar on another account is still adopted")
    func otherSourceIsStillAdopted() {
        // The source cannot be a *requirement*: it is resolved through the
        // user's default calendar, which they can change between installs. If
        // that were required, moving it would miss the match and create the
        // second calendar this rule exists to prevent.
        #expect(adopt([candidate("A", source: "some-other-account")]) == "A")
    }

    @Test("A match on the expected source wins over one elsewhere")
    func expectedSourceIsPreferred() {
        let candidates = [
            // Lower identifier, so it would win on the tie-break alone —
            // being on the expected source is what decides it instead.
            candidate("a-elsewhere", source: "some-other-account"),
            candidate("z-expected")
        ]
        #expect(adopt(candidates) == "z-expected")
    }

    @Test("A differently named calendar on our account is not ours")
    func differentTitleIsNotAdopted() {
        // The user's own calendars live on the same iCloud source, so the title
        // is what separates ours from theirs.
        #expect(adopt([candidate("A", title: "Training")]) == nil)
        #expect(adopt([candidate("A", title: "Gym Streak Workouts")]) == nil)
        // Matching is exact, not case- or whitespace-insensitive.
        #expect(adopt([candidate("A", title: "gym streak")]) == nil)
        #expect(adopt([candidate("A", title: " Gym Streak")]) == nil)
    }

    @Test("A read-only calendar is never adopted — the app could not manage it")
    func readOnlyIsNotAdopted() {
        #expect(adopt([candidate("A", isWritable: false)]) == nil)
    }

    @Test("Title and writability are both required")
    func onlyTheFullyMatchingCandidateIsChosen() {
        let candidates = [
            candidate("wrong-title", title: "Something else"),
            candidate("read-only", isWritable: false),
            candidate("ours")
        ]
        #expect(adopt(candidates) == "ours")
    }

    @Test("A calendar with no source at all fails the match instead of crashing")
    func missingSourceIsHandled() {
        // `EKCalendar.source` imports as `EKSource!`; the gateway projects a
        // nil source to "", which must simply not match the expected source.
        #expect(adopt([candidate("A", source: "")]) == "A")
        #expect(
            adopt([candidate("A", source: ""), candidate("B")]) == "B",
            "a sourced match must be preferred over one with no source"
        )
    }

    // MARK: - Several matches

    @Test("Several matches pick one deterministically instead of creating another")
    func multipleMatchesAreDeterministic() {
        // The orphans an earlier build left behind are indistinguishable from
        // each other by anything EventKit exposes. Adopting one is the whole
        // point; creating a fourth is the bug.
        let identifiers = ["c-third", "a-first", "b-second"]
        #expect(adopt(identifiers.map { candidate($0) }) == "a-first")
        // Order of discovery must not change the answer.
        #expect(adopt(identifiers.reversed().map { candidate($0) }) == "a-first")
    }

    @Test("Only the matching subset is considered when duplicates are mixed in")
    func multipleMatchesIgnoreNonMatches() {
        let candidates = [
            candidate("z-ours"),
            candidate("a-theirs", title: "Privat"),
            candidate("m-ours")
        ]
        #expect(adopt(candidates) == "m-ours")
    }
}
