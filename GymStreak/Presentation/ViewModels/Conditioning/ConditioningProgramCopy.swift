//
//  ConditioningProgramCopy.swift
//  GymStreak
//
//  Localized display text for the 12-week conditioning program. Marketing copy
//  follows docs/fight-conditioning.md ("Marketing claims"): no guaranteed
//  outcomes, no numbers promised.
//

import Foundation

enum ConditioningProgramCopy {

    static func phaseTitle(_ system: ConditioningEnergySystem) -> String {
        "conditioning.program.phase.\(system.rawValue).title".localized
    }

    static func phaseDetail(_ system: ConditioningEnergySystem) -> String {
        "conditioning.program.phase.\(system.rawValue).detail".localized
    }

    /// The one-line version shown while a phase card is collapsed.
    static func phaseTeaser(_ system: ConditioningEnergySystem) -> String {
        "conditioning.program.phase.\(system.rawValue).teaser".localized
    }

    /// The spacing rule that matters most in this phase.
    static func phaseRule(_ system: ConditioningEnergySystem) -> String {
        "conditioning.program.phase.\(system.rawValue).rule".localized
    }

    /// Two or three words for the week rail ("Base", "Speed", "Power").
    static func phaseShortTitle(_ system: ConditioningEnergySystem) -> String {
        "conditioning.program.phase.\(system.rawValue).short".localized
    }

    /// "Weeks 5–8".
    static func phaseWeeks(_ phase: ConditioningProgramPhase) -> String {
        "conditioning.program.phase.weeks".localized(phase.weeks.lowerBound, phase.weeks.upperBound)
    }

    /// "Weeks 5–8 · Lactic" — the card header that ties the rail to the card.
    static func phaseWeeksAndSystem(_ phase: ConditioningProgramPhase) -> String {
        phaseWeeks(phase) + " · " + ConditioningCopy.energySystem(phase.system)
    }

    /// "Phase 2, weeks 5–8, lactic: build repeatable speed".
    static func phaseAccessibilityLabel(_ phase: ConditioningProgramPhase) -> String {
        "conditioning.program.phase.label".localized(
            ConditioningProgramContent.number(of: phase), phase.weeks.lowerBound, phase.weeks.upperBound
        ) + " · " + phaseTitle(phase.system)
    }

    /// "Phase 2 · Weeks 5–8".
    static func phaseLabel(_ phase: ConditioningProgramPhase) -> String {
        "conditioning.program.phase.label".localized(
            ConditioningProgramContent.number(of: phase), phase.weeks.lowerBound, phase.weeks.upperBound
        )
    }

    static func experience(_ experience: ConditioningExperience) -> String {
        "conditioning.program.experience.\(experience.rawValue)".localized
    }

    /// What picking beginner or experienced actually changes, derived from the
    /// program content itself so the text can never drift from the plan.
    static func experienceSummary(
        _ experience: ConditioningExperience,
        sparsHard: Bool
    ) -> ConditioningExperienceSummary {
        let rows = ConditioningProgramContent.phases.compactMap { phase -> ConditioningExperienceSummary.Row? in
            guard let target = ConditioningProgramContent.emphasisTarget(
                of: phase, experience: experience, sparsHard: sparsHard
            ) else { return nil }
            return ConditioningExperienceSummary.Row(
                id: phase.system,
                weeks: "conditioning.program.phase.weeks".localized(phase.weeks.lowerBound, phase.weeks.upperBound),
                title: phaseTitle(phase.system),
                value: "\(target.count) × \(volume(target))"
            )
        }
        return ConditioningExperienceSummary(
            sessionsPerWeek: ConditioningProgramContent.sessionsPerWeek(experience: experience, sparsHard: sparsHard),
            intro: "conditioning.program.experience.\(experience.rawValue).intro".localized,
            note: "conditioning.program.experience.\(experience.rawValue).note".localized,
            rows: rows
        )
    }

