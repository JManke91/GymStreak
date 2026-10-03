//
//  RoutinesViewModel+Groups.swift
//  GymStreak
//
//  Groups the Routines tab's cards per installed program (docs/routine-programs.md).
//

import Foundation

/// One labelled section of routine cards below the "Up next" hero: an installed
/// program's routines, or the user's own (which includes the example routine).
struct RoutineCardGroup: Identifiable, Equatable {
    /// The program id, or nil for the user's own routines.
    let programId: String?
    /// Already localized; the view only uppercases it.
    let title: String
    let cards: [RoutineCardModel]

    var id: String { programId ?? "own" }
}

extension RoutinesViewModel {

    /// The sections, in catalog order, with the user's own routines last.
    ///
    /// Membership is a catalog lookup of the routine's `seedKey`, never a parse of
    /// the key, so a duplicate (`seedKey == ""`) and the example routine land in
    /// "Your routines". A program shows from its first routine on, partly installed
    /// or not. The hero is excluded from every group; a group left empty is dropped.
    /// The own-routines label reads "Your routines" once any program routine
    /// exists (the hero included) and "All routines" otherwise.
    static func makeCardGroups(
        routines: [Routine],
        heroId: UUID?,
        makeCard: (Routine) -> RoutineCardModel
    ) -> [RoutineCardGroup] {
        var programCards: [String: [RoutineCardModel]] = [:]
        var ownCards: [RoutineCardModel] = []
        var hasProgramRoutine = false

        for routine in routines {
            let program = RoutineProgramCatalog.program(forRoutineSeedKey: routine.seedKey)
            if program != nil { hasProgramRoutine = true }
            guard routine.id != heroId else { continue }
            if let program {
                programCards[program.id, default: []].append(makeCard(routine))
            } else {
                ownCards.append(makeCard(routine))
            }
        }

        var groups = RoutineProgramCatalog.programs.compactMap { program -> RoutineCardGroup? in
            guard let cards = programCards[program.id] else { return nil }
            return RoutineCardGroup(programId: program.id, title: programName(program.id), cards: cards)
        }
        if !ownCards.isEmpty {
            let title = (hasProgramRoutine ? "routines.own" : "routines.all").localized
            groups.append(RoutineCardGroup(programId: nil, title: title, cards: ownCards))
        }
        return groups
    }

    /// The hero eyebrow's program name; nil for a routine outside every program.
    static func heroProgramName(for routine: Routine?) -> String? {
        guard let routine,
              let program = RoutineProgramCatalog.program(forRoutineSeedKey: routine.seedKey)
        else { return nil }
        return programName(program.id)
    }

    private static func programName(_ programId: String) -> String {
        "routine_programs.\(programId).name".localized
    }
}
