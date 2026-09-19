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

/// What a session preview says about heart rate.
enum ConditioningHeartRateGuidance: Equatable {
    /// The session has no heart-rate guidance (intervals are steered by RPE).
    case none
    /// Alactic power: heart rate is never a target — cue maximal intent.
    case maximalIntent
    /// A heart-rate session, but no usable profile yet.
    case needsSetup
    /// The user takes heart-rate-affecting medication: RPE only.
    case rpeOnly
    case target(HeartRateTarget)
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
    @ObservationIgnored private let heartRateProfile: any HeartRateProfileStoring
    @ObservationIgnored private let makeRun: (ConditioningSessionPlan) -> ConditioningRunViewModel
    @ObservationIgnored let makeHeartRateEditor: () -> HeartRateProfileEditorViewModel

    init(
        safety: any ConditioningSafetyAcknowledging,
        heartRateProfile: any HeartRateProfileStoring,
        makeRun: @escaping (ConditioningSessionPlan) -> ConditioningRunViewModel,
        makeHeartRateEditor: @escaping () -> HeartRateProfileEditorViewModel
    ) {
        self.safety = safety
        self.heartRateProfile = heartRateProfile
        self.makeRun = makeRun
        self.makeHeartRateEditor = makeHeartRateEditor
    }

    /// Reads the profile store, which is `@Observable`, so a preview refreshes
    /// as soon as the editor sheet saves.
    func heartRateGuidance(for definition: ConditioningSessionDefinition) -> ConditioningHeartRateGuidance {
        if definition.energySystem == .alactic { return .maximalIntent }
        guard definition.effort == .conversational else { return .none }
        guard let profile = heartRateProfile.heartRateProfile else { return .needsSetup }
        if profile.usesHeartRateMedication { return .rpeOnly }
        return HeartRateZones.aerobicTarget(for: profile).map(ConditioningHeartRateGuidance.target) ?? .needsSetup
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
