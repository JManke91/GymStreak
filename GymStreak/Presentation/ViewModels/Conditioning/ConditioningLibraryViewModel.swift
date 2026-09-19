//
//  ConditioningLibraryViewModel.swift
//  GymStreak
//
//  The conditioning entry point: the session library, the structure preview,
//  the one-time safety acknowledgement and handing a plan to a runner.
//  See docs/fight-conditioning.md.
//

import Foundation
import Observation

/// One line of a session's structure preview.
struct ConditioningPreviewBlock: Equatable, Identifiable {
    let id: Int
    let title: String
    let detail: String?
}

struct ConditioningLibrarySection: Identifiable {
    let system: ConditioningEnergySystem
    let sessions: [ConditioningSessionDefinition]
    var id: ConditioningEnergySystem { system }
}

struct ConditioningPreview: Equatable {
    let blocks: [ConditioningPreviewBlock]
    let totalDuration: TimeInterval
}

@Observable
@MainActor
final class ConditioningLibraryViewModel {

    /// The library grouped by energy system, in program order. Built once — the
    /// library is a constant.
    let sections: [ConditioningLibrarySection] = ConditioningEnergySystem.allCases.map { system in
        ConditioningLibrarySection(
            system: system,
            sessions: ConditioningLibrary.sessions.filter { $0.energySystem == system }
        )
    }
    /// The session being run; the screen presents the runner while it is set.
    var activeRun: ConditioningRunViewModel?

    @ObservationIgnored private let safety: any ConditioningSafetyAcknowledging
    @ObservationIgnored private let makeRun: (ConditioningSessionPlan) -> ConditioningRunViewModel

    init(
        safety: any ConditioningSafetyAcknowledging,
        makeRun: @escaping (ConditioningSessionPlan) -> ConditioningRunViewModel
    ) {
        self.safety = safety
        self.makeRun = makeRun
    }

    /// Whether the runner must show the safety screen before starting.
    private(set) var needsSafetyAcknowledgement = false

    func start(_ plan: ConditioningSessionPlan) {
        needsSafetyAcknowledgement = !safety.hasAcknowledgedSafety
        activeRun = makeRun(plan)
    }

    func acknowledgeSafety() {
        safety.recordSafetyAcknowledged()
        needsSafetyAcknowledgement = false
    }

    func preview(for plan: ConditioningSessionPlan) -> ConditioningPreview {
        let definition = plan.definition
        let timeline = ConditioningTimeline(plan: plan)
        let effort = ConditioningCopy.effort(timeline.phases.first { $0.kind.isEffort }?.effort ?? definition.effort)
        var titles: [(String, String?)] = []

        if definition.warmUp > 0 {
            titles.append(("conditioning.preview.warm_up".localized, ConditioningCopy.duration(definition.warmUp)))
        }
        if let work = definition.work {
            let interval = "conditioning.preview.work_rest".localized(
                ConditioningCopy.duration(work), ConditioningCopy.duration(definition.rest)
            )
            switch definition.volume {
            case .sets(_, let reps):
                titles.append((
                    "conditioning.preview.sets".localized(plan.options.volume, reps) + " · " + interval,
                    "conditioning.preview.set_break".localized(ConditioningCopy.duration(definition.setBreak))
                        + " · " + effort
                ))
            case .rounds, .minutes:
                titles.append(("\(plan.options.volume) × " + interval, effort))
            }
        } else {
            titles.append((
                "conditioning.preview.steady".localized(ConditioningCopy.duration(TimeInterval(plan.options.volume * 60))),
                effort
            ))
        }
        if definition.coolDown > 0 {
            titles.append(("conditioning.preview.cool_down".localized, ConditioningCopy.duration(definition.coolDown)))
        }

        return ConditioningPreview(
            blocks: titles.enumerated().map { ConditioningPreviewBlock(id: $0.offset, title: $0.element.0, detail: $0.element.1) },
            totalDuration: timeline.totalDuration
        )
    }
}