    /// "45 min" / "6 rounds" / "3 sets".
    static func volume(_ target: ConditioningProgramTarget) -> String {
        switch target.definition.volume {
        case .minutes: "conditioning.unit.minutes".localized(target.volume)
        case .rounds: "conditioning.program.volume.rounds".localized(target.volume)
        case .sets: "conditioning.program.volume.sets".localized(target.volume)
        }
    }

    /// "3 × Aerobic base · 45 min".
    static func targetLine(_ target: ConditioningProgramTarget) -> String {
        "\(target.count) × \(ConditioningCopy.title(target.session)) · \(volume(target))"
    }

    /// "Week 3 of 12", "Starts Mon, Sep 21", "Program complete", with "· Paused" when paused.
    static func status(_ status: ConditioningProgramStatus, calendar: Calendar = .current) -> String {
        switch status {
        case .notStarted(let startsOn):
            return "conditioning.program.status.starts".localized(day(startsOn, calendar: calendar))
        case .active(let week, _, let isPaused):
            let text = "conditioning.program.status.week".localized(week, ConditioningProgramContent.weekCount)
            return isPaused ? text + " · " + "conditioning.program.status.paused".localized : text
        case .completed:
            return "conditioning.program.status.completed.title".localized
        }
    }

    static func caution(_ caution: ConditioningSuggestionCaution) -> String {
        switch caution {
        case .afterLegWorkout(let notBefore):
            "conditioning.program.caution.legs".localized(notBefore.formatted(date: .omitted, time: .shortened))
        case .sparring:
            "conditioning.program.caution.sparring".localized
        }
    }

    static func restTitle(_ reason: ConditioningRestReason) -> String {
        switch reason {
        case .alreadyTrainedToday: "conditioning.program.rest.today.title".localized
        case .weekComplete: "conditioning.program.rest.week.title".localized
        case .lacticSpacing: "conditioning.program.rest.lactic.title".localized
        case .hardSessionCap: "conditioning.program.rest.cap.title".localized
        }
    }

    static func restDetail(_ reason: ConditioningRestReason) -> String {
        switch reason {
        case .alreadyTrainedToday: "conditioning.program.rest.today.detail".localized
        case .weekComplete: "conditioning.program.rest.week.detail".localized
        case .lacticSpacing(let until):
            "conditioning.program.rest.lactic.detail".localized(
                until.formatted(.dateTime.weekday(.wide).hour().minute())
            )
        case .hardSessionCap: "conditioning.program.rest.cap.detail".localized
        }
    }

    /// "Mon, Sep 21".
    static func day(_ day: ConditioningProgramDay, calendar: Calendar = .current) -> String {
        day.startDate(in: calendar).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    // MARK: - Post-workout add-on (docs/fight-conditioning.md, ticket 05)

    /// "Aerobic base · 45 min" — the session the add-on offers.
    static func addOnSession(_ target: ConditioningProgramTarget) -> String {
        "\(ConditioningCopy.title(target.session)) · \(volume(target))"
    }

    /// Why a hard session is better later, naming the earliest sensible time.
    static func addOnLaterDetail(notBefore: Date) -> String {
        "conditioning.addon.later.detail".localized(
            notBefore.formatted(date: .omitted, time: .shortened)
        )
    }

    /// "We'll remind you Thu, 18:30."
    static func addOnReminded(at date: Date) -> String {
        "conditioning.addon.reminded".localized(
            date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        )
    }

    static var addOnReminderTitle: String {
        "conditioning.addon.reminder.title".localized
    }

    static func addOnReminderBody(_ target: ConditioningProgramTarget) -> String {
        "conditioning.addon.reminder.body".localized(addOnSession(target))
    }
}

/// What one experience level means, for the enrollment screen.
struct ConditioningExperienceSummary: Equatable {
    struct Row: Identifiable, Equatable {
        let id: ConditioningEnergySystem
        let weeks: String
        let title: String
        let value: String
    }

    let sessionsPerWeek: Int
    let intro: String
    let note: String
    let rows: [Row]
}
